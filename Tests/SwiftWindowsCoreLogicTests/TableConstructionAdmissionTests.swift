import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class TableConstructionAdmissionTests: XCTestCase {
    func testHashCloseStopsBeforeLaterKeysOrAnyHeaderBuilder() async throws {
        try assertRejection(at: .hash, by: .close)
    }

    func testHashNestedInstallationCannotRenewTheOriginalLookup() async throws {
        try assertRejection(at: .hash, by: .nestedInstallation)
    }

    func testCollisionEqualityCloseStopsBeforeAnyHeaderBuilder() async throws {
        try assertRejection(at: .collisionEquality, by: .close)
    }

    func testCollisionEqualityNestedInstallationCannotRenewTheOriginalLookup() async throws {
        try assertRejection(at: .collisionEquality, by: .nestedInstallation)
    }

    func testCurrentSortEqualityCannotContinueIntoHeaderViewConstruction() async throws {
        for stop in TableConstructionTestStop.allCases {
            try assertRejection(at: .sortEquality, by: stop)
        }
    }

    func testHeaderBuilderCannotContinueIntoItsReturnedViewOrAnotherColumn() async throws {
        for stop in TableConstructionTestStop.allCases {
            try assertRejection(at: .headerBuilder, by: stop)
        }
    }

    func testCellBuilderCannotContinueIntoItsReturnedViewOrAnotherCell() async throws {
        for stop in TableConstructionTestStop.allCases {
            try assertRejection(at: .cellBuilder, by: stop)
        }
    }

    func testLazyRowKeyCannotContinueAfterCloseOrNestedInstallation() async throws {
        for stop in TableConstructionTestStop.allCases {
            try assertRejection(at: .hash, by: stop, lazy: true)
        }
    }

    func testManagedTablesAllowTheirChildrenToInstallStateInDescriptorAndLazyScopes() async throws {
        for usesLazyRow in [false, true] {
            let fixture = try TableConstructionTestFixture()
            let row = usesLazyRow ? try TableConstructionTestLazyRow(fixture: fixture) : nil
            let probe = TableConstructionTestProbe()
            defer {
                probe.disarm()
                row?.close()
                fixture.close()
            }
            let context = try row?.enter() ?? fixture.context
            probe.arm()
            let output = makeViewComponent(probe.table(), context: context).makeNode(runtime: fixture.runtime)
            probe.disarm()

            XCTAssertFalse(output.containsRejectedRetainedSource)
            XCTAssertEqual(
                probe.builders, ["header.0", "header.1", "cell.0.10", "cell.1.10", "cell.0.20", "cell.1.20"])
            XCTAssertEqual(probe.bodies, probe.builders)
            XCTAssertEqual(probe.installedValues, Array(repeating: 23, count: 6))
            XCTAssertEqual(output.children.count, 3)
            XCTAssertEqual(output.children.first?.children.count, 2)
            XCTAssertEqual(output.children.first?.children.map(\.isFocusable), [true, true])
            XCTAssertEqual(probe.sortCalls, 0)
            XCTAssertTrue(fixture.build.canAdopt)
        }
    }

    func testUnmanagedTablesKeepTheirNormalHeaderAndCellConstruction() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let probe = TableConstructionTestProbe()
        probe.arm()
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 240) }, invalidateHandler: {})
        let output = makeViewComponent(probe.table(), context: context).makeNode(runtime: runtime)
        probe.disarm()

        XCTAssertFalse(output.containsRejectedRetainedSource)
        XCTAssertEqual(probe.builders.count, 6)
        XCTAssertEqual(probe.bodies, probe.builders)
        XCTAssertEqual(output.children.count, 3)
        XCTAssertEqual(output.children.first?.children.map(\.accessibilityLabel), ["header.0:23", "header.1:23"])
        XCTAssertEqual(probe.sortCalls, 0)
    }

    func testCollectionCallbacksStopBeforeTheNextIndexOrElementOperation() async throws {
        for trigger in ["collection.start", "collection.end", "collection.read.0", "collection.advance.0"] {
            for stop in TableConstructionTestStop.allCases {
                let fixture = try TableConstructionTestFixture()
                let probe = TableConstructionTestProbe()
                defer {
                    probe.disarm()
                    fixture.close()
                }
                var nested: TableConstructionTestNestedState?
                probe.arm(on: trigger) {
                    switch stop {
                    case .close: fixture.closeAuthority()
                    case .nestedInstallation: nested = try? fixture.installOrdinarySibling()
                    }
                }
                let table = probe.table(rows: TableConstructionTestCollection(probe: probe))
                let output = makeViewComponent(table, context: fixture.context).makeNode(runtime: fixture.runtime)
                probe.disarm()

                XCTAssertEqual(probe.hookCalls, 1, trigger)
                XCTAssertTrue(output.containsRejectedRetainedSource, trigger)
                XCTAssertTrue(probe.callbacksAfterHook.isEmpty, "\(trigger): \(probe.callbacksAfterHook)")
                let expected =
                    trigger == "collection.advance.0"
                    ? ["header.0", "header.1", "cell.0.10", "cell.1.10"] : ["header.0", "header.1"]
                XCTAssertEqual(probe.builders, expected, trigger)
                XCTAssertEqual(probe.bodies, expected, trigger)
                if stop == .nestedInstallation {
                    XCTAssertEqual(try XCTUnwrap(nested).value.wrappedValue, 23)
                    XCTAssertTrue(fixture.build.canAdopt)
                }
            }
        }
    }

    func testSelectionGetterRejectionSkipsAuthoredKeyEquality() async throws {
        try assertSelectionRejection(on: "selection.get")
    }

    func testRowDescriptionCannotRenewTheLookupAfterNestedWork() async throws {
        try assertSelectionRejection(on: "describe:row")
    }

    func testOptionalNilRowIdentityIsAValueRatherThanRejectedAdmission() async throws {
        let fixture = try TableConstructionTestFixture()
        defer { fixture.close() }
        let rows = [
            TableConstructionTestOptionalRow(id: nil, name: "Nil identity"),
            TableConstructionTestOptionalRow(id: 7, name: "Number identity"),
        ]
        let table = Table(rows, selection: Optional<Binding<Int??>>.none) {
            TableColumn("Name", value: \TableConstructionTestOptionalRow.name)
        }
        let output = makeViewComponent(table, context: fixture.context).makeNode(runtime: fixture.runtime)

        XCTAssertFalse(output.containsRejectedRetainedSource)
        XCTAssertEqual(output.children.count, 3)
        let nilRow = try XCTUnwrap(output.children.dropFirst().first)
        let identity = try XCTUnwrap(nilRow.retainedViewIdentity)
        XCTAssertTrue(identity.segments.contains(.keyed(.init(Optional<Int>.none))))
        XCTAssertTrue(fixture.build.canAdopt)
    }

    private func assertSelectionRejection(
        on trigger: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for stop in TableConstructionTestStop.allCases {
            let fixture = try TableConstructionTestFixture()
            let probe = TableConstructionTestProbe()
            defer {
                probe.disarm()
                fixture.close()
            }
            let key = TableConstructionTestKey(label: "row", value: 1, probe: probe)
            let selection = Binding<TableConstructionTestKey?>(
                get: {
                    probe.record("selection.get")
                    return TableConstructionTestKey(label: "selected", value: 1, probe: probe)
                }, set: { _ in XCTFail("Construction must not write selection", file: file, line: line) })
            let table = Table([TableConstructionTestKeyedRow(id: key)], selection: selection) {
                AnyTableColumn<TableConstructionTestKeyedRow>(
                    title: "Header", cellBuilder: { _ in [probe.builtValue("cell")] },
                    headerBuilder: { [probe.builtValue("header")] })
            }
            var nested: TableConstructionTestNestedState?
            probe.arm(on: trigger) {
                switch stop {
                case .close: fixture.closeAuthority()
                case .nestedInstallation: nested = try? fixture.installOrdinarySibling()
                }
            }
            let output = makeViewComponent(table, context: fixture.context).makeNode(runtime: fixture.runtime)
            probe.disarm()

            XCTAssertEqual(probe.hookCalls, 1, file: file, line: line)
            XCTAssertTrue(output.containsRejectedRetainedSource, file: file, line: line)
            XCTAssertTrue(probe.callbacksAfterHook.isEmpty, "\(probe.callbacksAfterHook)", file: file, line: line)
            let expected = trigger == "selection.get" ? ["header"] : ["header", "cell"]
            XCTAssertEqual(probe.builders, expected, file: file, line: line)
            XCTAssertEqual(probe.bodies, expected, file: file, line: line)
            if stop == .nestedInstallation {
                XCTAssertEqual(
                    try XCTUnwrap(nested, file: file, line: line).value.wrappedValue, 23, file: file, line: line)
                XCTAssertTrue(fixture.build.canAdopt, file: file, line: line)
            }
        }
    }

    private func assertRejection(
        at site: TableConstructionTestSite, by stop: TableConstructionTestStop, lazy: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try TableConstructionTestFixture()
        let row = lazy ? try TableConstructionTestLazyRow(fixture: fixture) : nil
        let probe = TableConstructionTestProbe()
        defer {
            probe.disarm()
            row?.close()
            fixture.close()
        }
        let context = try row?.enter() ?? fixture.context
        var nested: TableConstructionTestNestedState?
        probe.arm(on: site.trigger) {
            switch stop {
            case .close: fixture.closeAuthority()
            case .nestedInstallation: nested = try? fixture.installOrdinarySibling()
            }
        }
        let output = makeViewComponent(probe.table(sorted: site == .sortEquality), context: context)
            .makeNode(runtime: fixture.runtime)
        probe.disarm()

        XCTAssertEqual(probe.hookCalls, 1, "The requested callback must actually run", file: file, line: line)
        XCTAssertTrue(output.containsRejectedRetainedSource, file: file, line: line)
        XCTAssertTrue(
            probe.callbacksAfterHook.isEmpty, "No later authored work: \(probe.callbacksAfterHook)", file: file,
            line: line)
        XCTAssertEqual(probe.builders, site.expectedBuilders, file: file, line: line)
        XCTAssertEqual(probe.bodies, site.expectedBodies, file: file, line: line)
        XCTAssertEqual(probe.sortCalls, 0, file: file, line: line)
        if lazy {
            XCTAssertFalse(try XCTUnwrap(probe.originalLazy, file: file, line: line).isCurrent, file: file, line: line)
        } else {
            XCTAssertFalse(
                try XCTUnwrap(probe.originalDescriptor, file: file, line: line).canConstruct, file: file, line: line)
        }
        if stop == .nestedInstallation {
            let state = try XCTUnwrap(nested, file: file, line: line)
            XCTAssertTrue(fixture.build.canAdopt, "Reject only the obsolete Table contribution", file: file, line: line)
            XCTAssertTrue(state.owner.isInstallationActive, file: file, line: line)
            XCTAssertEqual(state.value.wrappedValue, 23, file: file, line: line)
            state.value.wrappedValue = 71
            XCTAssertEqual(state.value.wrappedValue, 71, file: file, line: line)
        }
    }
}

private enum TableConstructionTestStop: CaseIterable, Equatable {
    case close
    case nestedInstallation
}

private enum TableConstructionTestSite: Equatable {
    case hash
    case collisionEquality
    case sortEquality
    case headerBuilder
    case cellBuilder

    var trigger: String {
        switch self {
        case .hash: "hash:first"
        case .collisionEquality: "equal:first:second"
        case .sortEquality: "equal:sort:first"
        case .headerBuilder: "builder:header.0"
        case .cellBuilder: "builder:cell.0.10"
        }
    }

    var expectedBuilders: [String] {
        switch self {
        case .hash, .collisionEquality: []
        case .sortEquality, .headerBuilder: ["header.0"]
        case .cellBuilder: ["header.0", "header.1", "cell.0.10"]
        }
    }

    var expectedBodies: [String] {
        self == .cellBuilder ? ["header.0", "header.1"] : []
    }
}

@MainActor
private final class TableConstructionTestProbe {
    private var isRecording = false
    private var trigger: String?
    private var hook: (@MainActor () -> Void)?
    private(set) var hookCalls = 0
    private(set) var callbacksAfterHook: [String] = []
    private(set) var builders: [String] = []
    private(set) var bodies: [String] = []
    private(set) var installedValues: [Int] = []
    private(set) var originalDescriptor: RetainedDescriptorComponentAttribution?
    private(set) var originalLazy: LazyListViewAttribution?
    private(set) var sortCalls = 0

    func arm(on trigger: String? = nil, hook: (@MainActor () -> Void)? = nil) {
        isRecording = true
        self.trigger = trigger
        self.hook = hook
    }

    func disarm() {
        isRecording = false
        hook = nil
    }

    func record(_ event: String) {
        guard isRecording else { return }
        if hookCalls > 0 { callbacksAfterHook.append(event) }
        guard event == trigger, let action = hook else { return }
        originalDescriptor = ViewBuildContextScope.current?.viewIdentity.descriptorComponent
        originalLazy = ViewBuildContextScope.current?.viewIdentity.lazyList
        hook = nil
        hookCalls += 1
        action()
    }

    func builtValue(_ name: String) -> AnyView {
        builders.append(name)
        record("builder:\(name)")
        return AnyView(TableConstructionTestContent(name: name, probe: self))
    }

    func body(_ name: String, value: Int) {
        bodies.append(name)
        installedValues.append(value)
        record("body:\(name)")
    }

    func table(sorted: Bool = false) -> Table<[TableConstructionTestRow]> {
        table(rows: [TableConstructionTestRow(id: 10), TableConstructionTestRow(id: 20)], sorted: sorted)
    }

    func table<Rows: RandomAccessCollection>(rows: Rows, sorted: Bool = false) -> Table<Rows>
    where Rows.Element == TableConstructionTestRow {
        let keys = [
            TableConstructionTestKey(label: "first", value: 1, probe: self),
            TableConstructionTestKey(label: "second", value: 2, probe: self),
        ]
        let sort: (key: AnyHashable, order: WinSwiftUI.SortOrder)? =
            sorted ? (AnyHashable(TableConstructionTestKey(label: "sort", value: 1, probe: self)), .forward) : nil
        let onSort: (AnyHashable?, WinSwiftUI.SortOrder) -> Void = { [weak self] _, _ in self?.sortCalls += 1 }
        return Table(
            rows,
            selection: Optional<Binding<Int?>>.none, sort: sort, onSort: onSort
        ) {
            for (index, key) in keys.enumerated() {
                AnyTableColumn<TableConstructionTestRow>(
                    title: "Column \(index)", width: .fixed(100), sortKey: AnyHashable(key), isSortable: true,
                    cellBuilder: { [self] row in [builtValue("cell.\(index).\(row.id)")] },
                    headerBuilder: { [self] in [builtValue("header.\(index)")] })
            }
        }
    }
}

private struct TableConstructionTestKey: Hashable, CustomStringConvertible {
    let label: String
    let value: Int
    let probe: TableConstructionTestProbe

    var description: String {
        MainActor.assumeIsolated { probe.record("describe:\(label)") }
        return String(value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
        MainActor.assumeIsolated { probe.record("hash:\(label)") }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.probe.record("equal:\(lhs.label):\(rhs.label)") }
        return lhs.value == rhs.value
    }
}

private struct TableConstructionTestRow: Identifiable {
    let id: Int
}

private struct TableConstructionTestKeyedRow: Identifiable {
    let id: TableConstructionTestKey
}

private struct TableConstructionTestOptionalRow: Identifiable {
    let id: Int?
    let name: String
}

private struct TableConstructionTestCollection: RandomAccessCollection {
    let probe: TableConstructionTestProbe
    private let values = [TableConstructionTestRow(id: 10), TableConstructionTestRow(id: 20)]

    init(probe: TableConstructionTestProbe) { self.probe = probe }

    var startIndex: Int {
        MainActor.assumeIsolated { probe.record("collection.start") }
        return values.startIndex
    }

    var endIndex: Int {
        MainActor.assumeIsolated { probe.record("collection.end") }
        return values.endIndex
    }

    subscript(index: Int) -> TableConstructionTestRow {
        MainActor.assumeIsolated { probe.record("collection.read.\(index)") }
        return values[index]
    }

    func index(after index: Int) -> Int {
        MainActor.assumeIsolated { probe.record("collection.advance.\(index)") }
        return index + 1
    }

    func index(before index: Int) -> Int { index - 1 }
}

@MainActor
private struct TableConstructionTestContent: View {
    let name: String
    let probe: TableConstructionTestProbe
    @State private var value = 23

    init(name: String, probe: TableConstructionTestProbe) {
        self.name = name
        self.probe = probe
    }

    var body: some View {
        probe.body(name, value: value)
        return Text("\(name):\(value)")
    }
}

@MainActor
private struct TableConstructionTestSibling {
    @State var value = 23
}

@MainActor
private struct TableConstructionTestNestedState {
    let owner: StateMountOwner
    let value: Binding<Int>
}

private struct TableConstructionTestRoot {}

@MainActor
private final class TableConstructionTestFixture {
    let coordinator: StateMountCoordinator
    let build: any RetainedBuildEpoch
    let activity: any RetainedLazyListBuildActivity
    let scope: RetainedLazyListDescriptorBuildScope
    let runtime: RetainedViewRuntime
    let context: ViewBuildContext
    private var authorityClosed = false
    private var finished = false

    init() throws {
        let coordinator = StateMountCoordinator(
            invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        let build = try XCTUnwrap(coordinator.beginBuild())
        let activity = try XCTUnwrap(build as? any RetainedLazyListBuildActivity)
        let target = ViewNode()
        let runtime = RetainedViewRuntime(root: target)
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: target.lazyListActivityStorage().descriptorOwnerLifetime)
        XCTAssertTrue(activity.bindLazyListDescriptorScope(scope))
        var context = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { Size(width: 400, height: 240) },
            invalidateHandler: {}
        ).withViewIdentityType(TableConstructionTestRoot.self)
        _ = try XCTUnwrap(coordinator.install(TableConstructionTestRoot(), context: &context))
        self.coordinator = coordinator
        self.build = build
        self.activity = activity
        self.scope = scope
        self.runtime = runtime
        self.context = context
    }

    func installOrdinarySibling() throws -> TableConstructionTestNestedState {
        var sibling = context.withViewIdentityRole(.content).withViewIdentityType(TableConstructionTestSibling.self)
        let installed = try XCTUnwrap(coordinator.install(TableConstructionTestSibling(), context: &sibling))
        return TableConstructionTestNestedState(
            owner: try XCTUnwrap(sibling.viewIdentity.installedOwner), value: installed.$value)
    }

    func closeAuthority() {
        guard !authorityClosed else { return }
        authorityClosed = true
        coordinator.close()
    }

    func close() {
        guard !finished else { return }
        finished = true
        closeAuthority()
        build.abandon()
        build.finishAfterCallbacks()
    }
}

@MainActor
private final class TableConstructionTestLazyRow {
    let fixture: TableConstructionTestFixture
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let binding: RetainedLazyListManagedLogicalDescriptorBinding
    let admission: RetainedLazyListAdoptionAdmission
    let journal: RetainedLazyListAdoptionJournal
    let nativeCoordinator: RetainedBuildCoordinator
    private let lease: TableConstructionTestLease
    private var finished = false

    init(fixture: TableConstructionTestFixture) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        let identity = fixture.context.retainedViewIdentity.appending(.role(.content))
        XCTAssertTrue(
            provider.replaceData(
                [0], id: \.self, identityRoot: identity, descriptorBuildScope: fixture.scope,
                rowContent: { _, _ in [] }))
        let metadata = try XCTUnwrap(provider.metadata)
        let proposal = try XCTUnwrap(
            fixture.coordinator.stageLazyMembership(
                at: identity, metadata: metadata, context: fixture.context, receipt: receipt))
        let binding = proposal.nativeBinding
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        XCTAssertTrue(adapter.installManagedLogicalDescriptor(binding))
        let lease = TableConstructionTestLease(build: fixture.build)
        fixture.runtime.root.retainedSubtreeBuildLease = lease
        fixture.runtime.root.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.claimAttachment(to: fixture.runtime.root))
        let nativeCoordinator = RetainedBuildCoordinator()
        let sequence = try XCTUnwrap(nativeCoordinator.beginBuild())
        nativeCoordinator.install(fixture.build, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: fixture.runtime.root, runtime: fixture.runtime,
            coordinator: nativeCoordinator, sequence: sequence)
        XCTAssertTrue(admission.isBuildCurrent)
        let journal = RetainedLazyListAdoptionJournal(admission: admission, transaction: RetainedBuildTransaction())
        XCTAssertTrue(journal.bindDescriptorScope(fixture.scope))
        self.fixture = fixture
        self.provider = provider
        self.binding = binding
        self.admission = admission
        self.journal = journal
        self.nativeCoordinator = nativeCoordinator
        self.lease = lease
    }

    func enter() throws -> ViewBuildContext {
        let metadata = try XCTUnwrap(provider.metadata)
        let request = try XCTUnwrap(provider.request(for: try XCTUnwrap(metadata.rows.first).token))
        let preparation = try XCTUnwrap(journal.prepareSelectedRow(request: request, descriptor: binding))
        let response = try XCTUnwrap(fixture.activity.resolveSelectedLazyListRow(preparation))
        let native = try XCTUnwrap(journal.consumeSelectedRowResolution(response, for: preparation))
        XCTAssertTrue(fixture.activity.enterLazyListMaterialization(native))
        var context = try XCTUnwrap(
            fixture.coordinator.contextForEnteredLazyRow(from: fixture.context, descriptor: binding))
        context.viewIdentity.path = try XCTUnwrap(provider.identityPrefix(for: request))
        return context
    }

    func close() {
        guard !finished else { return }
        finished = true
        journal.revokeBeforeAbandon()
        admission.revoke()
        fixture.close()
        provider.close()
        nativeCoordinator.finishBuild()
    }
}

@MainActor
private final class TableConstructionTestLease: RetainedSubtreeBuildLease {
    private weak var originalBuild: (any RetainedBuildEpoch)?

    init(build: any RetainedBuildEpoch) {
        originalBuild = build
    }

    var canBuild: Bool { originalBuild?.canAdopt == true }

    // The fixture installs its original epoch directly and cannot supply another build.
    func beginBuild() -> (any RetainedBuildEpoch)? { nil }
}
