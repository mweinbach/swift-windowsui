import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class PublicLazyListBindingTests: XCTestCase {
    func testMutableDataFactoriesAreDeferredAndPublishRealElementAndSelectionWrites() async throws {
        for builder in [false, true] {
            let probe = PublicBoundListProbe(count: 10_000, builder: builder)
            let host = MountedLazyListTestHost { PublicBoundListRoot(probe: probe) }
            defer { host.close() }
            XCTAssertTrue(probe.factories.isEmpty)
            XCTAssertEqual(try XCTUnwrap(try host.list().retainedLazyListAdapter).logicalRecordCount, 10_000)

            XCTAssertNotNil(host.layout())
            XCTAssertLessThan(probe.factories.count, 128)
            XCTAssertNil(probe.rowBindings[9000])
            let first = try XCTUnwrap(probe.rowBindings[0])
            first.wrappedValue = PublicBoundListRow(id: 0, value: "Edited")
            XCTAssertNotNil(host.layout())
            XCTAssertEqual(try XCTUnwrap(probe.values).wrappedValue.first?.value, "Edited")
            XCTAssertEqual(host.find("public.bound.0")?.text, "Edited")

            try host.rowRoot("public.bound.0").onActivate?()
            XCTAssertEqual(probe.selected, [builder ? 100_000 : 0])
            XCTAssertEqual(probe.selectionWrites.count, 1)
            XCTAssertLessThan(try XCTUnwrap(try host.list().retainedLazyListAdapter).mountedRecordCount, 32)
        }
    }

    func testEscapedElementBindingWritesTheCurrentKeyAfterReorderWhileCold() async throws {
        for builder in [false, true] {
            let probe = PublicBoundListProbe(count: 1000, builder: builder)
            let host = MountedLazyListTestHost { PublicBoundListRoot(probe: probe) }
            defer { host.close() }
            XCTAssertNotNil(host.layout())
            let first = try XCTUnwrap(probe.rowBindings[0])
            let values = try XCTUnwrap(probe.values)
            try host.scroll(to: 4000)
            let firstFactories = probe.factories.filter { $0 == 0 }.count
            var reordered = values.wrappedValue
            reordered.swapAt(0, 1)
            values.wrappedValue = reordered
            XCTAssertNotNil(host.layout())

            first.wrappedValue = PublicBoundListRow(id: 0, value: "Cold edit")
            XCTAssertNotNil(host.layout())

            XCTAssertEqual(values.wrappedValue[0].id, 1)
            XCTAssertEqual(values.wrappedValue[1].id, 0)
            XCTAssertEqual(values.wrappedValue[1].value, "Cold edit")
            XCTAssertNil(host.find("public.bound.0"))
            XCTAssertEqual(probe.factories.filter { $0 == 0 }.count, firstFactories)
            try host.scroll(to: 0)
            XCTAssertEqual(host.find("public.bound.0")?.text, "Cold edit")
        }
    }

    func testObservedRemovalAndReinsertCannotReviveAnEscapedElementBinding() async throws {
        for builder in [false, true] {
            let probe = PublicBoundListProbe(count: 1000, builder: builder)
            let host = MountedLazyListTestHost { PublicBoundListRoot(probe: probe) }
            defer { host.close() }
            XCTAssertNotNil(host.layout())
            let first = try XCTUnwrap(probe.rowBindings[0])
            let values = try XCTUnwrap(probe.values)
            try host.scroll(to: 4000)
            values.wrappedValue.removeAll { $0.id == 0 }
            XCTAssertNotNil(host.layout())
            values.wrappedValue.insert(PublicBoundListRow(id: 0, value: "Fresh"), at: 0)
            XCTAssertNotNil(host.layout())
            let invalidations = host.events.stateInvalidations

            first.wrappedValue = PublicBoundListRow(id: 0, value: "Stale write")

            XCTAssertEqual(values.wrappedValue.first?.value, "Fresh")
            XCTAssertEqual(host.events.stateInvalidations, invalidations)
            try host.scroll(to: 0)
            XCTAssertEqual(host.find("public.bound.0")?.text, "Fresh")
        }
    }
}

private struct PublicBoundListRow: Identifiable {
    let id: Int
    let value: String
}

@MainActor
private final class PublicBoundListProbe {
    let count: Int
    let builder: Bool
    var values: Binding<[PublicBoundListRow]>?
    var rowBindings: [Int: Binding<PublicBoundListRow>] = [:]
    var factories: [Int] = []
    var selected: Set<Int> = []
    var selectionWrites: [Set<Int>] = []

    init(count: Int, builder: Bool) {
        self.count = count
        self.builder = builder
    }

    var selection: Binding<Set<Int>> {
        Binding(
            get: { self.selected },
            set: {
                self.selected = $0
                self.selectionWrites.append($0)
            })
    }

    func content(_ binding: Binding<PublicBoundListRow>) -> [AnyView] {
        let row = binding.wrappedValue
        factories.append(row.id)
        rowBindings[row.id] = binding
        return [
            AnyView(
                Text(row.value).accessibilityIdentifier("public.bound.\(row.id)")
                    .frame(width: 110, height: 24)
                    .tag(row.id + 100_000))
        ]
    }
}

@MainActor
private struct PublicBoundListRoot: View {
    @State private var values: [PublicBoundListRow]
    let probe: PublicBoundListProbe

    init(probe: PublicBoundListProbe) {
        self.probe = probe
        _values = State(wrappedValue: (0..<probe.count).map { PublicBoundListRow(id: $0, value: "Row \($0)") })
    }

    var body: some View {
        probe.values = $values
        return content
    }

    @ViewBuilder private var content: some View {
        if probe.builder {
            List(selection: probe.selection) { ForEach($values, content: probe.content) }
        } else {
            List($values, id: \.id, selection: probe.selection, rowContent: probe.content)
        }
    }
}
