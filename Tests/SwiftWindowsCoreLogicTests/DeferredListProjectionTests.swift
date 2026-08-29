import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class DeferredListProjectionTests: XCTestCase {
    func testLargeForEachRetainsOneSegmentAndOnlyInvokesRequestedFactories() async {
        let recorder = DeferredProjectionRecorder()
        let rows = ForEach(Array(0..<10_000), id: \.self) { value in
            let _ = recorder.factories.append(value)
            DeferredProjectionLeaf(value: value, recorder: recorder)
        }
        XCTAssertTrue(recorder.factories.isEmpty)
        let projection = DeferredListProjection(rows)

        XCTAssertTrue(projection.isCurrent)
        XCTAssertTrue(projection.containsDeferredData)
        XCTAssertEqual(projection.count, 10_000)
        XCTAssertEqual(projection.segmentCount, 1)
        XCTAssertTrue(recorder.factories.isEmpty)
        XCTAssertTrue(recorder.bodies.isEmpty)
        XCTAssertEqual(projection.elements[9_999].sourceOrdinal, 9_999)
        XCTAssertEqual(projection.elements[9_999].implicitSelectionTag, AnyHashable(9_999))

        let first = projection.rowViews(for: 412)
        let second = projection.rowViews(for: 9_500)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(recorder.factories, [412, 9_500])
        XCTAssertTrue(recorder.bodies.isEmpty, "Projecting a selected row must not run its custom View body")
        XCTAssertTrue(projection.rowViews(for: -1).isEmpty)
        XCTAssertTrue(projection.rowViews(for: 10_000).isEmpty)
        XCTAssertEqual(recorder.factories, [412, 9_500])
    }

    func testPublicListBuilderDefersFactoriesUntilItsHostRequestsTheViewport() async throws {
        let recorder = DeferredProjectionRecorder()
        let list = List {
            ForEach(0..<10_000) { value in
                let _ = recorder.factories.append(value)
                DeferredProjectionLeaf(value: value, recorder: recorder)
            }
        }
        XCTAssertTrue(recorder.factories.isEmpty)
        XCTAssertTrue(recorder.bodies.isEmpty)

        let window = try DeferredProjectionWindow(list)
        defer { window.close() }

        XCTAssertFalse(recorder.factories.isEmpty)
        XCTAssertFalse(recorder.bodies.isEmpty)
        XCTAssertLessThan(recorder.factories.count, 256)
        XCTAssertLessThan(Set(recorder.factories).count, 100)
        XCTAssertFalse(recorder.factories.contains(9_999))
    }

    func testGroupsConditionalsAndStaticSiblingsDoNotForceListFactories() async {
        let recorder = DeferredProjectionRecorder()
        let includeRows = true
        let list = List {
            Text("before")
            Group {
                if includeRows {
                    ForEach(0..<1_000) { value in
                        let _ = recorder.factories.append(value)
                        DeferredProjectionLeaf(value: value, recorder: recorder)
                    }
                }
            }
            Text("after")
        }
        XCTAssertTrue(recorder.factories.isEmpty)
        XCTAssertTrue(recorder.bodies.isEmpty)
        withExtendedLifetime(list) {}
    }

    func testCanonicalArrayFinalizationRetainsDeferredSegments() async {
        let recorder = DeferredProjectionRecorder()
        let rows = deferredProjectionArray(recorder)
        XCTAssertTrue(recorder.factories.isEmpty)
        let projection = DeferredListProjection(rows)
        XCTAssertTrue(projection.containsDeferredData)
        XCTAssertEqual(projection.count, 1_002)
        XCTAssertTrue(recorder.factories.isEmpty)
        XCTAssertEqual(projection.rowViews(for: 27).count, 1)
        XCTAssertEqual(recorder.factories, [26])
    }

    func testEagerConsumerExpandsCanonicalCarriersWithoutRenumberingStaticMetadata() async throws {
        let recorder = DeferredProjectionRecorder()
        let authored = deferredProjectionMetadataArray(recorder)
        let erased = authored.map { AnyView(AnyView($0)) }
        XCTAssertTrue(recorder.factories.isEmpty)
        XCTAssertEqual(erased.filter(\.isDeferredViewListProjection).count, 1)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 400, height: 300) }, invalidateHandler: {})

        let expanded = try XCTUnwrap(materializedDeferredViewList(erased, context: context))

        XCTAssertEqual(expanded.count, 4)
        XCTAssertEqual(expanded.map(\.selectionTag), ["before", "tag 7", "tag 9", "after"].map(AnyHashable.init))
        XCTAssertEqual(expanded.first?.structuralIdentity, authored.first?.structuralIdentity)
        XCTAssertEqual(expanded.last?.structuralIdentity, authored.last?.structuralIdentity)
        XCTAssertEqual(expanded.dropFirst().dropLast().map { $0.tabItem?.count }, [1, 1])
        XCTAssertFalse(expanded.contains(where: \.isDeferredViewListProjection))
        XCTAssertEqual(recorder.factories, [7, 9])
        XCTAssertTrue(recorder.bodies.isEmpty)

        let repeated = try XCTUnwrap(materializedDeferredViewList(erased, context: context))
        XCTAssertEqual(repeated.map(\.structuralIdentity), expanded.map(\.structuralIdentity))
        XCTAssertEqual(recorder.factories, [7, 9])
        let rendered = makeRoot(VStack(spacing: 0) { return erased })
        defer { withExtendedLifetime(rendered.runtime) {} }
        XCTAssertEqual(rendered.node.children.map(\.text), ["before", "row 7", "row 9", "after"])
        XCTAssertEqual(recorder.factories, [7, 9])
        XCTAssertEqual(recorder.bodies, [7, 9])
    }

    func testPickerResolvesDeferredOptionsBeforeReadingTagsAndBuildingActions() async throws {
        let recorder = DeferredProjectionRecorder()
        var selection = 7
        let rows = ForEach([7, 9], id: \.self) { value in
            let _ = recorder.factories.append(value)
            Text("option \(value)").tag(value)
        }
        let options = projectedViewListPreservingDeferred(projectedViewList(rows))
        let picker = Picker("Mode", selection: Binding(get: { selection }, set: { selection = $0 })) {
            return options
        }.pickerStyle(.inline)
        XCTAssertTrue(recorder.factories.isEmpty)

        let rendered = makeRoot(picker)
        defer { withExtendedLifetime(rendered.runtime) {} }
        let optionContainer = try XCTUnwrap(rendered.node.children.last)
        XCTAssertEqual(optionContainer.children.count, 2)
        XCTAssertEqual(recorder.factories, [7, 9])
        let first = try XCTUnwrap(optionContainer.children.first)
        let second = try XCTUnwrap(optionContainer.children.last)
        XCTAssertEqual(first.borderWidth, 1)
        XCTAssertEqual(second.borderWidth, 0)
        try XCTUnwrap(second.onActivate)()
        XCTAssertEqual(selection, 9)
        XCTAssertEqual(recorder.factories, [7, 9])
    }

    func testEmptyAndMultipleOutputsAreResolvedOnlyForSelectedElement() async {
        let recorder = DeferredProjectionRecorder()
        let rows = ForEach(0..<3) { value in
            let _ = recorder.factories.append(value)
            if value == 0 {
                EmptyView()
            } else if value == 1 {
                Text("one")
            } else {
                Text("two.a")
                Text("two.b")
            }
        }
        let projection = DeferredListProjection(rows)
        XCTAssertEqual(projection.count, 3)
        XCTAssertTrue(recorder.factories.isEmpty)

        XCTAssertTrue(projection.rowViews(for: 0).isEmpty)
        XCTAssertTrue(projection.isCurrent, "An authored empty row is not a revoked source")
        let pair = projection.rowViews(for: 2)
        XCTAssertEqual(pair.count, 2)
        XCTAssertNotEqual(pair[0].structuralIdentity, pair[1].structuralIdentity)
        XCTAssertEqual(recorder.factories, [0, 2])
        XCTAssertEqual(projection.rowViews(for: 1).count, 1)
        XCTAssertEqual(recorder.factories, [0, 2, 1])
    }

    func testTypedKeysAndSiblingOccurrencesRemainDistinctAcrossReorder() async {
        let first = deferredProjectionIdentities([DeferredProjectionKey(1), DeferredProjectionKey(2)])
        let reordered = deferredProjectionIdentities([DeferredProjectionKey(2), DeferredProjectionKey(1)])
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(Set(first.elements.map(\.identity)).count, 5)
        XCTAssertEqual(first.elements[1].identity, reordered.elements[2].identity)
        XCTAssertEqual(first.elements[2].identity, reordered.elements[1].identity)
        XCTAssertNotEqual(first.elements[1].identity, first.elements[3].identity)

        let duplicates = DeferredListProjection(ForEach([1, 1], id: \.self) { Text(String($0)) })
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertNotEqual(duplicates.elements[0].identity, duplicates.elements[1].identity)

        let integers = DeferredListProjection(ForEach([Int(1)], id: \.self) { Text(String($0)) })
        let unsigned = DeferredListProjection(ForEach([UInt(1)], id: \.self) { Text(String($0)) })
        XCTAssertNotEqual(integers.elements[0].identity, unsigned.elements[0].identity)
    }

    func testConcreteRowBuilderTypeParticipatesInLogicalIdentity() async {
        let text = DeferredListProjection(ForEach([1], id: \.self) { _ in Text("one") })
        let empty = DeferredListProjection(ForEach([1], id: \.self) { _ in EmptyView() })
        XCTAssertNotEqual(text.elements[0].identity, empty.elements[0].identity)
    }

    func testExplicitArrayMaterializationIsCachedAndKeepsRowsAndEditMetadata() async throws {
        let recorder = DeferredProjectionRecorder()
        var deleted: [[Int]] = []
        var moved: [([Int], Int)] = []
        var inserted: [(Int, Int)] = []
        var dropped: [Int] = []
        let rows = ForEach([7, 9], id: \.self) { value in
            let _ = recorder.factories.append(value)
            Text("row \(value)").tag("tag \(value)")
        }
        .onDelete { deleted.append(Array($0)) }
        .onMove { moved.append((Array($0), $1)) }
        .onInsert(of: ["public.text"]) { inserted.append(($0, $1.count)) }
        .dropDestination(for: DeferredProjectionPayload.self) { payloads, _ in
            dropped.append(contentsOf: payloads.map(\.value))
        }
        XCTAssertTrue(recorder.factories.isEmpty)
        let expression = WindowsArrayViewBuilder.buildExpression(rows)
        XCTAssertEqual(expression.count, 2)
        XCTAssertEqual(recorder.factories, [7, 9])
        XCTAssertEqual(rows.contentViews.count, 2)
        XCTAssertEqual(recorder.factories, [7, 9])
        XCTAssertEqual(expression.map(\.selectionTag), [AnyHashable("tag 7"), AnyHashable("tag 9")])
        let rendered = makeRoot(VStack { expression })
        defer { withExtendedLifetime(rendered.runtime) {} }
        XCTAssertEqual(rendered.node.children.map(\.text), ["row 7", "row 9"])
        XCTAssertEqual(rendered.node.children.map(\.dynamicContentIndex), [0, 1])
        XCTAssertEqual(recorder.factories, [7, 9])
        let last = try XCTUnwrap(rendered.node.children.last)
        try XCTUnwrap(last.onDeleteRows)(IndexSet(integer: 1))
        try XCTUnwrap(last.onMoveRows)(IndexSet(integer: 1), 0)
        try XCTUnwrap(last.onInsertRows)(1, [NSItemProvider()])
        try XCTUnwrap(last.onDropRows)([DeferredProjectionPayload(value: 42)], 1)
        XCTAssertEqual(deleted, [[1]])
        XCTAssertEqual(moved.map { $0.0 }, [[1]])
        XCTAssertEqual(moved.map { $0.1 }, [0])
        XCTAssertEqual(inserted.map { $0.0 }, [1])
        XCTAssertEqual(inserted.map { $0.1 }, [1])
        XCTAssertEqual(dropped, [42])
    }

    func testBindingForEachConstructsSelectedBindingAndWritesByCurrentKey() async throws {
        var values = [DeferredProjectionItem(id: 1, value: "one"), DeferredProjectionItem(id: 2, value: "two")]
        let source = Binding(get: { values }, set: { values = $0 })
        var bindings: [Int: Binding<DeferredProjectionItem>] = [:]
        var calls = 0
        let rows = ForEach(source) { binding in
            calls += 1
            let value = binding.wrappedValue
            bindings[value.id] = binding
            return [AnyView(Text(value.value))]
        }
        let projection = DeferredListProjection(rows)
        XCTAssertEqual(rows.data.count, 2)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(bindings.isEmpty)
        XCTAssertEqual(projection.rowViews(for: 1).count, 1)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(bindings.count, 1)

        let selected = try XCTUnwrap(bindings[2])
        values.swapAt(0, 1)
        selected.wrappedValue = DeferredProjectionItem(id: 2, value: "updated")
        XCTAssertEqual(values.map(\.id), [2, 1])
        XCTAssertEqual(values.map(\.value), ["updated", "one"])

        values.removeFirst()
        selected.wrappedValue = DeferredProjectionItem(id: 2, value: "stale")
        XCTAssertEqual(values.map(\.value), ["one"])
        XCTAssertFalse(projection.isCurrent)
        values.append(DeferredProjectionItem(id: 2, value: "replacement"))
        selected.wrappedValue = DeferredProjectionItem(id: 2, value: "stale again")
        XCTAssertEqual(values.last?.value, "replacement")
    }

    func testReferenceModelKeyDriftRevokesProjectionInsteadOfPublishingEmptyRow() async {
        let item = DeferredProjectionReferenceItem(id: 7)
        var calls = 0
        let rows = ForEach([item]) { element in
            calls += 1
            element.id = 8
            return [AnyView(Text("obsolete"))]
        }
        let projection = DeferredListProjection(rows)
        XCTAssertTrue(projection.isCurrent)
        XCTAssertTrue(projection.rowViews(for: 0).isEmpty)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(projection.isCurrent)
        XCTAssertTrue(projection.rowViews(for: 0).isEmpty)
        XCTAssertEqual(calls, 1)
    }

    func testReferenceModelKeyDriftBeforeRequestDoesNotInvokeFactory() async {
        let item = DeferredProjectionReferenceItem(id: 7)
        var calls = 0
        let projection = DeferredListProjection(
            ForEach([item]) { _ in
                calls += 1
                return [AnyView(Text("obsolete"))]
            })
        item.id = 8
        XCTAssertTrue(projection.rowViews(for: 0).isEmpty)
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(projection.isCurrent)
    }

    func testInactiveDeclarationWalkDoesNotInvokeDeferredFactories() async {
        let recorder = DeferredProjectionRecorder()
        let rows = ForEach(0..<100) { value in
            let _ = recorder.factories.append(value)
            DeferredProjectionLeaf(value: value, recorder: recorder)
        }
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 400, height: 300) }, invalidateHandler: {})
        let scopes = declaredProjectedViewListScopes(projectedViewList(rows), context: context)
        XCTAssertFalse(scopes.isEmpty)
        XCTAssertTrue(recorder.factories.isEmpty)
        XCTAssertTrue(recorder.bodies.isEmpty)
    }

    private func makeRoot<Content: View>(_ content: Content) -> (runtime: RetainedViewRuntime, node: ViewNode) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 400, height: 300) }, invalidateHandler: {})
        return (runtime, AnyView(content).makeComponent(context: context).makeNode(runtime: runtime))
    }
}

@MainActor
private final class DeferredProjectionRecorder {
    var factories: [Int] = []
    var bodies: [Int] = []
}

@MainActor
private struct DeferredProjectionLeaf: View {
    let value: Int
    let recorder: DeferredProjectionRecorder

    var body: some View {
        let _ = recorder.bodies.append(value)
        Text("row \(value)")
    }
}

private struct DeferredProjectionKey: Hashable, CustomStringConvertible {
    let value: Int
    init(_ value: Int) { self.value = value }
    var description: String { "same display label" }
}

private struct DeferredProjectionItem: Identifiable {
    let id: Int
    let value: String
}

private struct DeferredProjectionPayload: Transferable {
    let value: Int
}

private final class DeferredProjectionReferenceItem: Identifiable {
    var id: Int
    init(id: Int) { self.id = id }
}

@MainActor
@ViewBuilder
private func deferredProjectionArray(_ recorder: DeferredProjectionRecorder) -> [AnyView] {
    Text("before")
    ForEach(0..<1_000) { value in
        let _ = recorder.factories.append(value)
        DeferredProjectionLeaf(value: value, recorder: recorder)
    }
    Text("after")
}

@MainActor
@ViewBuilder
private func deferredProjectionMetadataArray(_ recorder: DeferredProjectionRecorder) -> [AnyView] {
    Text("before").tag("before")
    ForEach([7, 9], id: \.self) { value in
        let _ = recorder.factories.append(value)
        DeferredProjectionLeaf(value: value, recorder: recorder)
            .tag("tag \(value)")
            .tabItem { Text("tab \(value)") }
    }
    Text("after").tag("after")
}

@MainActor
private func deferredProjectionIdentities(_ keys: [DeferredProjectionKey]) -> DeferredListProjection {
    DeferredListProjection(
        TupleView(
            (
                Text("before"),
                ForEach(keys, id: \.self) { Text(String($0.value)) },
                ForEach([DeferredProjectionKey(1)], id: \.self) { Text(String($0.value)) },
                Text("after")
            )))
}

@MainActor
private final class DeferredProjectionWindow {
    private let host: WinSwiftUIWindowHost
    private let window: Win32Window
    private let clock: RuntimeTestClock

    init<Content: View>(_ content: Content) throws {
        let configuration = WindowGroupConfiguration(
            title: "Deferred List projection", size: IntSize(width: 400, height: 300), clearColor: .black,
            content: [AnyView(content)])
        let clock = RuntimeTestClock()
        clock.now = 8_100
        let handle = try XCTUnwrap(NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1)))
        let surface = SurfaceDescriptor(windowHandle: handle, pixelSize: configuration.size, scaleFactor: 1)
        let window = Win32Window(title: configuration.title, clientSize: configuration.size)
        let host = WinSwiftUIWindowHost(
            configuration: configuration, platformWindow: window,
            renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.host = host
        self.window = window
        self.clock = clock
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
        }
    }

    func close() { host.windowWillClose(window) }
}
