import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Geometry-cache changes must not become managed row declaration changes.
/// These fixtures use the production headless driver and its default budgets.
@MainActor
final class MountedLazyListWidthContextTests: XCTestCase {
    func testWidthOnlyRefreshPreservesAcceptedRowsAndStateOwners() async throws {
        let probe = LazyWidthContextProbe()
        let host = MountedLazyListTestHost { lazyWidthContextContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        let roots = list.children
        XCTAssertEqual(roots.count, 2)
        let attachments = roots.map { $0.captureLazyListAttachmentProof() }
        let owner = try XCTUnwrap(probe.owners[0])
        let binding = try XCTUnwrap(probe.bindings[0])
        let factories = probe.factoryCalls
        let bodies = probe.bodyCalls

        host.runtime.setRootSize(IntSize(width: 240, height: 40))
        XCTAssertNotNil(host.layout())

        XCTAssertTrue(try host.list() === list)
        XCTAssertTrue(list.retainedLazyListAdapter === adapter)
        XCTAssertEqual(list.children.count, roots.count)
        XCTAssertTrue(zip(roots, list.children).allSatisfy { $0 === $1 })
        XCTAssertTrue(attachments.allSatisfy(\.isCurrent))
        XCTAssertEqual(probe.factoryCalls, factories)
        XCTAssertEqual(probe.bodyCalls, bodies)
        XCTAssertTrue(owner.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: owner.identity) === owner)
        XCTAssertEqual(binding.wrappedValue, 41)
        XCTAssertTrue(list.children.allSatisfy { $0.resolvedFrame.width == 240 })
        let plan = try lazyWidthContextPlan(adapter, width: 240)
        XCTAssertFalse(plan.requiresResolution)
        XCTAssertEqual(plan.placements.count, 2)
        XCTAssertTrue(plan.placements.allSatisfy { $0.extent == 20 })

        let invalidations = host.events.stateInvalidations
        binding.wrappedValue = 87
        XCTAssertEqual(binding.wrappedValue, 87)
        XCTAssertEqual(host.events.stateInvalidations, invalidations + 1)
        XCTAssertTrue(owner.isLive)
    }

    func testWidthReturningToItsOldValueDoesNotReviveLayoutProofs() async throws {
        let probe = LazyWidthContextProbe()
        let host = MountedLazyListTestHost { lazyWidthContextContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        let first = try XCTUnwrap(adapter.captureLayoutProof())
        let factories = probe.factoryCalls
        XCTAssertTrue(first.isCurrent)

        host.runtime.setRootSize(IntSize(width: 180, height: 40))
        XCTAssertNotNil(host.layout())
        let second = try XCTUnwrap(adapter.captureLayoutProof())
        XCTAssertFalse(first.isCurrent)
        XCTAssertTrue(second.isCurrent)
        let oldContext = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let oldViewport = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter.Viewport(context: oldContext, offset: 0, extent: 40))
        XCTAssertNil(adapter.recordMeasurements([], viewport: oldViewport))

        host.runtime.setRootSize(IntSize(width: 120, height: 40))
        XCTAssertNotNil(host.layout())
        XCTAssertFalse(first.isCurrent)
        XCTAssertFalse(second.isCurrent)
        XCTAssertTrue(try XCTUnwrap(adapter.captureLayoutProof()).isCurrent)
        XCTAssertFalse(try lazyWidthContextPlan(adapter, width: 120).requiresResolution)
        XCTAssertEqual(probe.factoryCalls, factories)
    }

    func testContentRevisionStillRebuildsRowsAlongsideAWidthChange() async throws {
        try assertLazyWidthContextRebuild(content: 1, environment: 0, scale: 1)
    }

    func testEnvironmentRevisionStillRebuildsRowsAlongsideAWidthChange() async throws {
        try assertLazyWidthContextRebuild(content: 0, environment: 1, scale: 1)
    }

    func testDisplayScaleStillRebuildsRowsAlongsideAWidthChange() async throws {
        try assertLazyWidthContextRebuild(content: 0, environment: 0, scale: 1.5)
    }
}

@MainActor
private func assertLazyWidthContextRebuild(
    content: UInt64, environment: UInt64, scale: Double,
    file: StaticString = #filePath, line: UInt = #line
) throws {
    let probe = LazyWidthContextProbe()
    let host = MountedLazyListTestHost { lazyWidthContextContent(probe) }
    defer {
        host.close()
        probe.clear()
    }
    XCTAssertNotNil(host.layout(), file: file, line: line)
    let list = try host.list(file: file, line: line)
    let adapter = try XCTUnwrap(list.retainedLazyListAdapter, file: file, line: line)
    let factories = probe.factoryCalls
    XCTAssertNotNil(host.find("lazy.width.0.0"), file: file, line: line)

    probe.labelRevision = 1
    list.setRetainedLazyListMeasurementRevisions(content: content, environment: environment)
    host.runtime.displayScale = scale
    host.runtime.setRootSize(IntSize(width: 240, height: 40))
    XCTAssertNotNil(host.layout(), file: file, line: line)

    XCTAssertGreaterThan(probe.factoryCalls[0, default: 0], factories[0, default: 0], file: file, line: line)
    XCTAssertNotNil(host.find("lazy.width.0.1"), file: file, line: line)
    XCTAssertNil(host.find("lazy.width.0.0"), file: file, line: line)
    let plan = try lazyWidthContextPlan(
        adapter, width: 240, scale: scale, content: content, environment: environment)
    XCTAssertFalse(plan.requiresResolution, file: file, line: line)
}

@MainActor
private func lazyWidthContextPlan(
    _ adapter: RetainedLazyListRuntimeAdapter, width: Double, scale: Double = 1,
    content: UInt64 = 0, environment: UInt64 = 0
) throws -> RetainedLazyListRuntimeAdapter.LayoutPlan {
    let context = try XCTUnwrap(
        RetainedLazyListMeasurementContext(
            width: width, displayScale: scale, contentRevision: content, environmentRevision: environment))
    let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 40))
    return adapter.layoutPlan(viewport: viewport)
}

@MainActor
private final class LazyWidthContextProbe {
    var labelRevision = 0
    var factoryCalls: [Int: Int] = [:]
    var bodyCalls: [Int: Int] = [:]
    var owners: [Int: StateMountOwner] = [:]
    var bindings: [Int: Binding<Int>] = [:]

    func makeRow(_ row: Int) -> LazyWidthContextRow {
        factoryCalls[row, default: 0] += 1
        return LazyWidthContextRow(row: row, revision: labelRevision, probe: self)
    }

    func record(_ row: Int, binding: Binding<Int>) {
        bodyCalls[row, default: 0] += 1
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            XCTFail("The production managed row must install its owner before evaluating its body")
            return
        }
        owners[row] = owner
        bindings[row] = binding
    }

    func clear() {
        owners.removeAll()
        bindings.removeAll()
    }
}

@MainActor
private struct LazyWidthContextRow: View {
    @State private var value = 41
    let row: Int
    let revision: Int
    let probe: LazyWidthContextProbe

    init(row: Int, revision: Int, probe: LazyWidthContextProbe) {
        self.row = row
        self.revision = revision
        self.probe = probe
    }

    var body: some View {
        probe.record(row, binding: $value)
        return Color.blue.frame(height: 20).accessibilityIdentifier("lazy.width.\(row).\(revision)")
    }
}

@MainActor
private func lazyWidthContextContent(_ probe: LazyWidthContextProbe) -> some View {
    ManagedLazyListContent(
        Array(0..<8), id: \.self, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { row in probe.makeRow(row) }
}
