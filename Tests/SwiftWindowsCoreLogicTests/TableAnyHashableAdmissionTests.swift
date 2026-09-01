import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class TableAnyHashableAdmissionTests: XCTestCase {
    func testFirstRowErasureStopsBeforeRetainedKeyOrLaterRowWork() async throws {
        try assertTableRejection(on: "erase.row.1", rowErasures: 1, selectedErasures: 0, selectionReads: 0)
    }

    func testSecondRowErasureCannotAcquireNewSelectionLookupAuthority() async throws {
        try assertTableRejection(on: "erase.row.2", rowErasures: 2, selectedErasures: 0, selectionReads: 0)
    }

    func testTableSelectionGetterMustReturnCurrentBeforeCustomErasure() async throws {
        try assertTableRejection(on: "selection.get", rowErasures: 2, selectedErasures: 0, selectionReads: 1)
    }

    func testTableSelectedValueErasureMustReturnCurrentBeforeCells() async throws {
        try assertTableRejection(on: "erase.selected.1", rowErasures: 2, selectedErasures: 1, selectionReads: 1)
    }

    func testSharedSingleSelectionGettersStopBeforeCustomErasure() async throws {
        try assertSharedSelectionRejection(on: "selection.get", expectedErasures: 0)
    }

    func testSharedSingleSelectionErasuresStopBeforeConsumerCallbacks() async throws {
        try assertSharedSelectionRejection(on: "erase.selected.1", expectedErasures: 1)
    }

    func testDeferredSelectionUsesItsOriginalReceiptAcrossGetterAndErasure() async throws {
        for required in [false, true] {
            for trigger in ["selection.get", "erase.selected.1"] {
                let probe = TableErasureProbe()
                let row = ViewNode(isFocusable: true, accessibilityTraits: .isSelectable)
                row.interceptsVerticalArrowKeys = true
                let container = ViewNode(scrollAxis: .vertical, children: [row])
                let runtime = RetainedViewRuntime(root: container)
                let scope = RetainedListNavigationOwner(runtime: runtime)
                scope.install(on: container)
                let owner = scope.makeRowOwner(on: row)
                defer {
                    probe.disarm()
                    runtime.stopRenderLifecycleCallbacks()
                    runtime.cancelRenderLifecycleTasks()
                }
                XCTAssertTrue(
                    DeferredListScrollSource.install(
                        on: container, rows: [(implicitID: nil, providerKey: .init(0))], isCurrent: { true }))
                let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
                XCTAssertTrue(provider.replaceData([0], id: \.self) { _ in [row] })
                let adapter = try XCTUnwrap(
                    RetainedLazyListRuntimeAdapter(
                        provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                        maximumMountedRecords: 4, maximumMountedLeaves: 8, maximumProtectedRecords: 1))
                let binding = try XCTUnwrap(adapter.installNavigationContainer(in: runtime))
                container.retainedLazyListAdapter = adapter
                XCTAssertTrue(binding.node === container)
                let navigation = DeferredListKeyboardNavigation(
                    runtime: runtime, container: binding, scope: scope, prefersImplicitSelectionTag: true)
                let mode = probe.selectionMode(required: required)
                var invalidations = 0
                probe.arm(on: trigger) { scope.revoke() }

                navigation.moveSelection(
                    mode, from: owner, sourceTag: nil, ordinal: nil, leaf: nil, delta: 1,
                    invalidate: { invalidations += 1 })
                probe.disarm()

                let expected = trigger == "selection.get" ? ["selection.get"] : ["selection.get", "erase.selected.1"]
                XCTAssertEqual(probe.events, expected, "required=\(required), trigger=\(trigger)")
                XCTAssertEqual(probe.hookCalls, 1, "The real deferred receipt must admit the getter")
                XCTAssertTrue(probe.callbacksAfterHook.isEmpty)
                XCTAssertEqual(invalidations, 0)
                XCTAssertNil(scope.prepareAction(from: owner))
            }
        }
    }

    func testLegalCustomAndFallbackErasuresPreserveTypedRowsAndChildState() async throws {
        for lazy in [false, true] {
            for customRepresentation in [false, true] {
                let fixture = try TableErasureFixture(lazy: lazy)
                let probe = TableErasureProbe()
                defer {
                    probe.disarm()
                    fixture.close()
                }
                let key = TableErasureKey(
                    value: 1, label: "row", customRepresentation: customRepresentation, probe: probe)
                let later = TableErasureKey(
                    value: 2, label: "later", customRepresentation: customRepresentation, probe: probe)
                let selected = TableErasureKey(
                    value: 1, label: "selected", customRepresentation: customRepresentation, probe: probe)
                let rows = [
                    TableErasureRow(identity: key, name: "row", probe: probe),
                    TableErasureRow(identity: later, name: "later", probe: probe),
                ]
                let table = makeTable(rows: rows, selection: probe.selection(selected), probe: probe)
                probe.arm()
                let output = makeViewComponent(table, context: fixture.context).makeNode(runtime: fixture.runtime)
                probe.disarm()

                XCTAssertFalse(output.containsRejectedRetainedSource)
                XCTAssertEqual(probe.erasureCounts, ["row": 2, "later": 2, "selected": 2])
                XCTAssertEqual(probe.events.filter { $0.hasPrefix("row.id.") }, ["row.id.row", "row.id.later"])
                XCTAssertEqual(
                    probe.events.filter { $0.hasPrefix("body.") }, ["body.header", "body.cell.row", "body.cell.later"])
                XCTAssertEqual(probe.installedValues, [23, 23, 23])
                XCTAssertEqual(output.children.count, 3)
                XCTAssertEqual(
                    output.children.dropFirst().map { $0.accessibilityTraits.contains(.isSelected) }, [true, false])
                let identity = try XCTUnwrap(output.children.dropFirst().first?.retainedViewIdentity)
                XCTAssertTrue(identity.segments.contains(.keyed(RetainedViewIdentity.Key(key))))
                XCTAssertFalse(identity.segments.contains(.keyed(RetainedViewIdentity.Key(AnyHashable(key)))))
                XCTAssertTrue(fixture.build.canAdopt)
            }
        }
    }

    func testOptionalNilRowIdentityAndNilSelectionRemainValues() async throws {
        for (lazy, selectsNil) in [(false, false), (false, true), (true, false), (true, true)] {
            let fixture = try TableErasureFixture(lazy: lazy)
            let probe = TableErasureProbe()
            defer {
                probe.disarm()
                fixture.close()
            }
            let rows = [
                TableErasureRow(identity: Optional<Int>.none, name: "nil", probe: probe),
                TableErasureRow(identity: Optional<Int>.some(7), name: "number", probe: probe),
            ]
            let selection = Binding<Int??>(
                get: {
                    probe.record("selection.get")
                    return selectsNil ? .some(Optional<Int>.none) : .none
                }, set: { _ in probe.record("selection.set") })
            let table = makeTable(rows: rows, selection: selection, probe: probe)
            probe.arm()
            let output = makeViewComponent(table, context: fixture.context).makeNode(runtime: fixture.runtime)
            probe.disarm()

            XCTAssertFalse(output.containsRejectedRetainedSource)
            XCTAssertEqual(output.children.count, 3)
            XCTAssertEqual(probe.events.filter { $0 == "selection.get" }.count, 2)
            XCTAssertFalse(probe.events.contains("selection.set"))
            XCTAssertEqual(probe.installedValues, [23, 23, 23])
            XCTAssertEqual(
                output.children.dropFirst().map { $0.accessibilityTraits.contains(.isSelected) }, [selectsNil, false])
            let identity = try XCTUnwrap(output.children.dropFirst().first?.retainedViewIdentity)
            XCTAssertTrue(identity.segments.contains(.keyed(RetainedViewIdentity.Key(Optional<Int>.none))))
            XCTAssertTrue(fixture.build.canAdopt)
        }
    }

    func testNilSingleSelectionStillAllowsActivationAndMovement() async throws {
        for consumer in TableErasureConsumer.allCases {
            let probe = TableErasureProbe()
            let target = AnyHashable(TableErasureKey(value: 2, label: "target", probe: probe))
            let indices: ManagedKeyedMap<RetainedViewIdentity.Key, Int> = [.init(target): 0]
            var selected: TableErasureKey? = nil
            let mode = ListSelectionMode.single(
                Binding<TableErasureKey?>(
                    get: {
                        probe.record("selection.get")
                        return selected
                    },
                    set: {
                        probe.record("selection.set")
                        selected = $0
                    }))
            probe.arm()
            let changed = consumer.call(mode, target: target, indices: indices, isCurrent: { true }, probe: probe)
            probe.disarm()

            XCTAssertEqual(changed, consumer != .contains)
            XCTAssertEqual(probe.events.filter { $0 == "selection.get" }.count, 1)
            XCTAssertTrue(probe.erasureCounts.isEmpty)
            XCTAssertEqual(selected?.value, consumer == .contains ? nil : 2)
            XCTAssertEqual(probe.events.filter { $0 == "selection.set" }.count, consumer == .contains ? 0 : 1)
            XCTAssertEqual(probe.events.filter { $0 == "target.prepare" }.count, consumer == .move ? 1 : 0)
        }
    }

    func testRequiredSingleFallbackErasureKeepsTypedSelectionWrites() async throws {
        for consumer in TableErasureConsumer.allCases {
            let probe = TableErasureProbe()
            let target = AnyHashable(
                TableErasureKey(value: consumer == .contains ? 1 : 2, label: "target", probe: probe))
            let indices: ManagedKeyedMap<RetainedViewIdentity.Key, Int> = [.init(target): 0]
            var selected = TableErasureKey(value: 1, label: "selected", probe: probe)
            let mode = ListSelectionMode.requiredSingle(
                Binding<TableErasureKey>(
                    get: {
                        probe.record("selection.get")
                        return selected
                    },
                    set: {
                        probe.record("selection.set")
                        selected = $0
                    }))
            probe.arm()
            let changed = consumer.call(mode, target: target, indices: indices, isCurrent: { true }, probe: probe)
            probe.disarm()

            XCTAssertTrue(changed)
            XCTAssertEqual(probe.erasureCounts, ["selected": 1])
            XCTAssertEqual(probe.events.filter { $0 == "selection.get" }.count, 1)
            XCTAssertEqual(selected.value, consumer == .contains ? 1 : 2)
            XCTAssertEqual(probe.events.filter { $0 == "selection.set" }.count, consumer == .contains ? 0 : 1)
        }
    }

    func testRequiredSingleOptionalNilIsASelectedValueForEveryConsumer() async throws {
        for consumer in TableErasureConsumer.allCases {
            var selected: Int? = nil
            var reads = 0
            var writes = 0
            let mode = ListSelectionMode.requiredSingle(
                Binding<Int?>(
                    get: {
                        reads += 1
                        return selected
                    },
                    set: {
                        writes += 1
                        selected = $0
                    }))
            let nilTag = AnyHashable(Optional<Int>.none)
            let nextTag = AnyHashable(Optional<Int>.some(7))
            switch consumer {
            case .contains:
                XCTAssertTrue(mode.contains(nilTag))
            case .activate:
                XCTAssertTrue(mode.activate(nextTag))
            case .move:
                let indices: ManagedKeyedMap<RetainedViewIdentity.Key, Int> = [.init(nilTag): 0, .init(nextTag): 1]
                XCTAssertEqual(
                    mode.moveSelection(
                        within: [nilTag, nextTag], indicesByTag: indices, delta: 1,
                        isCurrent: { true }, prepareTarget: { _ in true }), nextTag)
            }
            XCTAssertEqual(reads, 1)
            XCTAssertEqual(writes, consumer == .contains ? 0 : 1)
            XCTAssertEqual(selected, consumer == .contains ? nil : 7)
        }
    }

    private func makeTable<ID: Hashable>(
        rows: [TableErasureRow<ID>], selection: Binding<ID?>?, probe: TableErasureProbe
    ) -> Table<TableErasureCollection<ID>> {
        Table(TableErasureCollection(rows: rows, probe: probe), selection: selection) {
            AnyTableColumn<TableErasureRow<ID>>(
                title: "Value", cellBuilder: { row in [probe.built("cell.\(row.name)")] },
                headerBuilder: { [probe.built("header")] })
        }
    }

    private func assertTableRejection(
        on trigger: String, rowErasures: Int, selectedErasures: Int, selectionReads: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for lazy in [false, true] {
            for stop in TableErasureStop.allCases {
                let fixture = try TableErasureFixture(lazy: lazy)
                let probe = TableErasureProbe()
                defer {
                    probe.disarm()
                    fixture.close()
                }
                let key = TableErasureKey(value: 1, label: "row", probe: probe)
                let later = TableErasureKey(value: 2, label: "later", probe: probe)
                let selected = TableErasureKey(value: 1, label: "selected", probe: probe)
                let table = makeTable(
                    rows: [
                        TableErasureRow(identity: key, name: "row", probe: probe),
                        TableErasureRow(identity: later, name: "later", probe: probe),
                    ], selection: probe.selection(selected), probe: probe)
                var nested: TableErasureNestedState?
                probe.arm(on: trigger) {
                    switch stop {
                    case .close: fixture.closeAuthority()
                    case .nestedInstallation: nested = try? fixture.installSibling()
                    }
                }
                let output = makeViewComponent(table, context: fixture.context).makeNode(runtime: fixture.runtime)
                probe.disarm()

                let scenario = "\(trigger), lazy=\(lazy), stop=\(stop)"
                XCTAssertEqual(probe.hookCalls, 1, scenario, file: file, line: line)
                XCTAssertTrue(output.containsRejectedRetainedSource, scenario, file: file, line: line)
                XCTAssertTrue(
                    probe.callbacksAfterHook.isEmpty, "\(scenario): \(probe.callbacksAfterHook)", file: file, line: line
                )
                XCTAssertEqual(probe.erasureCounts["row", default: 0], rowErasures, scenario, file: file, line: line)
                XCTAssertEqual(
                    probe.erasureCounts["selected", default: 0], selectedErasures, scenario, file: file, line: line)
                XCTAssertEqual(probe.erasureCounts["later", default: 0], 0, scenario, file: file, line: line)
                XCTAssertEqual(
                    probe.events.filter { $0 == "selection.get" }.count, selectionReads, scenario, file: file,
                    line: line)
                XCTAssertEqual(
                    probe.events.filter { $0.hasPrefix("build.") }, ["build.header"], scenario, file: file, line: line)
                XCTAssertEqual(
                    probe.events.filter { $0.hasPrefix("body.") }, ["body.header"], scenario, file: file, line: line)
                if lazy {
                    XCTAssertFalse(
                        try XCTUnwrap(probe.originalLazy, file: file, line: line).isCurrent, file: file, line: line)
                } else {
                    XCTAssertFalse(
                        try XCTUnwrap(probe.originalDescriptor, file: file, line: line).canConstruct, file: file,
                        line: line)
                }
                if stop == .nestedInstallation {
                    try assertNestedOwner(nested, fixture: fixture, file: file, line: line)
                }
            }
        }
    }

    private func assertSharedSelectionRejection(
        on trigger: String, expectedErasures: Int, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for required in [false, true] {
            for consumer in TableErasureConsumer.allCases {
                for stop in TableErasureStop.allCases {
                    let fixture = try TableErasureFixture()
                    let probe = TableErasureProbe()
                    defer {
                        probe.disarm()
                        fixture.close()
                    }
                    let target = AnyHashable(TableErasureKey(value: 2, label: "target", probe: probe))
                    let indices: ManagedKeyedMap<RetainedViewIdentity.Key, Int> = [.init(target): 0]
                    let mode = probe.selectionMode(required: required)
                    let context = try XCTUnwrap(
                        fixture.coordinator.contextForDescriptorComponent(from: fixture.context))
                    let attribution = try XCTUnwrap(context.viewIdentity.descriptorComponent)
                    let lookup = try XCTUnwrap(fixture.coordinator.descriptorLookupReceipt(for: attribution))
                    var nested: TableErasureNestedState?
                    probe.arm(on: trigger) {
                        switch stop {
                        case .close: fixture.closeAuthority()
                        case .nestedInstallation: nested = try? fixture.installSibling()
                        }
                    }
                    let changed = consumer.call(
                        mode, target: target, indices: indices, isCurrent: { lookup.isCurrent }, probe: probe)
                    probe.disarm()

                    let scenario = "\(trigger), required=\(required), consumer=\(consumer), stop=\(stop)"
                    let expected = expectedErasures == 0 ? ["selection.get"] : ["selection.get", "erase.selected.1"]
                    XCTAssertFalse(changed, scenario, file: file, line: line)
                    XCTAssertEqual(probe.hookCalls, 1, scenario, file: file, line: line)
                    XCTAssertEqual(probe.events, expected, scenario, file: file, line: line)
                    XCTAssertEqual(
                        probe.erasureCounts["selected", default: 0], expectedErasures, scenario, file: file, line: line)
                    XCTAssertFalse(lookup.isCurrent, scenario, file: file, line: line)
                    if stop == .nestedInstallation {
                        try assertNestedOwner(nested, fixture: fixture, file: file, line: line)
                    }
                }
            }
        }
    }

    private func assertNestedOwner(
        _ nested: TableErasureNestedState?, fixture: TableErasureFixture,
        file: StaticString, line: UInt
    ) throws {
        let nested = try XCTUnwrap(nested, file: file, line: line)
        XCTAssertTrue(fixture.build.canAdopt, file: file, line: line)
        XCTAssertTrue(nested.owner.isInstallationActive, file: file, line: line)
        XCTAssertEqual(nested.value.wrappedValue, 23, file: file, line: line)
        nested.value.wrappedValue = 71
        XCTAssertEqual(nested.value.wrappedValue, 71, file: file, line: line)
    }
}

private enum TableErasureStop: CaseIterable, Equatable {
    case close
    case nestedInstallation
}

private enum TableErasureConsumer: CaseIterable, Equatable {
    case contains
    case activate
    case move

    @MainActor
    func call(
        _ mode: ListSelectionMode, target: AnyHashable,
        indices: ManagedKeyedMap<RetainedViewIdentity.Key, Int>,
        isCurrent: () -> Bool, probe: TableErasureProbe
    ) -> Bool {
        switch self {
        case .contains:
            return mode.contains(target, isCurrent: isCurrent)
        case .activate:
            return mode.activate(target, isCurrent: isCurrent)
        case .move:
            return mode.moveSelection(
                within: [target], indicesByTag: indices, delta: 1, isCurrent: isCurrent,
                prepareTarget: { _ in
                    probe.record("target.prepare")
                    return true
                }) != nil
        }
    }
}

@MainActor
private final class TableErasureProbe {
    private var recording = false
    private var trigger: String?
    private var hook: (@MainActor () -> Void)?
    private(set) var events: [String] = []
    private(set) var callbacksAfterHook: [String] = []
    private(set) var erasureCounts: [String: Int] = [:]
    private(set) var installedValues: [Int] = []
    private(set) var hookCalls = 0
    private(set) var originalDescriptor: RetainedDescriptorComponentAttribution?
    private(set) var originalLazy: LazyListViewAttribution?

    func arm(on trigger: String? = nil, hook: (@MainActor () -> Void)? = nil) {
        recording = true
        self.trigger = trigger
        self.hook = hook
    }

    func disarm() {
        recording = false
        hook = nil
    }

    func record(_ event: String) {
        guard recording else { return }
        events.append(event)
        if hookCalls > 0 { callbacksAfterHook.append(event) }
        guard event == trigger, let action = hook else { return }
        originalDescriptor = ViewBuildContextScope.current?.viewIdentity.descriptorComponent
        originalLazy = ViewBuildContextScope.current?.viewIdentity.lazyList
        hook = nil
        hookCalls += 1
        action()
    }

    func erase(_ label: String) {
        guard recording else { return }
        erasureCounts[label, default: 0] += 1
        record("erase.\(label).\(erasureCounts[label, default: 0])")
    }

    func built(_ name: String) -> AnyView {
        record("build.\(name)")
        return AnyView(TableErasureContent(name: name, probe: self))
    }

    func body(_ name: String, value: Int) {
        installedValues.append(value)
        record("body.\(name)")
    }

    func selection(_ value: TableErasureKey?) -> Binding<TableErasureKey?> {
        Binding(
            get: {
                self.record("selection.get")
                return value
            }, set: { _ in self.record("selection.set") })
    }

    func selectionMode(required: Bool) -> ListSelectionMode {
        let selected = TableErasureKey(value: 1, label: "selected", probe: self)
        if required {
            return .requiredSingle(
                Binding<TableErasureKey>(
                    get: {
                        self.record("selection.get")
                        return selected
                    }, set: { _ in self.record("selection.set") }))
        }
        return .single(selection(selected))
    }
}

// The standard-library witness is nonisolated. These tests invoke it only
// through main-actor construction or selection, and never erase self again.
private struct TableErasureKey: Hashable, CustomStringConvertible, _HasCustomAnyHashableRepresentation {
    let value: Int
    let label: String
    var customRepresentation = false
    let probe: TableErasureProbe

    __consuming func _toCustomAnyHashable() -> AnyHashable? {
        MainActor.assumeIsolated { probe.erase(label) }
        return customRepresentation
            ? AnyHashable(TableErasureRepresentation(value: value, label: label, probe: probe)) : nil
    }

    var description: String {
        MainActor.assumeIsolated { probe.record("describe.\(label)") }
        return String(value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(customRepresentation)
        MainActor.assumeIsolated { probe.record("hash.\(label)") }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.probe.record("equal.\(lhs.label).\(rhs.label)") }
        return lhs.value == rhs.value && lhs.customRepresentation == rhs.customRepresentation
    }
}

private struct TableErasureRepresentation: Hashable, CustomStringConvertible {
    let value: Int
    let label: String
    let probe: TableErasureProbe

    var description: String {
        MainActor.assumeIsolated { probe.record("describe.\(label)") }
        return String(value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        MainActor.assumeIsolated { probe.record("hash.\(label)") }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.probe.record("equal.\(lhs.label).\(rhs.label)") }
        return lhs.value == rhs.value
    }
}

private struct TableErasureRow<ID: Hashable>: Identifiable {
    let identity: ID
    let name: String
    let probe: TableErasureProbe

    var id: ID {
        MainActor.assumeIsolated { probe.record("row.id.\(name)") }
        return identity
    }
}

private struct TableErasureCollection<ID: Hashable>: RandomAccessCollection {
    let rows: [TableErasureRow<ID>]
    let probe: TableErasureProbe

    var startIndex: Int {
        MainActor.assumeIsolated { probe.record("collection.start") }
        return rows.startIndex
    }

    var endIndex: Int {
        MainActor.assumeIsolated { probe.record("collection.end") }
        return rows.endIndex
    }

    subscript(index: Int) -> TableErasureRow<ID> {
        MainActor.assumeIsolated { probe.record("collection.read.\(index)") }
        return rows[index]
    }

    func index(after index: Int) -> Int {
        MainActor.assumeIsolated { probe.record("collection.advance.\(index)") }
        return index + 1
    }

    func index(before index: Int) -> Int { index - 1 }
}

@MainActor
private struct TableErasureContent: View {
    let name: String
    let probe: TableErasureProbe
    @State private var value = 23

    init(name: String, probe: TableErasureProbe) {
        self.name = name
        self.probe = probe
    }

    var body: some View {
        probe.body(name, value: value)
        return Text("\(name):\(value)")
    }
}

@MainActor
private struct TableErasureSibling {
    @State var value = 23
}

@MainActor
private struct TableErasureNestedState {
    let owner: StateMountOwner
    let value: Binding<Int>
}

private struct TableErasureRoot {}

// Real construction receipts are entered without a host window or renderer.
// The parent context stays installed so nested work has an independent owner.
@MainActor
private final class TableErasureFixture {
    let coordinator: StateMountCoordinator
    let build: any RetainedBuildEpoch
    let runtime: RetainedViewRuntime
    let context: ViewBuildContext
    private let parentContext: ViewBuildContext
    private let provider: RetainedLazyListDataSource<Int, [ViewNode]>?
    private let journal: RetainedLazyListAdoptionJournal?
    private let admission: RetainedLazyListAdoptionAdmission?
    private let nativeCoordinator: RetainedBuildCoordinator?
    private var closed = false
    private var authorityClosed = false

    init(lazy: Bool = false) throws {
        let coordinator = StateMountCoordinator(
            invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        let build = try XCTUnwrap(coordinator.beginBuild())
        let activity = try XCTUnwrap(build as? any RetainedLazyListBuildActivity)
        let root = ViewNode()
        let runtime = RetainedViewRuntime(root: root)
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: root.lazyListActivityStorage().descriptorOwnerLifetime)
        XCTAssertTrue(activity.bindLazyListDescriptorScope(scope))
        var parent = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { Size(width: 400, height: 240) },
            invalidateHandler: {}
        ).withViewIdentityType(TableErasureRoot.self)
        _ = try XCTUnwrap(coordinator.install(TableErasureRoot(), context: &parent))
        self.coordinator = coordinator
        self.build = build
        self.runtime = runtime
        self.parentContext = parent
        if lazy {
            let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
            let receipt = try XCTUnwrap(coordinator.descriptorResolutionReceipt(in: parent))
            let identity = parent.retainedViewIdentity.appending(.role(.content))
            XCTAssertTrue(
                provider.replaceData(
                    [0], id: \.self, identityRoot: identity, descriptorBuildScope: scope, rowContent: { _, _ in [] }))
            let metadata = try XCTUnwrap(provider.metadata)
            let proposal = try XCTUnwrap(
                coordinator.stageLazyMembership(at: identity, metadata: metadata, context: parent, receipt: receipt))
            let binding = proposal.nativeBinding
            let adapter = try XCTUnwrap(
                RetainedLazyListRuntimeAdapter(
                    provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                    maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
            XCTAssertTrue(adapter.installManagedLogicalDescriptor(binding))
            root.retainedSubtreeBuildLease = TableErasureLease(build: build)
            root.retainedLazyListAdapter = adapter
            XCTAssertTrue(adapter.claimAttachment(to: root))
            let nativeCoordinator = RetainedBuildCoordinator()
            let sequence = try XCTUnwrap(nativeCoordinator.beginBuild())
            nativeCoordinator.install(build, startedAt: sequence)
            let admission = RetainedLazyListAdoptionAdmission(
                adapter: adapter, container: root, runtime: runtime, coordinator: nativeCoordinator, sequence: sequence)
            XCTAssertTrue(admission.isBuildCurrent)
            let journal = RetainedLazyListAdoptionJournal(admission: admission, transaction: RetainedBuildTransaction())
            XCTAssertTrue(journal.bindDescriptorScope(scope))
            let request = try XCTUnwrap(provider.request(for: try XCTUnwrap(metadata.rows.first).token))
            let preparation = try XCTUnwrap(journal.prepareSelectedRow(request: request, descriptor: binding))
            let response = try XCTUnwrap(activity.resolveSelectedLazyListRow(preparation))
            let native = try XCTUnwrap(journal.consumeSelectedRowResolution(response, for: preparation))
            XCTAssertTrue(activity.enterLazyListMaterialization(native))
            var context = try XCTUnwrap(coordinator.contextForEnteredLazyRow(from: parent, descriptor: binding))
            context.viewIdentity.path = try XCTUnwrap(provider.identityPrefix(for: request))
            self.context = context
            self.provider = provider
            self.journal = journal
            self.admission = admission
            self.nativeCoordinator = nativeCoordinator
        } else {
            context = parent
            provider = nil
            journal = nil
            admission = nil
            nativeCoordinator = nil
        }
    }

    func installSibling() throws -> TableErasureNestedState {
        var context = parentContext.withViewIdentityRole(.content).withViewIdentityType(TableErasureSibling.self)
        let installed = try XCTUnwrap(coordinator.install(TableErasureSibling(), context: &context))
        return TableErasureNestedState(
            owner: try XCTUnwrap(context.viewIdentity.installedOwner), value: installed.$value)
    }

    func closeAuthority() {
        guard !authorityClosed else { return }
        authorityClosed = true
        coordinator.close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        journal?.revokeBeforeAbandon()
        admission?.revoke()
        closeAuthority()
        build.abandon()
        build.finishAfterCallbacks()
        provider?.close()
        nativeCoordinator?.finishBuild()
    }
}

@MainActor
private final class TableErasureLease: RetainedSubtreeBuildLease {
    private weak var originalBuild: (any RetainedBuildEpoch)?

    init(build: any RetainedBuildEpoch) {
        originalBuild = build
    }

    var canBuild: Bool { originalBuild?.canAdopt == true }

    // The fixture installs its original epoch directly and cannot supply another build.
    func beginBuild() -> (any RetainedBuildEpoch)? { nil }
}
