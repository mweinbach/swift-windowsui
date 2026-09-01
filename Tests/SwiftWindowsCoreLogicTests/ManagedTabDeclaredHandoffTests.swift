import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ManagedTabDeclaredHandoffTests: XCTestCase {
    func testReturningAfterUnchangedInactiveBuildsPreservesOriginalOwnerAndModel() async throws {
        let fixture = ManagedTabHandoffFixture()
        defer { fixture.close() }
        XCTAssertNotNil(fixture.host.layout())
        let original = try XCTUnwrap(fixture.probe.captures[0])
        let oldNode = try XCTUnwrap(fixture.host.find(managedTabHandoffIdentifier(0, 0)))
        original.value.wrappedValue = 41
        XCTAssertNotNil(fixture.host.layout())
        try fixture.select(1)
        let inactiveBodyCalls = fixture.probe.bodyCalls[0]

        for _ in 0..<3 {
            fixture.host.reload()
            XCTAssertNotNil(fixture.host.layout())
            XCTAssertNil(fixture.host.find(managedTabHandoffIdentifier(0, 0)))
            XCTAssertEqual(fixture.probe.bodyCalls[0], inactiveBodyCalls)
            XCTAssertTrue(fixture.host.coordinator.registry.owner(at: original.owner.identity) === original.owner)
        }
        original.value.wrappedValue = 42
        XCTAssertNotNil(fixture.host.layout())
        XCTAssertEqual(fixture.probe.bodyCalls[0], inactiveBodyCalls)
        try fixture.select(0)

        let returned = try XCTUnwrap(fixture.probe.captures[0])
        XCTAssertTrue(returned.owner === original.owner)
        XCTAssertEqual(returned.owner.generation, original.owner.generation)
        XCTAssertTrue(returned.model === original.model)
        XCTAssertEqual(returned.value.wrappedValue, 42)
        XCTAssertFalse(try XCTUnwrap(fixture.host.find(managedTabHandoffIdentifier(0, 0))) === oldNode)
        XCTAssertNotNil(fixture.host.find(managedTabHandoffIdentifier(0, 1)))
        try fixture.host.assertCommittedDescriptor()
        try fixture.select(1)
        try fixture.select(0)
        XCTAssertTrue(try XCTUnwrap(fixture.probe.captures[0]).owner === original.owner)
        XCTAssertTrue(try XCTUnwrap(fixture.probe.captures[0]).model === original.model)
        XCTAssertEqual(try XCTUnwrap(fixture.probe.captures[0]).value.wrappedValue, 42)
    }

    func testIncomingControllerSeesOriginalAcceptedStateBeforeSynchronousReload() async throws {
        let fixture = ManagedTabHandoffFixture()
        defer { fixture.close() }
        XCTAssertNotNil(fixture.host.layout())
        let original = try XCTUnwrap(fixture.probe.captures[0])
        original.value.wrappedValue = 41
        XCTAssertNotNil(fixture.host.layout())
        try fixture.select(1)
        var callbackCount = 0
        fixture.probe.onAttach = { row, leaf, node in
            guard row == 0, leaf == 0 else { return }
            fixture.probe.onAttach = nil
            callbackCount += 1
            XCTAssertTrue(fixture.host.runtime.hasActiveRetainedBuild)
            XCTAssertTrue(fixture.host.contains(node))
            XCTAssertTrue(fixture.probe.captures[0]?.owner === original.owner)
            XCTAssertEqual(original.value.wrappedValue, 41)
            let invalidations = fixture.host.events.stateInvalidations
            original.value.wrappedValue = 73
            XCTAssertEqual(original.value.wrappedValue, 73)
            XCTAssertEqual(fixture.host.events.stateInvalidations, invalidations + 1)
        }

        try fixture.select(0)
        XCTAssertNotNil(fixture.host.layout())

        XCTAssertEqual(callbackCount, 1)
        let returned = try XCTUnwrap(fixture.probe.captures[0])
        XCTAssertTrue(returned.owner === original.owner)
        XCTAssertTrue(returned.model === original.model)
        XCTAssertEqual(returned.value.wrappedValue, 73)
        XCTAssertNotNil(fixture.host.find(managedTabHandoffIdentifier(0, 1)))
        try fixture.host.assertCommittedDescriptor()
    }

    func testClosingFromFirstReturningControllerCannotAttachItsLaterSiblingOrReviveState() async throws {
        let fixture = ManagedTabHandoffFixture()
        defer { fixture.close() }
        XCTAssertNotNil(fixture.host.layout())
        let original = try XCTUnwrap(fixture.probe.captures[0])
        original.value.wrappedValue = 41
        XCTAssertNotNil(fixture.host.layout())
        try fixture.select(1)
        fixture.probe.attachments.removeAll()
        var closeCount = 0
        fixture.probe.onAttach = { row, leaf, _ in
            guard row == 0, leaf == 0 else { return }
            fixture.probe.onAttach = nil
            closeCount += 1
            XCTAssertTrue(fixture.probe.captures[0]?.owner === original.owner)
            fixture.host.close()
            original.value.wrappedValue = 999
        }

        fixture.probe.selection = 0
        fixture.host.reload()
        _ = fixture.host.layout()

        XCTAssertEqual(closeCount, 1)
        XCTAssertTrue(fixture.host.isClosed)
        XCTAssertEqual(fixture.probe.attachments, [0], "The second leaf from the invalidated attachment must not run")
        XCTAssertFalse(original.owner.isLive)
        XCTAssertEqual(original.value.wrappedValue, 41)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
    }
}

@MainActor
private struct ManagedTabHandoffCapture {
    let owner: StateMountOwner
    let value: Binding<Int>
    let model: MountedLazyListModel
}

@MainActor
private final class ManagedTabHandoffProbe {
    var selection = 0
    var captures: [Int: ManagedTabHandoffCapture] = [:]
    var bodyCalls: [Int: Int] = [:]
    var attachments: [Int] = []
    var onAttach: ((Int, Int, ViewNode) -> Void)?

    func record(_ row: Int, value: Binding<Int>, model: MountedLazyListModel) {
        bodyCalls[row, default: 0] += 1
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            return XCTFail("The managed page must install its original State owner")
        }
        captures[row] = ManagedTabHandoffCapture(owner: owner, value: value, model: model)
    }
}

@MainActor
private struct ManagedTabHandoffPage: View {
    @State private var value: Int
    @StateObject private var model: MountedLazyListModel
    let row: Int
    let probe: ManagedTabHandoffProbe

    init(row: Int, probe: ManagedTabHandoffProbe) {
        self.row = row
        self.probe = probe
        _value = State(initialValue: 100 + row)
        _model = StateObject(wrappedValue: MountedLazyListModel(value: 100 + row, serial: row))
    }

    var body: some View {
        probe.record(row, value: $value, model: model)
        return VStack(spacing: 0) {
            ManagedTabHandoffLeaf(probe: probe, row: row, leaf: 0)
            ManagedTabHandoffLeaf(probe: probe, row: row, leaf: 1)
        }
        .frame(width: 80, height: 32)
    }
}

@MainActor
private struct ManagedTabHandoffLeaf: View {
    typealias Body = Never
    let probe: ManagedTabHandoffProbe
    let row: Int
    let leaf: Int
    var body: Never { fatalError("Primitive") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            let node = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 16))
            node.accessibilityIdentifier = managedTabHandoffIdentifier(row, leaf)
            node.textInputController = ManagedTabHandoffController(probe: probe, row: row, leaf: leaf)
            return node
        }
    }
}

@MainActor
private final class ManagedTabHandoffController: RetainedTextInputController {
    private weak var probe: ManagedTabHandoffProbe?
    private let row: Int
    private let leaf: Int

    init(probe: ManagedTabHandoffProbe, row: Int, leaf: Int) {
        self.probe = probe
        self.row = row
        self.leaf = leaf
    }

    func attach(to node: ViewNode) {
        probe?.attachments.append(row * 10 + leaf)
        probe?.onAttach?(row, leaf, node)
    }
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func detach(from node: ViewNode) {}
}

@MainActor
private final class ManagedTabHandoffFixture {
    let probe: ManagedTabHandoffProbe
    let host: MountedLazyListTestHost

    init() {
        let probe = ManagedTabHandoffProbe()
        self.probe = probe
        host = MountedLazyListTestHost(size: Size(width: 320, height: 160)) {
            ManagedLazyListContent(
                [0], id: \.self, estimatedExtent: 160, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1
            ) { _ in
                TabView(selection: Binding(get: { probe.selection }, set: { probe.selection = $0 })) {
                    ManagedTabHandoffPage(row: 0, probe: probe)
                        .tag(0)
                        .tabItem { Color.clear.frame(width: 16, height: 8) }
                    ManagedTabHandoffPage(row: 1, probe: probe)
                        .tag(1)
                        .tabItem { Color.clear.frame(width: 16, height: 8) }
                }
                .frame(height: 160)
            }
        }
    }

    func select(_ page: Int) throws {
        probe.selection = page
        host.reload()
        XCTAssertNotNil(host.layout())
        XCTAssertNotNil(host.find(managedTabHandoffIdentifier(page, 0)))
    }

    func close() {
        probe.onAttach = nil
        host.close()
        probe.captures.removeAll()
    }
}

private func managedTabHandoffIdentifier(_ row: Int, _ leaf: Int) -> String { "declared.tab.\(row).\(leaf)" }
