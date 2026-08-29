import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ManagedListLogicalCountTests: XCTestCase {
    func testAcceptedMetadataCountDoesNotPrepareViewportOrGrantAccessibility() async throws {
        let probe = ManagedListLogicalCountProbe()
        let host = makeHost(probe)
        defer { host.close() }
        try host.assertCommittedDescriptor()
        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)

        for _ in 0..<4 { XCTAssertEqual(adapter.logicalRecordCount, 32) }

        XCTAssertEqual(adapter.mountedRecordCount, 0)
        XCTAssertEqual(adapter.mountedLeafCount, 0)
        XCTAssertEqual(adapter.contentExtent, 0)
        XCTAssertTrue(list.children.isEmpty)
        XCTAssertTrue(probe.factories.isEmpty)
        XCTAssertTrue(probe.appearances.isEmpty)
        XCTAssertFalse(adapter.hasCurrentLogicalSnapshot)
        XCTAssertNil(adapter.currentLogicalGeneration)
        XCTAssertNil(adapter.captureLayoutProof())
        XCTAssertFalse(host.runtime.supportsLazyListAccessibilityItems(in: list))
        XCTAssertNil(host.runtime.captureLazyListScrollSource(in: list))
    }

    func testReloadAndCloseInvalidatePriorCountsWithoutPreparingRows() async throws {
        let probe = ManagedListLogicalCountProbe()
        let host = makeHost(probe)
        defer { host.close() }
        let previous = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        XCTAssertEqual(previous.logicalRecordCount, 32)

        probe.rows = Array(0..<7)
        host.reload()

        try host.assertCommittedDescriptor()
        let replacement = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        XCTAssertFalse(replacement === previous)
        XCTAssertEqual(replacement.logicalRecordCount, 7)
        XCTAssertEqual(previous.logicalRecordCount, 0)
        XCTAssertFalse(replacement.hasCurrentLogicalSnapshot)
        XCTAssertEqual(replacement.contentExtent, 0)
        XCTAssertEqual(replacement.mountedRecordCount, 0)
        XCTAssertTrue(probe.factories.isEmpty)

        host.close()

        XCTAssertEqual(replacement.logicalRecordCount, 0)
        XCTAssertEqual(previous.logicalRecordCount, 0)
        XCTAssertTrue(probe.factories.isEmpty)
        XCTAssertTrue(probe.appearances.isEmpty)
    }

    func testProvisionalAndRevokedBindingsDoNotExposeDeclaredCountsOrReadProviders() async throws {
        let probe = ManagedListLogicalCountProbe()
        // This managed primitive preserves its Int element type, allowing the
        // monitor to wrap the actual accepted source without inventing metadata.
        let host = MountedLazyListTestHost {
            ManagedLazyListContent(
                probe.rows, id: \.self, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1
            ) { probe.makeRow($0) }
        }
        defer { host.close() }
        try host.assertCommittedDescriptor()
        let accepted = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        let binding = try XCTUnwrap(accepted.managedLogicalDescriptorBinding)
        let source = try XCTUnwrap(accepted.dataSource(for: Int.self))
        let metadata = try XCTUnwrap(source.metadata)
        let provider = ManagedListLogicalCountProvider(source: source)
        let monitored = try makeAdapter(provider)
        XCTAssertTrue(monitored.installManagedLogicalDescriptor(binding))
        let provisional = RetainedLazyListManagedLogicalDescriptorBinding(
            descriptor: RetainedLazyListLogicalDeclarationID(), facadeProposal: RetainedLazyListLogicalProposalID(),
            scope: binding.scope, metadata: metadata)
        let pending = try makeAdapter(provider)
        XCTAssertTrue(pending.installManagedLogicalDescriptor(provisional))
        let unmanaged = try makeAdapter(provider)

        XCTAssertTrue(provisional.isCurrent)
        XCTAssertFalse(provisional.scope.containsDeclaredDescriptor(provisional.descriptor))
        XCTAssertEqual(monitored.logicalRecordCount, 32)
        XCTAssertEqual(pending.logicalRecordCount, 0)
        XCTAssertEqual(unmanaged.logicalRecordCount, 0)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertFalse(monitored.hasCurrentLogicalSnapshot)

        binding.revoke()

        XCTAssertTrue(binding.sourceGeneration.isCurrent, "Explicit revocation is independent of provider freshness")
        XCTAssertFalse(binding.isCurrent)
        XCTAssertEqual(monitored.logicalRecordCount, 0)
        XCTAssertEqual(accepted.logicalRecordCount, 0)
        XCTAssertEqual(pending.logicalRecordCount, 0)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(probe.factories.isEmpty)
        XCTAssertTrue(probe.appearances.isEmpty)
    }

    func testNativeBindingDoesNotRetainMetadataKeyPayload() async throws {
        let (binding, observedKey) = try bindingAfterSourceClose()

        XCTAssertEqual(binding.declaredRecordCount, 1)
        XCTAssertFalse(binding.sourceGeneration.isCurrent)
        XCTAssertNil(observedKey.value, "The native binding may retain the count, but not metadata or typed keys")
    }

    private func makeHost(_ probe: ManagedListLogicalCountProbe) -> MountedLazyListTestHost {
        MountedLazyListTestHost { List(probe.rows, id: \.self) { probe.makeRow($0) }.listStyle(.plain) }
    }

    private func makeAdapter(
        _ provider: ManagedListLogicalCountProvider
    ) throws -> RetainedLazyListRuntimeAdapter {
        try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
    }

    private func bindingAfterSourceClose() throws -> (
        RetainedLazyListManagedLogicalDescriptorBinding, ManagedListLogicalCountWeakKey
    ) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let scope = RetainedLazyListLogicalMembershipScope(in: runtime, parentRow: nil)
        let source = RetainedLazyListDataSource<ManagedListLogicalCountKey, [ViewNode]>()
        let key = ManagedListLogicalCountKey(1)
        let observed = ManagedListLogicalCountWeakKey(key)
        XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { _ in [] }))
        let binding = RetainedLazyListManagedLogicalDescriptorBinding(
            descriptor: RetainedLazyListLogicalDeclarationID(), facadeProposal: RetainedLazyListLogicalProposalID(),
            scope: scope, metadata: try XCTUnwrap(source.metadata))
        XCTAssertTrue(binding.isCurrent)
        XCTAssertNotNil(observed.value)
        source.close()
        withExtendedLifetime(runtime) {}
        return (binding, observed)
    }
}

@MainActor
private final class ManagedListLogicalCountProbe {
    var rows = Array(0..<32)
    var factories: [Int] = []
    var appearances: [Int] = []

    func makeRow(_ id: Int) -> [AnyView] {
        factories.append(id)
        return [AnyView(Text("Row \(id)").onAppear { [weak self] in self?.appearances.append(id) })]
    }
}

@MainActor
private final class ManagedListLogicalCountProvider: RetainedLazyListProvider {
    typealias RowContent = [ViewNode]
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    private(set) var calls = 0

    init(source: RetainedLazyListDataSource<Int, [ViewNode]>) { self.source = source }

    var metadata: RetainedLazyListMetadata? {
        calls += 1
        return source.metadata
    }

    func token(for key: RetainedViewIdentity.Key, occurrence: Int) -> RetainedLazyListRowToken? {
        calls += 1
        return source.token(for: key, occurrence: occurrence)
    }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        calls += 1
        return source.request(for: token)
    }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        calls += 1
        return source.isCurrent(request)
    }

    func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity? {
        calls += 1
        return source.identityPrefix(for: request)
    }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        calls += 1
        return source.materialize(request, budget: budget)
    }
}

private final class ManagedListLogicalCountKey: Hashable {
    let value: Int
    init(_ value: Int) { self.value = value }
    static func == (lhs: ManagedListLogicalCountKey, rhs: ManagedListLogicalCountKey) -> Bool { lhs.value == rhs.value }
    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

private final class ManagedListLogicalCountWeakKey {
    weak var value: ManagedListLogicalCountKey?
    init(_ value: ManagedListLogicalCountKey) { self.value = value }
}
