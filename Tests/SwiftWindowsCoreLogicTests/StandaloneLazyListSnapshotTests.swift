import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Direct snapshots use the ordinary public List path without a mounted State
/// coordinator. These cases exercise actual attachment and first-scene paint.
@MainActor
final class StandaloneLazyListSnapshotTests: XCTestCase {
    func testPaddedGeometryReaderPaintsEveryPublicListRowInTheFirstSnapshot() async throws {
        let names = ["Welcome.txt", "Unicode.txt", "Empty.txt", "Invalid UTF-8.txt"]
        let view = GeometryReader { geometry in
            List(names, id: \.self) { name in
                Text(name).font(.system(size: 13))
            }
            .listStyle(.plain)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(16)
        .frame(width: 320, height: 240)
        let result = WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: IntSize(width: 320, height: 240), colorScheme: .dark)
        let list = try RetainedListPaintAssertions.list(in: result.runtime.root)

        XCTAssertGreaterThan(result.runtime.geometryReaderResolveCount, 0)
        XCTAssertTrue(try XCTUnwrap(list.retainedLazyListAdapter).ownsAttachment(list))
        XCTAssertTrue(try XCTUnwrap(list.retainedSubtreeBuildLease).canBuild)
        try RetainedListPaintAssertions.labels(names, in: list, scene: result.scene, size: result.size)
    }

    func testAcceptedCopyBindsTheRetainedTargetAndDiscardsTheSourceAuthority() async throws {
        let fixture = StandaloneListFixture()
        fixture.attach()
        _ = fixture.runtime.renderScene(at: 0)
        let target = try fixture.list()
        let oldLease = try XCTUnwrap(target.retainedSubtreeBuildLease)
        let oldEpoch = try XCTUnwrap(oldLease.beginBuild())
        let sourceRoot = fixture.makeContent(prefix: "After")
        let source = try RetainedListPaintAssertions.list(in: sourceRoot)
        let incomingAdapter = try XCTUnwrap(source.retainedLazyListAdapter)
        let incomingLease = try XCTUnwrap(source.retainedSubtreeBuildLease)
        XCTAssertFalse(incomingLease.canBuild)
        XCTAssertNil(incomingLease.beginBuild())

        ComponentHost.adopt(source: sourceRoot, into: fixture.content)

        XCTAssertTrue(try fixture.list() === target)
        XCTAssertTrue(target.retainedLazyListAdapter === incomingAdapter)
        XCTAssertTrue(target.retainedSubtreeBuildLease === incomingLease)
        XCTAssertTrue(incomingAdapter.ownsAttachment(target))
        XCTAssertFalse(incomingAdapter.ownsAttachment(source))
        XCTAssertFalse(source.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertTrue(incomingLease.canBuild)
        XCTAssertFalse(oldLease.canBuild)
        XCTAssertFalse(oldEpoch.canAdopt)
        XCTAssertFalse(oldEpoch.canComplete)

        // The discarded candidate still references the transported native
        // payload. Its setter and a foreign claim cannot revoke or retarget it.
        source.retainedSubtreeBuildLease = nil
        XCTAssertFalse(incomingAdapter.claimAttachment(to: source))
        XCTAssertTrue(incomingLease.canBuild)
        XCTAssertTrue(incomingAdapter.ownsAttachment(target))
        let scene = fixture.runtime.renderScene(at: 0)
        try RetainedListPaintAssertions.labels(
            fixture.names(prefix: "After"), in: target, scene: scene, size: fixture.size)
    }

    func testEquivalentLeaseAndAdapterAssignmentsPreserveTheAcceptedAttachment() async throws {
        let fixture = StandaloneListFixture()
        fixture.attach()
        _ = fixture.runtime.renderScene(at: 0)
        let list = try fixture.list()
        let lease = try XCTUnwrap(list.retainedSubtreeBuildLease)
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)

        list.retainedSubtreeBuildLease = lease
        list.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.claimAttachment(to: list))

        XCTAssertTrue(lease.canBuild)
        let scene = fixture.runtime.renderScene(at: 0)
        try RetainedListPaintAssertions.labels(
            fixture.names(), in: list, scene: scene, size: fixture.size)
    }

    func testDetachAndSameNodeReattachCannotReviveLeaseOrEpoch() async throws {
        try assertRevocation { fixture, _, _, _ in
            fixture.runtime.root.removeChild(fixture.content)
            fixture.runtime.root.addChild(fixture.content)
        }
    }

    func testNeverObservedAttachmentCannotBeRecapturedAfterDetach() async throws {
        let fixture = StandaloneListFixture()
        fixture.attach()
        let list = try fixture.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        let lease = try XCTUnwrap(list.retainedSubtreeBuildLease)
        XCTAssertTrue(adapter.ownsAttachment(list))
        // No render, lease validity getter, or beginBuild has observed this
        // first attachment. Publication itself must have captured its proof.
        fixture.runtime.root.removeChild(fixture.content)
        fixture.attach()

        XCTAssertFalse(lease.canBuild)
        XCTAssertNil(lease.beginBuild())
        XCTAssertFalse(adapter.ownsAttachment(list))
        _ = fixture.runtime.renderScene(at: 0)
        XCTAssertTrue(fixture.probe.built.isEmpty)
    }

    func testLeaseRemovalAndReinstallationCannotReviveLeaseOrEpoch() async throws {
        try assertRevocation { _, list, _, lease in
            list.retainedSubtreeBuildLease = nil
            list.retainedSubtreeBuildLease = lease
        }
    }

    func testAdapterRemovalAndReinstallationCannotReviveLeaseOrEpoch() async throws {
        try assertRevocation { _, list, adapter, _ in
            list.retainedLazyListAdapter = nil
            list.retainedLazyListAdapter = adapter
        }
    }

    func testSameValueIdentityAssignmentCannotRefreshTheAcceptedProof() async throws {
        try assertRevocation { _, list, _, _ in
            let identity = list.retainedViewIdentity
            list.retainedViewIdentity = identity
        }
    }

    func testPermissiveForeignLeaseCannotReopenTheRevokedAdapter() async throws {
        let foreign = StandaloneForeignLease()
        try assertRevocation { _, list, _, _ in
            list.retainedSubtreeBuildLease = foreign
        }
        XCTAssertEqual(foreign.validityReads, 0)
        XCTAssertEqual(foreign.buildEntries, 0)
    }

    func testDetachedAndForeignCandidatesCannotConsumeTheFirstActualAttachment() async throws {
        let fixture = StandaloneListFixture()
        let list = try fixture.list()
        let lease = try XCTUnwrap(list.retainedSubtreeBuildLease)
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertFalse(adapter.claimAttachment(to: list))
        XCTAssertFalse(adapter.ownsAttachment(list))
        XCTAssertFalse(lease.canBuild)
        XCTAssertNil(lease.beginBuild())
        XCTAssertTrue(fixture.probe.built.isEmpty)

        let foreign = RetainedViewRuntime(root: ViewNode())
        foreign.setRootSize(fixture.size)
        foreign.root.addChild(fixture.content)
        _ = foreign.renderScene(at: 0)
        XCTAssertFalse(adapter.ownsAttachment(list))
        XCTAssertFalse(lease.canBuild)
        XCTAssertTrue(fixture.probe.built.isEmpty)
        foreign.root.removeChild(fixture.content)

        fixture.attach()
        let scene = fixture.runtime.renderScene(at: 0)
        XCTAssertTrue(adapter.ownsAttachment(list))
        XCTAssertTrue(lease.canBuild)
        try RetainedListPaintAssertions.labels(
            fixture.names(), in: list, scene: scene, size: fixture.size)
    }

    private func assertRevocation(
        _ mutate: (
            StandaloneListFixture, ViewNode, RetainedLazyListRuntimeAdapter, any RetainedSubtreeBuildLease
        ) -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = StandaloneListFixture()
        fixture.attach()
        _ = fixture.runtime.renderScene(at: 0)
        let list = try fixture.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter, file: file, line: line)
        let lease = try XCTUnwrap(list.retainedSubtreeBuildLease, file: file, line: line)
        let epoch = try XCTUnwrap(lease.beginBuild(), file: file, line: line)
        XCTAssertTrue(lease.canBuild, file: file, line: line)
        XCTAssertEqual(Set(fixture.probe.built), Set(fixture.names()), file: file, line: line)
        let builds = fixture.probe.built

        mutate(fixture, list, adapter, lease)

        XCTAssertFalse(lease.canBuild, file: file, line: line)
        XCTAssertNil(lease.beginBuild(), file: file, line: line)
        XCTAssertFalse(epoch.canAdopt, file: file, line: line)
        XCTAssertFalse(epoch.canComplete, file: file, line: line)
        // A real new layout opportunity must not rearm or poll a replacement
        // lease. This is one render, not a retry loop or a recharged work budget.
        fixture.runtime.setRootSize(IntSize(width: 321, height: 240))
        _ = fixture.runtime.renderScene(at: 0)
        XCTAssertEqual(fixture.probe.built, builds, file: file, line: line)
        XCTAssertFalse(lease.canBuild, file: file, line: line)
    }
}

@MainActor
private final class StandaloneListFixture {
    let size: IntSize
    let runtime: RetainedViewRuntime
    let probe: StandaloneListProbe
    let content: ViewNode

    init() {
        let size = IntSize(width: 320, height: 240)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let probe = StandaloneListProbe()
        self.size = size
        self.runtime = runtime
        self.probe = probe
        runtime.setRootSize(size)
        content = Self.makeContent(prefix: "Before", runtime: runtime, probe: probe)
    }

    func names(prefix: String = "Before") -> [String] { (0..<4).map { "\(prefix) \($0)" } }

    func makeContent(prefix: String) -> ViewNode {
        Self.makeContent(prefix: prefix, runtime: runtime, probe: probe)
    }

    private static func makeContent(
        prefix: String, runtime: RetainedViewRuntime, probe: StandaloneListProbe
    ) -> ViewNode {
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 320, height: 240) }, invalidateHandler: {})
        return List(Array(0..<4), id: \.self) { index in
            probe.row("\(prefix) \(index)")
        }
        .listStyle(.plain)
        .frame(width: 320, height: 240)
        .makeComponent(context: context).makeNode(runtime: runtime)
    }

    func attach() { runtime.root.addChild(content) }
    func list() throws -> ViewNode { try RetainedListPaintAssertions.list(in: content) }
}

@MainActor
private final class StandaloneListProbe {
    var built: [String] = []
    func row(_ label: String) -> some View {
        built.append(label)
        return Text(label).font(.system(size: 13))
    }
}

@MainActor
private final class StandaloneForeignLease: RetainedSubtreeBuildLease {
    var validityReads = 0
    var buildEntries = 0
    var canBuild: Bool {
        validityReads += 1
        return true
    }
    func beginBuild() -> (any RetainedBuildEpoch)? {
        buildEntries += 1
        return nil
    }
}

/// Read the actual retained scene's glyph primitives for each List text leaf.
/// Model values, accessibility labels, and nonzero layout frames are insufficient.
@MainActor
enum RetainedListPaintAssertions {
    static func descendants(in root: ViewNode) -> [ViewNode] {
        var result: [ViewNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }

    static func list(in root: ViewNode, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let lists = descendants(in: root).filter { $0.retainedLazyListAdapter != nil }
        XCTAssertEqual(lists.count, 1, file: file, line: line)
        return try XCTUnwrap(lists.first, file: file, line: line)
    }

    static func labels(
        _ expected: [String], in list: ViewNode, scene: GPUIScene, size: IntSize,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertTrue(scene.validate().isEmpty, file: file, line: line)
        let nodes = descendants(in: list)
        let canvas = Rect(x: 0, y: 0, width: Double(size.width), height: Double(size.height))
        for label in expected {
            let matches = nodes.filter { $0.text == label }
            XCTAssertEqual(matches.count, 1, label, file: file, line: line)
            let text = try XCTUnwrap(matches.first, label, file: file, line: line)
            let range = try XCTUnwrap(text.cachedScenePaintRange, label, file: file, line: line)
            guard range.lowerBound >= 0, range.upperBound <= scene.paintRecords.count else {
                XCTFail("\(label): paint range does not belong to this retained scene", file: file, line: line)
                continue
            }
            let visibleGlyphs = scene.paintRecords[range].filter { record in
                guard case .primitive(let layerIndex, let kind, let index) = record,
                    case .glyph(let glyph)? = scene.primitive(kind: kind, inLayer: layerIndex, at: index),
                    glyph.colorA > 0
                else { return false }
                let cell = Rect(
                    x: Double(glyph.screenX), y: Double(glyph.screenY),
                    width: Double(glyph.screenW), height: Double(glyph.screenH))
                let clip = Rect(
                    x: Double(glyph.clipX), y: Double(glyph.clipY),
                    width: Double(glyph.clipWidth), height: Double(glyph.clipHeight))
                return cell.intersected(with: clip)?.intersected(with: canvas) != nil
            }
            XCTAssertGreaterThan(visibleGlyphs.count, 0, "\(label) must paint visible glyphs", file: file, line: line)
        }
    }
}
