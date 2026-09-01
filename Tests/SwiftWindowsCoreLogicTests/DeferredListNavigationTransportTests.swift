import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A fresh deferred controller must use the accepted retained List after its
/// temporary construction node is discarded. Old prepared actions alone do
/// not exercise this handoff.
@MainActor
final class DeferredListNavigationTransportTests: XCTestCase {
    private static let down = KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue)

    func testPaddedGeometryReaderNavigatesAfterRebuildWithHeldOrReleasedCandidates() async throws {
        for holdCandidate in [false, true] {
            let fixture = DeferredNavigationTransportFixture(geometry: true)
            defer { fixture.close() }
            let target = try fixture.list()
            let reader = try XCTUnwrap(
                RetainedListPaintAssertions.descendants(in: fixture.content).first { $0.geometryReaderBuild != nil })
            let build = try XCTUnwrap(reader.geometryReaderBuild)
            var captured: DeferredNavigationTransportCandidate?
            var heldSource: ViewNode?
            var slots: [Size] = []
            defer { heldSource = nil }
            // Observe the real resolved-size callback and return its original
            // candidates unchanged. Holding one changes only its lifetime.
            reader.geometryReaderBuild = { runtime, slot in
                let candidates = build(runtime, slot)
                slots.append(slot)
                let lists = candidates.flatMap { RetainedListPaintAssertions.descendants(in: $0) }
                    .filter { $0.retainedLazyListAdapter != nil }
                XCTAssertEqual(candidates.count, 1)
                XCTAssertEqual(lists.count, 1)
                if let root = candidates.first, let list = lists.first {
                    captured = try? DeferredNavigationTransportCandidate(
                        sourceRoot: root, sourceList: list, target: target)
                    if holdCandidate { heldSource = root }
                }
                return candidates
            }

            let scene = try fixture.attachAndRender()

            let candidate = try XCTUnwrap(captured)
            let runtime = try XCTUnwrap(fixture.runtime)
            let slot = try XCTUnwrap(slots.last)
            XCTAssertEqual(slots.count, 1)
            XCTAssertEqual(runtime.geometryReaderResolveCount, 1)
            XCTAssertEqual(slot.width, 228, accuracy: 0.01)
            XCTAssertEqual(slot.height, 208, accuracy: 0.01)
            XCTAssertEqual(fixture.probe.geometrySizes.last, slot)
            XCTAssertTrue(try fixture.list() === target)
            XCTAssertTrue(target.retainedLazyListAdapter === candidate.adapter)
            XCTAssertTrue(target.retainedSubtreeBuildLease === candidate.lease)
            XCTAssertTrue(candidate.adapter.ownsAttachment(target))
            XCTAssertTrue(candidate.lease.canBuild)
            if holdCandidate {
                XCTAssertTrue(heldSource === candidate.sourceRoot)
                XCTAssertNotNil(candidate.sourceRoot)
                XCTAssertNotNil(candidate.sourceList)
                XCTAssertFalse(candidate.adapter.ownsAttachment(try XCTUnwrap(candidate.sourceList)))
            } else {
                XCTAssertNil(candidate.sourceRoot)
                XCTAssertNil(candidate.sourceList)
            }
            try RetainedListPaintAssertions.labels(
                fixture.labels(prefix: "Before"), in: target, scene: scene,
                size: DeferredNavigationTransportFixture.size)

            try assertFreshKeyboardAction(in: fixture)

            withExtendedLifetime(heldSource) {}
            heldSource = nil
            XCTAssertNil(candidate.sourceRoot)
            XCTAssertNil(candidate.sourceList)
        }
    }

    func testAcceptedReplacementUsesTheRetainedContainerWhileTheCandidateIsStillAlive() async throws {
        let fixture = DeferredNavigationTransportFixture()
        defer { fixture.close() }
        _ = try fixture.attachAndRender()
        let target = try fixture.list()
        let oldKey = try XCTUnwrap(try fixture.row(0).onKeyDown)
        let sourceRoot = fixture.makeContent(prefix: "After")
        let source = try RetainedListPaintAssertions.list(in: sourceRoot)
        let incoming = try XCTUnwrap(source.retainedLazyListAdapter)
        let lease = try XCTUnwrap(source.retainedSubtreeBuildLease)
        XCTAssertFalse(lease.canBuild)

        ComponentHost.adopt(source: sourceRoot, into: fixture.content)

        XCTAssertTrue(try fixture.list() === target)
        XCTAssertTrue(target.retainedLazyListAdapter === incoming)
        XCTAssertTrue(target.retainedSubtreeBuildLease === lease)
        XCTAssertTrue(incoming.ownsAttachment(target))
        XCTAssertFalse(incoming.ownsAttachment(source))
        source.retainedSubtreeBuildLease = nil
        XCTAssertFalse(incoming.claimAttachment(to: source))
        XCTAssertTrue(lease.canBuild)
        let scene = try fixture.render()
        try RetainedListPaintAssertions.labels(
            fixture.labels(prefix: "After"), in: target, scene: scene, size: DeferredNavigationTransportFixture.size)
        fixture.probe.resetTrace()
        oldKey(Self.down)
        assertNoEffects(fixture.probe)

        try assertFreshKeyboardAction(in: fixture)

        withExtendedLifetime((sourceRoot, source)) {}
    }

    func testAcceptedReplacementKeepsFreshKeyboardNavigationAfterTheCandidateIsReleased() async throws {
        let fixture = DeferredNavigationTransportFixture()
        defer { fixture.close() }
        _ = try fixture.attachAndRender()
        let oldKey = try XCTUnwrap(try fixture.row(0).onKeyDown)

        let candidate = try fixture.adoptReplacement()

        try assertAcceptedReplacement(candidate, in: fixture)
        let scene = try fixture.render()
        try RetainedListPaintAssertions.labels(
            fixture.labels(prefix: "After"), in: candidate.target, scene: scene,
            size: DeferredNavigationTransportFixture.size)
        fixture.probe.resetTrace()
        oldKey(Self.down)
        assertNoEffects(fixture.probe)

        try assertFreshKeyboardAction(in: fixture)
    }

    func testAdoptedPhysicalRowsRemainNavigableAfterPlainRuntimeAndLogicalHostExpiry() async throws {
        let fixture = DeferredNavigationTransportFixture()
        _ = try fixture.attachAndRender()
        let candidate = try fixture.adoptReplacement()
        try assertAcceptedReplacement(candidate, in: fixture)
        _ = try fixture.render()
        let key = try XCTUnwrap(try fixture.row(0).onKeyDown)
        weak var expiredRuntime = fixture.runtime
        weak var expiredLogicalHost = fixture.runtime?.lazyListLogicalHostLifetime

        fixture.runtime = nil
        fixture.probe.resetTrace()

        XCTAssertNil(expiredRuntime)
        XCTAssertNil(expiredLogicalHost, "Navigation must not retain descriptor or logical-row authority")
        XCTAssertNil(candidate.sourceRoot)
        XCTAssertNil(candidate.sourceList)
        XCTAssertFalse(candidate.lease.canBuild)
        key(Self.down)
        XCTAssertEqual(fixture.probe.selected, 1)
        XCTAssertEqual(fixture.probe.writes, [1])
        XCTAssertEqual(fixture.probe.invalidations, 1)
        XCTAssertTrue(fixture.probe.factories.isEmpty, "Only already realized direct-data rows remain available")
    }

    func testManagedPreparedContinuationIsFollowedByANewKeyboardActionAfterRebuild() async throws {
        let probe = DeferredNavigationTransportProbe(count: 32)
        let host = MountedLazyListTestHost(size: Size(width: 260, height: 200)) {
            List(selection: probe.binding) {
                ForEach(probe.rows, id: \.self) { probe.row($0, prefix: "Managed") }
            }
            .listStyle(.plain)
            .frame(width: 260, height: 200)
        }
        defer {
            probe.onSet = nil
            host.close()
        }
        XCTAssertNotNil(host.layout())
        XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 8))
        let targetList = try host.list()
        let oldKey = try XCTUnwrap(try managedRow(0, in: host).onKeyDown)
        XCTAssertNil(findManagedRow(24, in: host))
        probe.selected = 23
        var prepared: ViewNode?
        probe.onSet = { [weak host] in
            prepared = host?.nodes.first { DeferredListRowNavigation.attached(to: $0)?.ordinal == 24 }
        }
        let buildsBefore = host.events.rootCompletions
        let callsBefore = probe.factories.count

        oldKey(Self.down)
        XCTAssertLessThanOrEqual(probe.factories.count - callsBefore, 8)
        settleManagedNavigation(in: host, probe: probe, expected: 24)

        let destination = try XCTUnwrap(prepared)
        XCTAssertTrue(try managedRow(24, in: host) === destination)
        XCTAssertTrue(host.runtime.focusedNode === destination)
        XCTAssertEqual(probe.writes, [24])
        XCTAssertEqual(host.events.rootCompletions, buildsBefore + 1)
        XCTAssertTrue(try host.list() === targetList)
        let incoming = try XCTUnwrap(targetList.retainedLazyListAdapter)
        XCTAssertTrue(incoming.ownsAttachment(targetList))
        let freshKey = try XCTUnwrap(destination.onKeyDown)
        probe.onSet = nil
        probe.resetTrace(selection: 24)
        oldKey(Self.down)
        assertNoEffects(probe)
        XCTAssertTrue(host.runtime.focusedNode === destination)

        freshKey(Self.down)
        XCTAssertLessThanOrEqual(probe.factories.count, 8)
        settleManagedNavigation(in: host, probe: probe, expected: 25)

        XCTAssertEqual(probe.selected, 25)
        XCTAssertEqual(probe.writes, [25])
        XCTAssertTrue(host.runtime.focusedNode === (try managedRow(25, in: host)))
        XCTAssertEqual(host.events.rootCompletions, buildsBefore + 2)
        XCTAssertLessThan(try XCTUnwrap(try host.list().retainedLazyListAdapter).mountedRecordCount, 32)
    }

    func testRejectedForeignCandidateCanStillBindItsFirstAcceptedRetainedContainer() async throws {
        let fixture = DeferredNavigationTransportFixture()
        defer { fixture.close() }
        _ = try fixture.attachAndRender()
        let target = try fixture.list()
        let sourceRoot = fixture.makeContent(prefix: "After")
        let source = try RetainedListPaintAssertions.list(in: sourceRoot)
        let incoming = try XCTUnwrap(source.retainedLazyListAdapter)
        let lease = try XCTUnwrap(source.retainedSubtreeBuildLease)
        let foreign = RetainedViewRuntime(root: ViewNode())
        defer {
            foreign.stopRenderLifecycleCallbacks()
            foreign.cancelRenderLifecycleTasks()
        }
        foreign.setRootSize(DeferredNavigationTransportFixture.size)
        fixture.probe.resetTrace()
        XCTAssertFalse(incoming.claimAttachment(to: source))

        foreign.root.addChild(sourceRoot)
        _ = foreign.renderScene(at: 0)

        XCTAssertFalse(incoming.ownsAttachment(source))
        XCTAssertFalse(lease.canBuild)
        assertNoEffects(fixture.probe)
        foreign.stopRenderLifecycleCallbacks()
        foreign.root.removeChild(sourceRoot)
        ComponentHost.adopt(source: sourceRoot, into: fixture.content)
        XCTAssertTrue(try fixture.list() === target)
        XCTAssertTrue(target.retainedLazyListAdapter === incoming)
        XCTAssertTrue(target.retainedSubtreeBuildLease === lease)
        XCTAssertTrue(incoming.ownsAttachment(target))
        XCTAssertFalse(incoming.ownsAttachment(source))
        let scene = try fixture.render()
        try RetainedListPaintAssertions.labels(
            fixture.labels(prefix: "After"), in: target, scene: scene, size: DeferredNavigationTransportFixture.size)

        try assertFreshKeyboardAction(in: fixture)
    }

    func testDepartureAndSameNodeReinstallationCannotReviveAnAdoptedController() async throws {
        let fixture = DeferredNavigationTransportFixture()
        defer { fixture.close() }
        _ = try fixture.attachAndRender()
        let candidate = try fixture.adoptReplacement()
        try assertAcceptedReplacement(candidate, in: fixture)
        _ = try fixture.render()
        let row = try fixture.row(0)
        let key = try XCTUnwrap(row.onKeyDown)
        let activate = try XCTUnwrap(row.onActivate)
        let runtime = try XCTUnwrap(fixture.runtime)
        fixture.probe.resetTrace()

        runtime.root.removeChild(fixture.content)
        runtime.root.addChild(fixture.content)
        key(Self.down)
        activate()
        _ = try fixture.render()
        key(Self.down)

        XCTAssertFalse(candidate.lease.canBuild)
        XCTAssertFalse(candidate.adapter.ownsAttachment(candidate.target))
        assertNoEffects(fixture.probe)
    }

    func testRawAdapterReleaseOrReplacementCannotReclaimAnAdoptedController() async throws {
        for removeSlot in [false, true] {
            let fixture = DeferredNavigationTransportFixture()
            defer { fixture.close() }
            _ = try fixture.attachAndRender()
            let candidate = try fixture.adoptReplacement()
            try assertAcceptedReplacement(candidate, in: fixture)
            _ = try fixture.render()
            let row = try fixture.row(0)
            let key = try XCTUnwrap(row.onKeyDown)
            let activate = try XCTUnwrap(row.onActivate)
            fixture.probe.resetTrace()

            if removeSlot {
                candidate.target.retainedLazyListAdapter = nil
                candidate.target.retainedLazyListAdapter = candidate.adapter
            } else {
                XCTAssertTrue(candidate.adapter.releaseAttachment(from: candidate.target))
            }
            XCTAssertFalse(candidate.adapter.claimAttachment(to: candidate.target))
            key(Self.down)
            activate()
            _ = try fixture.render()
            key(Self.down)

            XCTAssertFalse(candidate.adapter.ownsAttachment(candidate.target))
            XCTAssertFalse(candidate.lease.canBuild)
            assertNoEffects(fixture.probe)
        }
    }

    func testIdentityOrLeaseABACannotRefreshAnAdoptedControllersAttachment() async throws {
        for replaceLease in [false, true] {
            let fixture = DeferredNavigationTransportFixture()
            defer { fixture.close() }
            _ = try fixture.attachAndRender()
            let candidate = try fixture.adoptReplacement()
            try assertAcceptedReplacement(candidate, in: fixture)
            _ = try fixture.render()
            let row = try fixture.row(0)
            let key = try XCTUnwrap(row.onKeyDown)
            let activate = try XCTUnwrap(row.onActivate)
            fixture.probe.resetTrace()

            if replaceLease {
                candidate.target.retainedSubtreeBuildLease = nil
                candidate.target.retainedSubtreeBuildLease = candidate.lease
            } else {
                let identity = candidate.target.retainedViewIdentity
                candidate.target.retainedViewIdentity = identity
            }
            key(Self.down)
            activate()
            _ = try fixture.render()
            key(Self.down)

            XCTAssertFalse(candidate.lease.canBuild)
            XCTAssertNil(candidate.lease.beginBuild())
            assertNoEffects(fixture.probe)
        }
    }

    private func assertFreshKeyboardAction(
        in fixture: DeferredNavigationTransportFixture, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let runtime = try XCTUnwrap(fixture.runtime, file: file, line: line)
        let source = try fixture.row(0)
        let target = try fixture.row(1)
        XCTAssertNotNil(source.onKeyDown, file: file, line: line)
        runtime.requestFocus(source)
        fixture.probe.resetTrace()

        runtime.keyDown(Self.down)

        XCTAssertEqual(fixture.probe.selected, 1, file: file, line: line)
        XCTAssertEqual(fixture.probe.writes, [1], file: file, line: line)
        XCTAssertEqual(fixture.probe.invalidations, 1, file: file, line: line)
        XCTAssertTrue(runtime.focusedNode === target, file: file, line: line)
        XCTAssertTrue(
            fixture.probe.factories.isEmpty, "A realized neighbor needs no factory pass", file: file, line: line)
    }

    private func assertAcceptedReplacement(
        _ candidate: DeferredNavigationTransportCandidate, in fixture: DeferredNavigationTransportFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertNil(candidate.sourceRoot, file: file, line: line)
        XCTAssertNil(candidate.sourceList, file: file, line: line)
        XCTAssertTrue(try fixture.list() === candidate.target, file: file, line: line)
        XCTAssertTrue(candidate.target.retainedLazyListAdapter === candidate.adapter, file: file, line: line)
        XCTAssertTrue(candidate.target.retainedSubtreeBuildLease === candidate.lease, file: file, line: line)
        XCTAssertTrue(candidate.adapter.ownsAttachment(candidate.target), file: file, line: line)
        XCTAssertTrue(candidate.lease.canBuild, file: file, line: line)
    }

    private func assertNoEffects(
        _ probe: DeferredNavigationTransportProbe, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(probe.reads, 0, file: file, line: line)
        XCTAssertTrue(probe.writes.isEmpty, file: file, line: line)
        XCTAssertEqual(probe.invalidations, 0, file: file, line: line)
        XCTAssertTrue(probe.factories.isEmpty, file: file, line: line)
    }

    private func findManagedRow(_ ordinal: Int, in host: MountedLazyListTestHost) -> ViewNode? {
        host.nodes.first { DeferredListRowNavigation.attached(to: $0)?.ordinal == ordinal }
    }

    private func managedRow(_ ordinal: Int, in host: MountedLazyListTestHost) throws -> ViewNode {
        try XCTUnwrap(findManagedRow(ordinal, in: host))
    }

    private func settleManagedNavigation(
        in host: MountedLazyListTestHost, probe: DeferredNavigationTransportProbe, expected: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<24 {
            let callsBefore = probe.factories.count
            host.render()
            XCTAssertLessThanOrEqual(probe.factories.count - callsBefore, 8, file: file, line: line)
            let ordinal = host.runtime.focusedNode.flatMap { DeferredListRowNavigation.attached(to: $0)?.ordinal }
            if !host.runtime.hasPendingLayout, probe.selected == expected, ordinal == expected { return }
        }
        XCTFail("The prepared focus must settle within the bounded passes", file: file, line: line)
    }
}

@MainActor
private final class DeferredNavigationTransportProbe {
    let rows: [Int]
    var selected: Int? = 0
    var reads = 0
    var writes: [Int?] = []
    var invalidations = 0
    var factories: [String] = []
    var geometrySizes: [Size] = []
    var onSet: (() -> Void)?

    init(count: Int = 4) { rows = Array(0..<count) }

    var binding: Binding<Int?> {
        Binding(
            get: {
                self.reads += 1
                return self.selected
            },
            set: {
                self.selected = $0
                self.writes.append($0)
                self.onSet?()
            })
    }

    func resetTrace(selection: Int? = 0) {
        selected = selection
        reads = 0
        writes = []
        invalidations = 0
        factories = []
    }

    func row(_ index: Int, prefix: String) -> some View {
        let label = "\(prefix) \(index)"
        factories.append(label)
        return Text(label).font(.system(size: 13)).frame(height: 32)
            .accessibilityIdentifier("transport-row-\(index)").tag(index)
    }

    func list(prefix: String, size: Size) -> some View {
        List(rows, id: \.self, selection: binding) { self.row($0, prefix: prefix) }
            .listStyle(.plain).frame(width: size.width, height: size.height)
    }

    func geometryContent(prefix: String, size: Size) -> some View {
        geometrySizes.append(size)
        return list(prefix: prefix, size: size)
    }
}

@MainActor
private final class DeferredNavigationTransportCandidate {
    weak var sourceRoot: ViewNode?
    weak var sourceList: ViewNode?
    let target: ViewNode
    let adapter: RetainedLazyListRuntimeAdapter
    let lease: any RetainedSubtreeBuildLease

    init(sourceRoot: ViewNode, sourceList: ViewNode, target: ViewNode) throws {
        self.sourceRoot = sourceRoot
        self.sourceList = sourceList
        self.target = target
        adapter = try XCTUnwrap(sourceList.retainedLazyListAdapter)
        lease = try XCTUnwrap(sourceList.retainedSubtreeBuildLease)
    }
}

@MainActor
private final class DeferredNavigationTransportFixture {
    static let size = IntSize(width: 260, height: 240)
    var runtime: RetainedViewRuntime?
    let probe: DeferredNavigationTransportProbe
    let content: ViewNode
    private let geometry: Bool

    init(geometry: Bool = false) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let probe = DeferredNavigationTransportProbe()
        runtime.clock = { 0 }
        runtime.setRootSize(Self.size)
        self.runtime = runtime
        self.probe = probe
        self.geometry = geometry
        content = Self.makeContent(runtime: runtime, probe: probe, prefix: "Before", geometry: geometry)
    }

    func makeContent(prefix: String) -> ViewNode {
        Self.makeContent(runtime: runtime!, probe: probe, prefix: prefix, geometry: geometry)
    }

    func adoptReplacement() throws -> DeferredNavigationTransportCandidate {
        let sourceRoot = makeContent(prefix: "After")
        let candidate = try DeferredNavigationTransportCandidate(
            sourceRoot: sourceRoot, sourceList: RetainedListPaintAssertions.list(in: sourceRoot), target: list())
        ComponentHost.adopt(source: sourceRoot, into: content)
        return candidate
    }

    func attachAndRender() throws -> GPUIScene {
        try XCTUnwrap(runtime).root.addChild(content)
        return try render()
    }

    func render() throws -> GPUIScene { try XCTUnwrap(runtime).renderScene(at: 0) }

    func list() throws -> ViewNode { try RetainedListPaintAssertions.list(in: content) }

    func row(_ ordinal: Int) throws -> ViewNode {
        try XCTUnwrap(
            RetainedListPaintAssertions.descendants(in: content).first {
                DeferredListRowNavigation.attached(to: $0)?.ordinal == ordinal
            })
    }

    func labels(prefix: String) -> [String] { probe.rows.map { "\(prefix) \($0)" } }

    func close() {
        runtime?.stopRenderLifecycleCallbacks()
        runtime?.cancelRenderLifecycleTasks()
    }

    private static func makeContent(
        runtime: RetainedViewRuntime, probe: DeferredNavigationTransportProbe, prefix: String, geometry: Bool
    ) -> ViewNode {
        let size = Size(width: 260, height: 240)
        let context = ViewBuildContext(
            canvasSizeProvider: { size }, invalidateHandler: { probe.invalidations += 1 })
        let view: AnyView
        if geometry {
            view = AnyView(
                GeometryReader { proxy in probe.geometryContent(prefix: prefix, size: proxy.size) }
                    .padding(16).frame(width: size.width, height: size.height))
        } else {
            view = AnyView(probe.list(prefix: prefix, size: size))
        }
        return view.makeComponent(context: context).makeNode(runtime: runtime)
    }
}
