import XCTest

@testable import SwiftWindowsUI

/// Native claim-publication fixtures. These do not render, build rows, or
/// establish public keyboard behavior; the public transport class covers that.
@MainActor
final class RetainedLazyListNavigationContainerTests: XCTestCase {
    func testProvisionalClaimNeedsActualOriginalMembershipBeforePublishing() async throws {
        let fixture = try NavigationContainerFixture()
        defer { fixture.close() }
        XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
        XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.node))
        XCTAssertNil(fixture.binding.node)
        XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
        XCTAssertNil(fixture.binding.node, "Repeated provisional claims and getters grant nothing")

        try fixture.attach()

        XCTAssertTrue(fixture.binding.node === fixture.node)
        fixture.node.retainedLazyListAdapter = fixture.adapter
        XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
        XCTAssertTrue(fixture.binding.node === fixture.node)
        XCTAssertEqual(fixture.probe.factoryCalls, 0)
    }

    func testForeignClaimAndReleaseCannotConsumeFirstOriginalPublication() async throws {
        let fixture = try NavigationContainerFixture()
        defer { fixture.close() }
        let foreign = RetainedViewRuntime(root: ViewNode())
        defer {
            foreign.stopRenderLifecycleCallbacks()
            foreign.cancelRenderLifecycleTasks()
        }
        foreign.root.addChild(fixture.node)
        XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.node))
        XCTAssertNil(fixture.binding.node)
        XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
        XCTAssertNil(fixture.binding.node)

        foreign.root.removeChild(fixture.node)
        foreign.stopRenderLifecycleCallbacks()
        try fixture.attach()

        XCTAssertTrue(fixture.binding.node === fixture.node)
        XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.node))
        XCTAssertEqual(fixture.probe.factoryCalls, 0)
    }

    func testAcceptedReleaseIsTerminalEvenWhenRawAdapterReclaimsSameNode() async throws {
        let fixture = try NavigationContainerFixture()
        defer { fixture.close() }
        try fixture.attach()
        XCTAssertTrue(fixture.binding.node === fixture.node)
        let foreign = ViewNode()
        XCTAssertFalse(fixture.adapter.releaseAttachment(from: foreign))
        XCTAssertTrue(fixture.binding.node === fixture.node)

        XCTAssertTrue(fixture.adapter.releaseAttachment(from: fixture.node))
        XCTAssertNil(fixture.binding.node)
        XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
        XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.node))
        XCTAssertNil(fixture.binding.node, "The raw claim can recover, but its original binding cannot")
        XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
        XCTAssertNil(fixture.binding.node)
        XCTAssertNil(fixture.adapter.installNavigationContainer(in: try XCTUnwrap(fixture.runtime)))
        XCTAssertEqual(fixture.probe.factoryCalls, 0)
    }

    func testAdapterSlotRemovalCannotRestoreItsOriginalBinding() async throws {
        let fixture = try NavigationContainerFixture()
        defer { fixture.close() }
        try fixture.attach()
        XCTAssertTrue(fixture.binding.node === fixture.node)

        fixture.node.retainedLazyListAdapter = nil
        fixture.node.retainedLazyListAdapter = fixture.adapter

        XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.node))
        XCTAssertNil(fixture.binding.node)
        XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
        XCTAssertNil(fixture.binding.node)
        XCTAssertEqual(fixture.probe.factoryCalls, 0)
    }

    func testIdentityReassignmentCannotRefreshBindingDuringRepeatedClaim() async throws {
        let fixture = try NavigationContainerFixture()
        defer { fixture.close() }
        try fixture.attach()
        XCTAssertTrue(fixture.binding.node === fixture.node)
        let identity = fixture.node.retainedViewIdentity

        fixture.node.retainedViewIdentity = identity

        XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.node))
        XCTAssertNil(fixture.binding.node)
        XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
        XCTAssertNil(fixture.binding.node, "Claim publication must not replace an expired original proof")
        XCTAssertEqual(fixture.probe.factoryCalls, 0)
    }

    func testPlainRuntimeExpiryKeepsOnlyTheOriginalPhysicalAttachment() async throws {
        let fixture = try NavigationContainerFixture()
        try fixture.attach()
        weak var observedRuntime = fixture.runtime
        weak var observedLogicalHost = fixture.runtime?.lazyListLogicalHostLifetime
        XCTAssertTrue(fixture.binding.node === fixture.node)

        fixture.runtime = nil

        XCTAssertNil(observedRuntime)
        XCTAssertNil(observedLogicalHost)
        XCTAssertTrue(fixture.binding.node === fixture.node)
        var foreign: RetainedViewRuntime? = RetainedViewRuntime(root: ViewNode())
        weak var observedForeign = foreign
        try XCTUnwrap(foreign).root.addChild(fixture.node)
        XCTAssertNil(fixture.binding.node)
        foreign = nil
        XCTAssertNil(observedForeign)
        XCTAssertNil(fixture.binding.node, "Two expired runtimes cannot make the original proof current again")
        XCTAssertEqual(fixture.probe.factoryCalls, 0)
    }

    func testExpiredOriginalRuntimeCannotCaptureFirstAttachmentInAnotherHost() async throws {
        let fixture = try NavigationContainerFixture()
        weak var observedRuntime = fixture.runtime
        weak var observedLogicalHost = fixture.runtime?.lazyListLogicalHostLifetime
        fixture.runtime = nil
        XCTAssertNil(observedRuntime)
        XCTAssertNil(observedLogicalHost)
        XCTAssertNil(fixture.binding.node)
        let foreign = RetainedViewRuntime(root: ViewNode())
        defer {
            foreign.stopRenderLifecycleCallbacks()
            foreign.cancelRenderLifecycleTasks()
        }

        foreign.root.addChild(fixture.node)

        XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.node))
        XCTAssertNil(fixture.binding.node)
        XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
        XCTAssertNil(fixture.binding.node)
        XCTAssertEqual(fixture.probe.factoryCalls, 0)
    }

    func testExplicitCloseBeforeOrAfterCaptureRemainsTerminalAfterExpiry() async throws {
        for wasAttached in [false, true] {
            let fixture = try NavigationContainerFixture()
            if wasAttached {
                try fixture.attach()
                XCTAssertTrue(fixture.binding.node === fixture.node)
            }
            weak var observedRuntime = fixture.runtime
            weak var observedLogicalHost = fixture.runtime?.lazyListLogicalHostLifetime

            fixture.close()
            fixture.runtime = nil

            XCTAssertNil(observedRuntime)
            XCTAssertNil(observedLogicalHost)
            XCTAssertNil(fixture.binding.node)
            XCTAssertTrue(fixture.adapter.claimAttachment(to: fixture.node))
            XCTAssertNil(fixture.binding.node)
            XCTAssertEqual(fixture.probe.factoryCalls, 0)
        }
    }
}

@MainActor
private final class NavigationContainerProbe {
    var factoryCalls = 0
}

@MainActor
private final class NavigationContainerFixture {
    var runtime: RetainedViewRuntime?
    let node = ViewNode()
    let probe: NavigationContainerProbe
    let adapter: RetainedLazyListRuntimeAdapter
    let binding: RetainedLazyListNavigationContainer

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let probe = NavigationContainerProbe()
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { _ in
                probe.factoryCalls += 1
                return [ViewNode()]
            })
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 8, maximumProtectedRecords: 1))
        let binding = try XCTUnwrap(adapter.installNavigationContainer(in: runtime))
        self.runtime = runtime
        self.probe = probe
        self.adapter = adapter
        self.binding = binding
        node.retainedLazyListAdapter = adapter
    }

    func attach() throws {
        try XCTUnwrap(runtime).root.addChild(node)
    }

    func close() {
        runtime?.stopRenderLifecycleCallbacks()
        runtime?.cancelRenderLifecycleTasks()
    }
}
