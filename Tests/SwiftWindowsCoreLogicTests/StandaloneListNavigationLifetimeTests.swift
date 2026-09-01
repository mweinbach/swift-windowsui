import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Direct public List construction has no State coordinator. These cases
/// preserve returned-tree actions while distinguishing actual native lifetime.
@MainActor
final class StandaloneListNavigationLifetimeTests: XCTestCase {
    private static let down = KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue)

    func testForeignDataListAttemptDoesNotConsumeSelectionOrKeyboardNavigation() async throws {
        for closeForeign in [false, true] {
            let fixture = StandaloneNavigationFixture(deferred: true)
            defer { fixture.close() }
            let foreign = RetainedViewRuntime(root: ViewNode())
            defer {
                foreign.stopRenderLifecycleCallbacks()
                foreign.cancelRenderLifecycleTasks()
            }
            foreign.setRootSize(StandaloneNavigationFixture.size)
            let list = try fixture.list()
            let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
            fixture.probe.reset()

            foreign.root.addChild(fixture.content)
            _ = foreign.renderScene(at: 0)
            if closeForeign { foreign.stopRenderLifecycleCallbacks() }

            XCTAssertFalse(adapter.ownsAttachment(list))
            XCTAssertEqual(fixture.probe.reads, 0)
            XCTAssertEqual(fixture.probe.writes, [])
            XCTAssertEqual(fixture.probe.invalidations, 0)
            XCTAssertEqual(fixture.probe.factories, [])
            foreign.root.removeChild(fixture.content)
            fixture.attachAndRender()

            XCTAssertTrue(adapter.ownsAttachment(list))
            try assertAcceptedSelectionAndKeyboard(in: fixture)
        }
    }

    func testForeignEagerListAttemptCannotReadOrWriteBindings() async throws {
        for closeForeign in [false, true] {
            let fixture = StandaloneNavigationFixture(deferred: false)
            defer { fixture.close() }
            let source = try fixture.row(1)
            let activate = try XCTUnwrap(source.onActivate)
            let key = try XCTUnwrap(source.onKeyDown)
            let foreign = RetainedViewRuntime(root: ViewNode())
            defer {
                foreign.stopRenderLifecycleCallbacks()
                foreign.cancelRenderLifecycleTasks()
            }
            foreign.setRootSize(StandaloneNavigationFixture.size)
            fixture.probe.reset()

            foreign.root.addChild(fixture.content)
            _ = foreign.renderScene(at: 0)
            activate()
            key(Self.down)
            if closeForeign {
                foreign.stopRenderLifecycleCallbacks()
                activate()
                key(Self.down)
            }

            assertNoBindingCalls(fixture.probe)
            foreign.root.removeChild(fixture.content)
            fixture.attachAndRender()
            try assertAcceptedSelectionAndKeyboard(in: fixture)
        }
    }

    func testPreparedConstructionActionIsCancelledWithoutConsumingTheUnacceptedOwner() async throws {
        let fixture = StandaloneNavigationFixture(deferred: false)
        defer { fixture.close() }
        let source = try fixture.row(0)
        let target = try fixture.row(1)
        let activate = try XCTUnwrap(target.onActivate)
        activate()
        XCTAssertEqual(fixture.probe.selected, 1)
        XCTAssertEqual(fixture.probe.writes, [1])
        let scope = try XCTUnwrap(try fixture.scroll().listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
        XCTAssertTrue(receipt.prepareTarget(try XCTUnwrap(target.listNavigationOwner)))
        XCTAssertTrue(receipt.permitsContinuation)
        let foreign = RetainedViewRuntime(root: ViewNode())
        defer { foreign.cancelRenderLifecycleTasks() }
        fixture.probe.reset()

        foreign.root.addChild(fixture.content)

        XCTAssertFalse(receipt.permitsContinuation)
        activate()
        XCTAssertEqual(fixture.probe.reads, 0)
        foreign.stopRenderLifecycleCallbacks()
        foreign.root.removeChild(fixture.content)
        fixture.attachAndRender()

        XCTAssertFalse(receipt.permitsContinuation)
        try assertAcceptedSelectionAndKeyboard(in: fixture)
    }

    func testUnobservedAcceptedAttachmentCannotBeRecapturedAfterDetach() async throws {
        let fixture = StandaloneNavigationFixture(deferred: false)
        defer { fixture.close() }
        let runtime = try XCTUnwrap(fixture.runtime)
        runtime.root.addChild(fixture.content)
        let source = try fixture.row(1)
        let activate = try XCTUnwrap(source.onActivate)
        let key = try XCTUnwrap(source.onKeyDown)
        // No action, receipt, or render has observed this accepted attachment.
        runtime.root.removeChild(fixture.content)
        fixture.attachAndRender()
        fixture.probe.reset()

        activate()
        key(Self.down)

        assertNoBindingCalls(fixture.probe)
        let scope = try XCTUnwrap(try fixture.scroll().listNavigationOwner)
        XCTAssertNil(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
    }

    func testDepartureRevokesBeforeCallbacksAndSameNodeReinstallation() async throws {
        for deferred in [false, true] {
            let fixture = StandaloneNavigationFixture(deferred: deferred)
            defer { fixture.close() }
            fixture.attachAndRender()
            let runtime = try XCTUnwrap(fixture.runtime)
            let source = try fixture.row(1)
            let activate = try XCTUnwrap(source.onActivate)
            let key = try XCTUnwrap(source.onKeyDown)
            let scope = try XCTUnwrap(try fixture.scroll().listNavigationOwner)
            let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
            var disappearances = 0
            source.onDisappear = {
                disappearances += 1
                XCTAssertFalse(receipt.permitsContinuation)
                activate()
                key(Self.down)
            }
            fixture.probe.reset()

            runtime.root.removeChild(fixture.content)

            XCTAssertEqual(disappearances, 1)
            assertNoBindingCalls(fixture.probe)
            source.onDisappear = nil
            fixture.attachAndRender()
            fixture.probe.reset()
            activate()
            key(Self.down)
            XCTAssertFalse(receipt.permitsContinuation)
            assertNoBindingCalls(fixture.probe)
        }
    }

    func testOwnerSlotRemovalAndReinstallationCannotReviveOldActions() async throws {
        for scopeSlot in [false, true] {
            let fixture = StandaloneNavigationFixture(deferred: false)
            defer { fixture.close() }
            fixture.attachAndRender()
            let source = try fixture.row(1)
            let activate = try XCTUnwrap(source.onActivate)
            let key = try XCTUnwrap(source.onKeyDown)
            let scope = try XCTUnwrap(try fixture.scroll().listNavigationOwner)
            let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
            let node: ViewNode
            if scopeSlot { node = try fixture.scroll() } else { node = source }
            let owner = try XCTUnwrap(node.listNavigationOwner)
            node.listNavigationOwner = owner
            XCTAssertTrue(receipt.permitsContinuation, "An identical owner assignment preserves the attachment")
            fixture.probe.reset()

            node.listNavigationOwner = nil
            node.listNavigationOwner = owner
            activate()
            key(Self.down)

            XCTAssertFalse(receipt.permitsContinuation)
            assertNoBindingCalls(fixture.probe)
        }
    }

    func testIdentityABADoesNotRefreshOldReceiptDuringFreshDeclarationAdoption() async throws {
        let fixture = StandaloneNavigationFixture(deferred: false)
        defer { fixture.close() }
        fixture.attachAndRender()
        let source = try fixture.row(1)
        let activate = try XCTUnwrap(source.onActivate)
        let key = try XCTUnwrap(source.onKeyDown)
        let scope = try XCTUnwrap(try fixture.scroll().listNavigationOwner)
        let oldOwner = try XCTUnwrap(source.listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: oldOwner))
        let identity = source.retainedViewIdentity
        source.retainedViewIdentity = identity
        XCTAssertFalse(receipt.permitsContinuation)

        ComponentHost.adopt(source: fixture.makeContent(prefix: "After"), into: fixture.content)

        XCTAssertTrue(try fixture.row(1) === source)
        XCTAssertFalse(source.listNavigationOwner === oldOwner)
        XCTAssertFalse(receipt.permitsContinuation)
        fixture.probe.reset()
        activate()
        key(Self.down)
        assertNoBindingCalls(fixture.probe)
        try assertAcceptedSelectionAndKeyboard(in: fixture)
    }

    func testOwnerRemovalPublishesBeforeCancellationInstallsANewerOwner() async throws {
        let fixture = StandaloneNavigationFixture(deferred: false)
        defer { fixture.close() }
        fixture.attachAndRender()
        let source = try fixture.row(1)
        let scope = try XCTUnwrap(try fixture.scroll().listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
        var replacement: RetainedListNavigationOwner?
        var cancellations = 0
        var deliveries = 0
        var observedPublishedRemoval = false
        XCTAssertTrue(
            receipt.schedulePreparedNavigationReplay(
                afterLayout: true,
                perform: { deliveries += 1 },
                onCancel: {
                    cancellations += 1
                    observedPublishedRemoval = source.listNavigationOwner == nil
                    XCTAssertFalse(receipt.permitsContinuation)
                    replacement = scope.makeRowOwner(on: source)
                }))
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(deliveries, 0)

        source.listNavigationOwner = nil

        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(deliveries, 0)
        XCTAssertTrue(observedPublishedRemoval)
        XCTAssertTrue(source.listNavigationOwner === replacement)
        let next = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(replacement)))
        XCTAssertTrue(next.permitsBindingWrite)
        next.cancelPreparedNavigation()
    }

    func testRawAdapterRemovalRevokesAllRowsBeforeCancellationPublishesANewerDeclaration() async throws {
        let fixture = StandaloneNavigationFixture(deferred: true)
        defer { fixture.close() }
        fixture.attachAndRender()
        let list = try fixture.list()
        let source = try fixture.row(1)
        let otherActivate = try XCTUnwrap(try fixture.row(0).onActivate)
        let scope = try XCTUnwrap(try fixture.scroll().listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
        let replacementRoot = fixture.makeContent(prefix: "After")
        let replacementList = try RetainedListPaintAssertions.list(in: replacementRoot)
        let replacementAdapter = try XCTUnwrap(replacementList.retainedLazyListAdapter)
        let replacementLease = try XCTUnwrap(replacementList.retainedSubtreeBuildLease)
        var cancellations = 0
        var deliveries = 0
        var observedPublishedRemoval = false
        fixture.probe.reset()
        XCTAssertTrue(
            receipt.schedulePreparedNavigationReplay(
                afterLayout: true,
                perform: { deliveries += 1 },
                onCancel: {
                    cancellations += 1
                    observedPublishedRemoval = list.retainedLazyListAdapter == nil
                    XCTAssertFalse(receipt.permitsContinuation)
                    otherActivate()
                    XCTAssertEqual(fixture.probe.reads, 0)
                    XCTAssertEqual(fixture.probe.writes, [])
                    ComponentHost.adopt(source: replacementRoot, into: fixture.content)
                }))
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(deliveries, 0)

        list.retainedLazyListAdapter = nil

        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(deliveries, 0)
        XCTAssertTrue(observedPublishedRemoval)
        XCTAssertTrue(list.retainedLazyListAdapter === replacementAdapter)
        XCTAssertTrue(list.retainedSubtreeBuildLease === replacementLease)
        XCTAssertTrue(replacementAdapter.ownsAttachment(list))
        XCTAssertTrue(replacementLease.canBuild)
        XCTAssertFalse(receipt.permitsContinuation)
    }

    func testLeaseAndAdapterABARemainRevokedAfterPlainRuntimeExpiry() async throws {
        for mutation in ["lease", "adapter", "claim"] {
            let fixture = StandaloneNavigationFixture(deferred: true)
            fixture.attachAndRender()
            let list = try fixture.list()
            let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
            let lease = try XCTUnwrap(list.retainedSubtreeBuildLease)
            let source = try fixture.row(1)
            let activate = try XCTUnwrap(source.onActivate)
            let key = try XCTUnwrap(source.onKeyDown)
            let scope = try XCTUnwrap(try fixture.scroll().listNavigationOwner)
            let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
            switch mutation {
            case "lease":
                list.retainedSubtreeBuildLease = nil
                list.retainedSubtreeBuildLease = lease
            case "adapter":
                list.retainedLazyListAdapter = nil
                list.retainedLazyListAdapter = adapter
            default:
                XCTAssertTrue(adapter.releaseAttachment(from: list))
                XCTAssertFalse(adapter.claimAttachment(to: list))
            }
            fixture.probe.reset()
            activate()
            key(Self.down)
            XCTAssertFalse(receipt.permitsContinuation)
            assertNoBindingCalls(fixture.probe)
            weak var expired = fixture.runtime

            fixture.runtime = nil

            XCTAssertNil(expired)
            XCTAssertFalse(lease.canBuild)
            activate()
            key(Self.down)
            assertNoBindingCalls(fixture.probe)
        }
    }

    func testExplicitCloseRemainsTerminalAfterOriginalRuntimeExpiry() async throws {
        for state in ["unmounted", "eager", "deferred"] {
            let fixture = StandaloneNavigationFixture(deferred: state == "deferred")
            if state != "unmounted" { fixture.attachAndRender() }
            let source = try fixture.row(1)
            let activate = try XCTUnwrap(source.onActivate)
            let key = try XCTUnwrap(source.onKeyDown)
            weak var expired = fixture.runtime
            fixture.close()
            fixture.runtime = nil
            fixture.probe.reset()

            XCTAssertNil(expired)
            activate()
            key(Self.down)

            assertNoBindingCalls(fixture.probe)
        }
    }

    func testPlainRuntimeExpiryPreservesPhysicalRowsWithoutRetainingLogicalHostLifetime() async throws {
        for deferred in [false, true] {
            let fixture = StandaloneNavigationFixture(deferred: deferred)
            fixture.attachAndRender()
            let source = try fixture.row(1)
            weak var expiredRuntime = fixture.runtime
            weak var expiredLogicalHost = fixture.runtime?.lazyListLogicalHostLifetime
            fixture.runtime = nil
            fixture.probe.reset()

            XCTAssertNil(expiredRuntime)
            XCTAssertNil(expiredLogicalHost, "The close witness must not keep descriptor scopes alive")
            source.onActivate?()
            source.onKeyDown?(Self.down)

            XCTAssertEqual(fixture.probe.selected, 2)
            XCTAssertEqual(fixture.probe.writes, [1, 2])
            XCTAssertEqual(fixture.probe.invalidations, 2)
            if deferred { XCTAssertFalse(try XCTUnwrap(try fixture.list().retainedSubtreeBuildLease).canBuild) }
        }
    }

    func testDifferentExpiredOriginalRuntimesCannotShareAConstructionReceipt() async throws {
        let first = StandaloneNavigationFixture(deferred: false)
        let second = StandaloneNavigationFixture(deferred: false)
        weak var expiredFirst = first.runtime
        weak var expiredSecond = second.runtime
        first.runtime = nil
        second.runtime = nil
        XCTAssertNil(expiredFirst)
        XCTAssertNil(expiredSecond)
        let source = try first.row(1)
        let oldActivate = try XCTUnwrap(source.onActivate)
        let scope = try XCTUnwrap(try first.scroll().listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
        XCTAssertTrue(receipt.permitsContinuation)

        ComponentHost.adopt(source: second.content, into: first.content)

        XCTAssertFalse(receipt.permitsContinuation)
        first.probe.reset()
        second.probe.reset()
        oldActivate()
        assertNoBindingCalls(first.probe)
        try first.row(1).onActivate?()
        XCTAssertEqual(second.probe.selected, 1)
        XCTAssertEqual(second.probe.writes, [1])
    }

    func testSameNodeDeclarationTransportPreservesPreparedReceiptAndRetiresOldCallbacks() async throws {
        let fixture = StandaloneNavigationFixture(deferred: false)
        defer { fixture.close() }
        fixture.attachAndRender()
        let source = try fixture.row(0)
        let target = try fixture.row(1)
        let oldKey = try XCTUnwrap(source.onKeyDown)
        let scope = try XCTUnwrap(try fixture.scroll().listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
        XCTAssertTrue(receipt.prepareTarget(try XCTUnwrap(target.listNavigationOwner)))

        ComponentHost.adopt(source: fixture.makeContent(prefix: "After"), into: fixture.content)

        XCTAssertTrue(try fixture.row(0) === source)
        XCTAssertTrue(try fixture.row(1) === target)
        XCTAssertTrue(receipt.permitsContinuation)
        XCTAssertFalse(receipt.permitsBindingWrite)
        fixture.probe.reset()
        oldKey(Self.down)
        assertNoBindingCalls(fixture.probe)
        receipt.cancelPreparedNavigation()
        try assertAcceptedSelectionAndKeyboard(in: fixture)
    }

    private func assertAcceptedSelectionAndKeyboard(
        in fixture: StandaloneNavigationFixture, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let runtime = try XCTUnwrap(fixture.runtime, file: file, line: line)
        let source = try fixture.row(0)
        let target = try fixture.row(1)
        fixture.probe.reset()
        try XCTUnwrap(target.onActivate, file: file, line: line)()
        XCTAssertEqual(fixture.probe.selected, 1, file: file, line: line)
        XCTAssertEqual(fixture.probe.writes, [1], file: file, line: line)
        XCTAssertEqual(fixture.probe.invalidations, 1, file: file, line: line)
        fixture.probe.reset()
        runtime.requestFocus(source)

        runtime.keyDown(Self.down)

        XCTAssertEqual(fixture.probe.selected, 1, file: file, line: line)
        XCTAssertEqual(fixture.probe.writes, [1], file: file, line: line)
        XCTAssertEqual(fixture.probe.invalidations, 1, file: file, line: line)
        XCTAssertTrue(runtime.focusedNode === target, file: file, line: line)
    }

    private func assertNoBindingCalls(
        _ probe: StandaloneNavigationProbe, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(probe.reads, 0, file: file, line: line)
        XCTAssertEqual(probe.writes, [], file: file, line: line)
        XCTAssertEqual(probe.invalidations, 0, file: file, line: line)
    }
}

@MainActor
private final class StandaloneNavigationProbe {
    var selected: Int? = 0
    var reads = 0
    var writes: [Int?] = []
    var invalidations = 0
    var factories: [Int] = []

    var binding: Binding<Int?> {
        Binding(
            get: {
                self.reads += 1
                return self.selected
            },
            set: {
                self.selected = $0
                self.writes.append($0)
            })
    }

    func reset() {
        selected = 0
        reads = 0
        writes = []
        invalidations = 0
    }

    func row(_ index: Int, prefix: String) -> some View {
        factories.append(index)
        return Text("\(prefix) \(index)")
            .frame(height: 32)
            .accessibilityIdentifier("standalone-navigation-\(index)")
            .tag(index)
    }
}

@MainActor
private final class StandaloneNavigationFixture {
    static let size = IntSize(width: 260, height: 240)
    var runtime: RetainedViewRuntime?
    let probe: StandaloneNavigationProbe
    let content: ViewNode
    private let deferred: Bool

    init(deferred: Bool) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let probe = StandaloneNavigationProbe()
        runtime.clock = { 0 }
        runtime.setRootSize(Self.size)
        self.runtime = runtime
        self.probe = probe
        self.deferred = deferred
        content = Self.makeContent(runtime: runtime, probe: probe, deferred: deferred, prefix: "Before")
    }

    func makeContent(prefix: String) -> ViewNode {
        Self.makeContent(runtime: runtime!, probe: probe, deferred: deferred, prefix: prefix)
    }

    private static func makeContent(
        runtime: RetainedViewRuntime, probe: StandaloneNavigationProbe, deferred: Bool, prefix: String
    ) -> ViewNode {
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 260, height: 240) },
            invalidateHandler: { probe.invalidations += 1 })
        let list: List
        if deferred {
            list = List(Array(0..<4), id: \.self, selection: probe.binding) { index in
                probe.row(index, prefix: prefix)
            }
        } else {
            let rows = (0..<4).map { AnyView(probe.row($0, prefix: prefix)) }
            list = List(selection: probe.binding) { rows }
        }
        return list.listStyle(.plain).frame(width: 260, height: 240)
            .makeComponent(context: context).makeNode(runtime: runtime)
    }

    func attachAndRender() {
        runtime!.root.addChild(content)
        _ = runtime!.renderScene(at: 0)
    }

    func close() {
        runtime?.stopRenderLifecycleCallbacks()
        runtime?.cancelRenderLifecycleTasks()
    }

    func row(_ index: Int) throws -> ViewNode {
        try XCTUnwrap(
            Self.nodes(in: content).first { node in
                node.listNavigationOwner != nil && node.accessibilityTraits.contains(.isSelectable)
                    && Self.nodes(in: node).contains { $0.accessibilityIdentifier == "standalone-navigation-\(index)" }
            })
    }

    func scroll() throws -> ViewNode {
        try XCTUnwrap(Self.nodes(in: content).first { $0.listNavigationOwner != nil && $0.scrollAxis == .vertical })
    }

    func list() throws -> ViewNode {
        try XCTUnwrap(Self.nodes(in: content).first { $0.retainedLazyListAdapter != nil })
    }

    private static func nodes(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { nodes(in: $0) }
    }
}
