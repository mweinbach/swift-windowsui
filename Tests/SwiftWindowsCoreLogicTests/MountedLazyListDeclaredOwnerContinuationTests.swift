import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Source fixtures for exact declaration publication through the managed lazy
/// route. These use the headless production driver, not a native window or a
/// substitute state registry. An unevaluated body supplies no removal proof.
@MainActor
final class MountedLazyListDeclaredOwnerContinuationTests: XCTestCase {
    func testColdInactiveConditionalReplacementRetiresOnlyTheDeclaredOldBranch() async throws {
        let probe = LazyDeclaredOwnerProbe(kind: .conditional)
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 160)) {
            lazyDeclaredOwnerContent(probe)
        }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        try host.assertCommittedDescriptor()
        let first = try probe.capture("page", in: host)
        let sibling = try probe.capture("sibling", in: host)
        XCTAssertEqual(first.value.wrappedValue, 10)
        first.value.wrappedValue = 41
        sibling.value.wrappedValue = 73
        XCTAssertNotNil(host.layout())

        probe.selection = "other"
        refreshLazyDeclaredOwnerHost(host)
        let inactiveBuilds = probe.bodyCalls["page", default: 0]
        let factories = probe.factoryCalls["page", default: 0]
        XCTAssertTrue(first.owner.isLive)
        XCTAssertNil(host.find("lazy.declared.page"))
        let physicalRow = try host.rowRoot("lazy.declared.row.0")
        try host.scroll(to: 2_048)
        XCTAssertFalse(host.contains(physicalRow))
        let rowFactories = probe.rowFactoryCalls[0, default: 0]

        probe.firstBranch = false
        refreshLazyDeclaredOwnerHost(host)
        XCTAssertEqual(probe.rowFactoryCalls[0, default: 0], rowFactories)
        XCTAssertEqual(probe.bodyCalls["page", default: 0], inactiveBuilds)
        XCTAssertEqual(probe.factoryCalls["page", default: 0], factories)
        XCTAssertTrue(first.owner.isLive, "An unvisited row has not published a replacement declaration")

        try host.scroll(to: 0)
        XCTAssertGreaterThan(probe.rowFactoryCalls[0, default: 0], rowFactories)
        XCTAssertEqual(probe.bodyCalls["page", default: 0], inactiveBuilds)
        XCTAssertEqual(probe.factoryCalls["page", default: 0], factories)
        XCTAssertNil(host.find("lazy.declared.page"))
        await assertLazyDeclaredOwnerRetired(first, lastValue: 41, in: host)
        try assertLazyDeclaredOwnerSurvives(sibling, named: "sibling", value: 73, probe: probe, host: host)

        probe.selection = "target"
        refreshLazyDeclaredOwnerHost(host)
        let second = try probe.capture("page", in: host)
        XCTAssertEqual(second.value.wrappedValue, 20)
        XCTAssertNotEqual(second.owner.generation, first.owner.generation)
        XCTAssertFalse(second.model === first.model)
        XCTAssertEqual(probe.factoryCalls["page", default: 0], factories + 1)
        await assertLazyDeclaredOwnerRetired(first, lastValue: 41, in: host)

        probe.selection = "other"
        refreshLazyDeclaredOwnerHost(host)
        let secondInactiveBuilds = probe.bodyCalls["page", default: 0]
        probe.firstBranch = true
        refreshLazyDeclaredOwnerHost(host)
        XCTAssertEqual(probe.bodyCalls["page", default: 0], secondInactiveBuilds)
        await assertLazyDeclaredOwnerRetired(second, lastValue: 20, in: host)
        probe.selection = "target"
        refreshLazyDeclaredOwnerHost(host)
        let returned = try probe.capture("page", in: host)
        XCTAssertEqual(returned.value.wrappedValue, 10)
        XCTAssertNotEqual(returned.owner.generation, first.owner.generation)
        XCTAssertNotEqual(returned.owner.generation, second.owner.generation)
        await assertLazyDeclaredOwnerRetired(first, lastValue: 41, in: host)
        try assertLazyDeclaredOwnerSurvives(sibling, named: "sibling", value: 73, probe: probe, host: host)
        XCTAssertEqual(probe.missingOwners, 0)
    }

    func testColdInactiveExplicitIdentityReplacementDoesNotReviveAnOldBinding() async throws {
        let probe = LazyDeclaredOwnerProbe(kind: .identified)
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 160)) {
            lazyDeclaredOwnerContent(probe)
        }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let first = try probe.capture("page", in: host)
        let sibling = try probe.capture("sibling", in: host)
        first.value.wrappedValue = 61
        sibling.value.wrappedValue = 74
        probe.selection = "other"
        refreshLazyDeclaredOwnerHost(host)
        let inactiveBuilds = probe.bodyCalls["page", default: 0]
        let factories = probe.factoryCalls["page", default: 0]
        try host.scroll(to: 2_048)
        let rowFactories = probe.rowFactoryCalls[0, default: 0]

        probe.identifier = 2
        refreshLazyDeclaredOwnerHost(host)
        XCTAssertEqual(probe.rowFactoryCalls[0, default: 0], rowFactories)
        XCTAssertTrue(first.owner.isLive)
        try host.scroll(to: 0)
        XCTAssertEqual(probe.bodyCalls["page", default: 0], inactiveBuilds)
        XCTAssertEqual(probe.factoryCalls["page", default: 0], factories)
        XCTAssertNil(host.find("lazy.declared.page"))
        await assertLazyDeclaredOwnerRetired(first, lastValue: 61, in: host)
        try assertLazyDeclaredOwnerSurvives(sibling, named: "sibling", value: 74, probe: probe, host: host)

        // Reusing the old ID before its page is evaluated must not resurrect
        // the generation retired by the accepted inactive declaration change.
        probe.identifier = 1
        refreshLazyDeclaredOwnerHost(host)
        XCTAssertEqual(probe.bodyCalls["page", default: 0], inactiveBuilds)
        XCTAssertEqual(probe.factoryCalls["page", default: 0], factories)
        await assertLazyDeclaredOwnerRetired(first, lastValue: 61, in: host)
        probe.selection = "target"
        refreshLazyDeclaredOwnerHost(host)
        let replacement = try probe.capture("page", in: host)
        XCTAssertEqual(replacement.value.wrappedValue, 5)
        XCTAssertNotEqual(replacement.owner.generation, first.owner.generation)
        XCTAssertFalse(replacement.model === first.model)
        XCTAssertEqual(probe.factoryCalls["page", default: 0], factories + 1)
        replacement.value.wrappedValue = 91
        XCTAssertNotNil(host.layout())
        await assertLazyDeclaredOwnerRetired(first, lastValue: 61, in: host)
        XCTAssertEqual(replacement.value.wrappedValue, 91)
        try assertLazyDeclaredOwnerSurvives(sibling, named: "sibling", value: 74, probe: probe, host: host)
        XCTAssertEqual(probe.missingOwners, 0)
    }

    func testZeroSlotEmptyOwnerContinuesWhileInactiveAndRetiresOnExactIdentityRemoval() async throws {
        let probe = LazyDeclaredOwnerProbe(kind: .empty)
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 160)) {
            lazyDeclaredOwnerContent(probe)
        }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let first = try probe.emptyOwner(in: host)
        let sibling = try probe.capture("sibling", in: host)
        sibling.value.wrappedValue = 75
        probe.selection = "other"
        refreshLazyDeclaredOwnerHost(host)
        let inactiveBuilds = probe.bodyCalls["empty", default: 0]
        XCTAssertTrue(first.isLive, "An empty owning roster still has a declared component presence")
        try host.scroll(to: 2_048)
        refreshLazyDeclaredOwnerHost(host)
        try host.scroll(to: 0)
        XCTAssertEqual(probe.bodyCalls["empty", default: 0], inactiveBuilds)
        XCTAssertTrue(try probe.emptyOwner(in: host) === first)
        try assertLazyDeclaredOwnerSurvives(sibling, named: "sibling", value: 75, probe: probe, host: host)

        probe.selection = "target"
        refreshLazyDeclaredOwnerHost(host)
        XCTAssertTrue(try probe.emptyOwner(in: host) === first)
        probe.selection = "other"
        refreshLazyDeclaredOwnerHost(host)
        let beforeRemoval = probe.bodyCalls["empty", default: 0]
        probe.identifier = 2
        refreshLazyDeclaredOwnerHost(host)
        XCTAssertEqual(probe.bodyCalls["empty", default: 0], beforeRemoval)
        XCTAssertFalse(first.isLive)
        XCTAssertNil(host.coordinator.registry.owner(at: first.identity))

        probe.identifier = 1
        refreshLazyDeclaredOwnerHost(host)
        XCTAssertEqual(probe.bodyCalls["empty", default: 0], beforeRemoval)
        XCTAssertFalse(first.isLive)
        probe.selection = "target"
        refreshLazyDeclaredOwnerHost(host)
        let replacement = try probe.emptyOwner(in: host)
        XCTAssertFalse(replacement === first)
        XCTAssertNotEqual(replacement.generation, first.generation)
        try assertLazyDeclaredOwnerSurvives(sibling, named: "sibling", value: 75, probe: probe, host: host)
        XCTAssertEqual(probe.missingOwners, 0)
    }

    func testDeferredRegionBecomingEmptyKeepsItsZeroSlotBoundaryAndBothSiblings() async throws {
        let probe = LazyDeclaredOwnerProbe(kind: .regions)
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 160)) {
            lazyDeclaredOwnerContent(probe)
        }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let changing = try probe.capture("changing", in: host)
        let fixed = try probe.capture("fixed", in: host)
        let sibling = try probe.capture("sibling", in: host)
        changing.value.wrappedValue = 81
        fixed.value.wrappedValue = 82
        sibling.value.wrappedValue = 83
        XCTAssertNotNil(host.layout())
        let reader = try XCTUnwrap(
            host.nodes.first { node in
                node.geometryReaderBuild != nil
                    && MountedLazyListTestHost.descendants(in: node).contains {
                        $0.accessibilityIdentifier == "lazy.declared.changing"
                    }
            })
        let boundaryIdentity = try XCTUnwrap(reader.retainedViewIdentity)
        let boundary = try XCTUnwrap(host.coordinator.registry.owner(at: boundaryIdentity))
        let attachment = reader.captureLazyListAttachmentProof()
        let rowFactories = probe.rowFactoryCalls[0, default: 0]
        let fixedBuilds = probe.regionBuilds["fixed", default: 0]
        let changingBuilds = probe.regionBuilds["changing", default: 0]

        // Only the flexible reader's width changes. No root reload or row
        // factory supplies a whole-row declaration table for this update.
        probe.changingRegionPresent = false
        host.runtime.setRootSize(IntSize(width: 384, height: 160))
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.rowFactoryCalls[0, default: 0], rowFactories)
        XCTAssertGreaterThan(probe.regionBuilds["changing", default: 0], changingBuilds)
        XCTAssertEqual(probe.regionBuilds["fixed", default: 0], fixedBuilds)
        XCTAssertNil(host.find("lazy.declared.changing"))
        XCTAssertTrue(host.contains(reader))
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertTrue(boundary.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: boundaryIdentity) === boundary)
        await assertLazyDeclaredOwnerRetired(changing, lastValue: 81, in: host)
        try assertLazyDeclaredOwnerSurvives(fixed, named: "fixed", value: 82, probe: probe, host: host)
        try assertLazyDeclaredOwnerSurvives(sibling, named: "sibling", value: 83, probe: probe, host: host)

        probe.changingRegionPresent = true
        host.runtime.setRootSize(IntSize(width: 416, height: 160))
        XCTAssertNotNil(host.layout())
        let replacement = try probe.capture("changing", in: host)
        XCTAssertEqual(replacement.value.wrappedValue, 30)
        XCTAssertNotEqual(replacement.owner.generation, changing.owner.generation)
        XCTAssertFalse(replacement.model === changing.model)
        XCTAssertEqual(probe.rowFactoryCalls[0, default: 0], rowFactories)
        XCTAssertEqual(probe.regionBuilds["fixed", default: 0], fixedBuilds)
        XCTAssertTrue(host.coordinator.registry.owner(at: boundaryIdentity) === boundary)
        await assertLazyDeclaredOwnerRetired(changing, lastValue: 81, in: host)
        try assertLazyDeclaredOwnerSurvives(fixed, named: "fixed", value: 82, probe: probe, host: host)
        try assertLazyDeclaredOwnerSurvives(sibling, named: "sibling", value: 83, probe: probe, host: host)
        XCTAssertEqual(probe.missingOwners, 0)
    }
}

@MainActor
private func refreshLazyDeclaredOwnerHost(
    _ host: MountedLazyListTestHost, file: StaticString = #filePath, line: UInt = #line
) {
    host.reload()
    XCTAssertNotNil(host.layout(), file: file, line: line)
}

@MainActor
private func assertLazyDeclaredOwnerRetired(
    _ capture: LazyDeclaredOwnerCapture, lastValue: Int, in host: MountedLazyListTestHost,
    file: StaticString = #filePath, line: UInt = #line
) async {
    XCTAssertFalse(capture.owner.isLive, file: file, line: line)
    XCTAssertFalse(
        host.coordinator.registry.owner(at: capture.owner.identity) === capture.owner, file: file, line: line)
    let invalidations = host.events.stateInvalidations
    let completions = host.events.rootCompletions
    capture.value.wrappedValue = lastValue + 1_000
    XCTAssertEqual(capture.value.wrappedValue, lastValue, file: file, line: line)
    XCTAssertEqual(host.events.stateInvalidations, invalidations, file: file, line: line)
    XCTAssertEqual(host.events.rootCompletions, completions, file: file, line: line)
    await Task.yield()
    XCTAssertEqual(capture.value.wrappedValue, lastValue, file: file, line: line)
    XCTAssertEqual(host.events.stateInvalidations, invalidations, file: file, line: line)
    XCTAssertEqual(host.events.rootCompletions, completions, file: file, line: line)
}

@MainActor
private func assertLazyDeclaredOwnerSurvives(
    _ original: LazyDeclaredOwnerCapture, named name: String, value: Int,
    probe: LazyDeclaredOwnerProbe, host: MountedLazyListTestHost,
    file: StaticString = #filePath, line: UInt = #line
) throws {
    let current = try probe.capture(name, in: host, file: file, line: line)
    XCTAssertTrue(current.owner === original.owner, file: file, line: line)
    XCTAssertEqual(current.owner.generation, original.owner.generation, file: file, line: line)
    XCTAssertTrue(current.model === original.model, file: file, line: line)
    XCTAssertEqual(current.value.wrappedValue, value, file: file, line: line)
    XCTAssertEqual(original.value.wrappedValue, value, file: file, line: line)
}

@MainActor
private struct LazyDeclaredOwnerCapture {
    let owner: StateMountOwner
    let value: Binding<Int>
    let model: MountedLazyListModel
}

@MainActor
private final class LazyDeclaredOwnerProbe {
    enum Kind: Equatable {
        case conditional
        case identified
        case empty
        case regions
    }

    let kind: Kind
    var selection = "target"
    var firstBranch = true
    var identifier = 1
    var changingRegionPresent = true
    var bodyCalls: [String: Int] = [:]
    var factoryCalls: [String: Int] = [:]
    var rowFactoryCalls: [Int: Int] = [:]
    var regionBuilds: [String: Int] = [:]
    private(set) var missingOwners = 0
    private var captures: [String: [UInt64: LazyDeclaredOwnerCapture]] = [:]
    private var emptyOwners: [UInt64: StateMountOwner] = [:]

    init(kind: Kind) { self.kind = kind }

    func makeModel(_ name: String, seed: Int) -> MountedLazyListModel {
        factoryCalls[name, default: 0] += 1
        return MountedLazyListModel(value: seed, serial: factoryCalls[name, default: 0])
    }

    func record(_ name: String, value: Binding<Int>, model: MountedLazyListModel) {
        bodyCalls[name, default: 0] += 1
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            missingOwners += 1
            return
        }
        captures[name, default: [:]][owner.generation] = LazyDeclaredOwnerCapture(
            owner: owner, value: value, model: model)
    }

    func recordEmptyOwner() {
        bodyCalls["empty", default: 0] += 1
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            missingOwners += 1
            return
        }
        emptyOwners[owner.generation] = owner
    }

    func capture(
        _ name: String, in host: MountedLazyListTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> LazyDeclaredOwnerCapture {
        let matches = (captures[name] ?? [:]).values.filter {
            $0.owner.isLive && host.coordinator.registry.owner(at: $0.owner.identity) === $0.owner
        }
        XCTAssertEqual(matches.count, 1, "Expected one accepted owner for \(name)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func emptyOwner(
        in host: MountedLazyListTestHost, file: StaticString = #filePath, line: UInt = #line
    ) throws -> StateMountOwner {
        let matches = emptyOwners.values.filter {
            $0.isLive && host.coordinator.registry.owner(at: $0.identity) === $0
        }
        XCTAssertEqual(matches.count, 1, "Expected one accepted empty owner", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func makeRow(_ row: Int) -> AnyView {
        rowFactoryCalls[row, default: 0] += 1
        guard row == 0 else { return AnyView(Color.gray.frame(height: 160)) }
        if kind == .regions { return AnyView(LazyDeclaredOwnerRegions(probe: self)) }
        return AnyView(LazyDeclaredOwnerTabs(probe: self))
    }

    func page() -> AnyView {
        switch kind {
        case .conditional:
            return AnyView(
                _ConditionalContent<LazyDeclaredOwnerCounter, LazyDeclaredOwnerCounter>(
                    storage: firstBranch
                        ? .trueContent(LazyDeclaredOwnerCounter(name: "page", seed: 10, probe: self))
                        : .falseContent(LazyDeclaredOwnerCounter(name: "page", seed: 20, probe: self))
                ).padding(2))
        case .identified:
            return AnyView(LazyDeclaredOwnerCounter(name: "page", seed: 5, probe: self).id(identifier).padding(2))
        case .empty:
            return AnyView(LazyDeclaredOwnerEmptyPage(probe: self).id(identifier).padding(2))
        case .regions:
            return AnyView(EmptyView())
        }
    }

    func region(_ name: String) -> [AnyView] {
        regionBuilds[name, default: 0] += 1
        if name == "changing", !changingRegionPresent { return [] }
        return [AnyView(LazyDeclaredOwnerCounter(name: name, seed: name == "changing" ? 30 : 40, probe: self))]
    }

    func clear() {
        captures.removeAll()
        emptyOwners.removeAll()
    }
}

@MainActor
private struct LazyDeclaredOwnerCounter: View {
    @State private var value: Int
    @StateObject private var model: MountedLazyListModel
    let name: String
    let probe: LazyDeclaredOwnerProbe

    init(name: String, seed: Int, probe: LazyDeclaredOwnerProbe) {
        self.name = name
        self.probe = probe
        _value = State(initialValue: seed)
        _model = StateObject(wrappedValue: probe.makeModel(name, seed: seed))
    }

    var body: some View {
        probe.record(name, value: $value, model: model)
        return Color.blue.frame(height: 16).accessibilityIdentifier("lazy.declared.\(name)")
    }
}

@MainActor
private struct LazyDeclaredOwnerEmptyPage: View {
    let probe: LazyDeclaredOwnerProbe

    var body: some View {
        probe.recordEmptyOwner()
        return EmptyView()
    }
}

@MainActor
private struct LazyDeclaredOwnerTabs: View {
    let probe: LazyDeclaredOwnerProbe

    var body: some View {
        let selection = Binding(get: { probe.selection }, set: { probe.selection = $0 })
        return VStack(spacing: 0) {
            LazyDeclaredOwnerCounter(name: "sibling", seed: 70, probe: probe)
            TabView(selection: selection) {
                probe.page().tag("target").tabItem { Text("Target") }
                Color.gray.frame(height: 72).tag("other").tabItem { Text("Other") }
            }
            .frame(height: 120)
        }
        .frame(height: 160)
        .accessibilityIdentifier("lazy.declared.row.0")
    }
}

@MainActor
private struct LazyDeclaredOwnerRegions: View {
    let probe: LazyDeclaredOwnerProbe

    var body: some View {
        VStack(spacing: 0) {
            LazyDeclaredOwnerCounter(name: "sibling", seed: 70, probe: probe)
            GeometryReader { _ in probe.region("changing") }
                .frame(height: 40)
            GeometryReader { _ in probe.region("fixed") }
                .frame(width: 80, height: 40)
        }
        .frame(height: 160)
        .accessibilityIdentifier("lazy.declared.row.0")
    }
}

@MainActor
private func lazyDeclaredOwnerContent(_ probe: LazyDeclaredOwnerProbe) -> some View {
    ManagedLazyListContent(
        Array(0..<40), id: \.self, estimatedExtent: 160, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 32, maximumProtectedRecords: 2
    ) { row in probe.makeRow(row) }
}
