import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class LazyListUIAReaderButtonConstructionTests: XCTestCase {
    func testPendingRawReaderButtonActivatesOnlyAfterOriginalPreparationCleanup() async throws {
        let probe = UIAReaderButtonProbe(mode: .accepted, slot: 70)
        let reader = probe.makeReader()
        let fixture = try UIAReaderButtonFixture(beforeList: [reader])
        defer { fixture.close() }
        let factories = fixture.factories.values
        XCTAssertEqual(probe.builds, 0)

        try withPreparation(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            let request = try XCTUnwrap(
                fixture.runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { fixture.runtime.finishLazyListUIARequest(request) }

            let button = try XCTUnwrap(probe.primaryButton)
            XCTAssertEqual(probe.builds, 1)
            XCTAssertEqual(probe.bodyAttempts, 2)
            XCTAssertTrue(probe.sawConstructionFrame)
            XCTAssertEqual(probe.pendingDuringBody, [true])
            XCTAssertTrue(probe.actions.isEmpty)
            XCTAssertTrue(button.parent === reader)
            XCTAssertTrue(button.retainedLazyListRuntime === fixture.runtime)
            XCTAssertTrue(reader.children.contains { $0 === button })
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 20))
            XCTAssertFalse(try XCTUnwrap(button.buttonActionOwner).isRetired)
            XCTAssertEqual(request.item.token, witness.token)
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(request.item))
            XCTAssertNil(fixture.runtime.buttonActionConstruction)
            try assertSettled(fixture.runtime)
        }

        let accepted = try XCTUnwrap(probe.primaryButton)
        XCTAssertTrue(accepted.parent === reader)
        XCTAssertNil(fixture.runtime.buttonActionConstruction)
        accepted.onActivate?()
        XCTAssertEqual(probe.actions, ["accepted"])
        XCTAssertEqual(fixture.factories.values, factories)
        XCTAssertFalse(fixture.factories.values.contains(300))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 32)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 16)
    }

    func testRejectedRawReaderButtonReleasesItsActionWhileItsNodeRemainsAlive() async throws {
        for mode in [UIAReaderButtonMode.empty, .revoked] {
            let probe = UIAReaderButtonProbe(mode: mode, slot: 70)
            let laterProbe = UIAReaderButtonProbe(mode: .accepted, slot: 71)
            let reader = probe.makeReader()
            let later = laterProbe.makeReader()
            let fixture = try UIAReaderButtonFixture(beforeList: [reader, later])
            defer { fixture.close() }
            let runtime = fixture.runtime
            let factories = fixture.factories.values
            XCTAssertEqual(probe.builds, 0)
            XCTAssertEqual(laterProbe.builds, 0)

            try withPreparation(in: fixture) { witness, mutation in
                if mode == .revoked {
                    probe.beforeReturn = { [weak runtime] in runtime?.endAccessibilityMutation(mutation) }
                }
                defer { probe.beforeReturn = nil }
                reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
                later.geometryReaderBuiltSize = Size(width: 120, height: 10)
                let request = runtime.prepareLazyListUIARequest(
                    token: witness.token, in: witness, during: mutation)
                if let request { runtime.finishLazyListUIARequest(request) }

                XCTAssertNil(request)
                XCTAssertEqual(probe.builds, 1)
                XCTAssertEqual(laterProbe.builds, 0)
                XCTAssertEqual(probe.pendingDuringBody, [true])
                XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
                XCTAssertTrue(reader.children.isEmpty)
                XCTAssertEqual(probe.releases, 1)
                XCTAssertNil(probe.actionCapture, "Keeping a rejected Button must not keep its action capture")
                XCTAssertEqual(probe.retiredAtRelease, true)
                XCTAssertEqual(probe.constructionAtRelease, true)
                XCTAssertTrue(probe.actions.isEmpty)
                XCTAssertNil(runtime.buttonActionConstruction)
                XCTAssertFalse(runtime.hasActiveRetainedBuild)
                XCTAssertEqual(fixture.factories.values, factories)
                XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            }

            let rejected = try XCTUnwrap(probe.escapedButton)
            XCTAssertTrue(try XCTUnwrap(rejected.buttonActionOwner).isRetired)
            // A later ordinary attachment cannot publish a rejected action.
            runtime.root.addChild(rejected)
            rejected.onActivate?()
            rejected.onRepeatActivate?()
            probe.savedActivation?()
            XCTAssertTrue(probe.actions.isEmpty)
            XCTAssertEqual(probe.releases, 1)
            XCTAssertNil(probe.actionCapture)
            XCTAssertFalse(fixture.factories.values.contains(300))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertEqual(runtime.lastLazyListConsumedElements, 1)
            XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
        }
    }

    func testUnreturnedButtonReleaseAfterAcceptedReaderStopsTheOriginalUIAContinuation() async throws {
        let probe = UIAReaderButtonProbe(mode: .acceptedWithRejectedButton, slot: 70)
        let laterProbe = UIAReaderButtonProbe(mode: .accepted, slot: 71)
        let reader = probe.makeReader()
        let later = laterProbe.makeReader()
        let fixture = try UIAReaderButtonFixture(beforeList: [reader, later])
        defer { fixture.close() }
        let runtime = fixture.runtime
        let factories = fixture.factories.values
        var mutationEnds = 0

        try withPreparation(in: fixture) { witness, mutation in
            probe.onActionCaptureRelease = { [weak runtime] in
                mutationEnds += 1
                runtime?.endAccessibilityMutation(mutation)
            }
            defer { probe.onActionCaptureRelease = nil }
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            later.geometryReaderBuiltSize = Size(width: 120, height: 10)
            let request = runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation)
            if let request { runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(probe.builds, 1)
            XCTAssertEqual(probe.bodyAttempts, 4)
            XCTAssertEqual(probe.pendingDuringBody, [true, true])
            XCTAssertEqual(probe.releases, 1)
            XCTAssertEqual(mutationEnds, 1)
            XCTAssertNil(probe.actionCapture)
            XCTAssertEqual(probe.retiredAtRelease, true)
            XCTAssertEqual(probe.constructionAtRelease, true)
            XCTAssertEqual(probe.primaryWasAttachedAtRelease, true)
            // The body returned nonempty output and its Button was adopted.
            // Only the unreturned Button's capture ends the mutation; an
            // empty-body failure must not conceal the release-order check.
            let accepted = try XCTUnwrap(probe.primaryButton)
            XCTAssertTrue(accepted.parent === reader)
            XCTAssertTrue(accepted.retainedLazyListRuntime === runtime)
            XCTAssertTrue(reader.children.contains { $0 === accepted })
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 20))
            XCTAssertFalse(try XCTUnwrap(accepted.buttonActionOwner).isRetired)
            XCTAssertEqual(laterProbe.builds, 0)
            XCTAssertEqual(later.geometryReaderBuiltSize, Size(width: 120, height: 10))
            XCTAssertTrue(probe.actions.isEmpty)
            XCTAssertNil(runtime.buttonActionConstruction)
            XCTAssertFalse(runtime.hasActiveRetainedBuild)
            XCTAssertEqual(fixture.factories.values, factories)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }

        let accepted = try XCTUnwrap(probe.primaryButton)
        let rejected = try XCTUnwrap(probe.escapedButton)
        accepted.onActivate?()
        rejected.onActivate?()
        probe.savedActivation?()
        XCTAssertEqual(probe.actions, ["accepted"], "Revocation must not roll back the already accepted Button")
        XCTAssertFalse(fixture.factories.values.contains(300))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 1)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
    }

    private func withPreparation(
        in fixture: UIAReaderButtonFixture,
        _ body: @MainActor (RetainedLazyListAccessibilityItem, RetainedAccessibilityMutation) throws -> Void
    ) throws {
        let witness = try fixture.target()
        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation())
        defer { fixture.runtime.endAccessibilityMutation(mutation) }
        try fixture.runtime.withLazyListResolutionBudget { try body(witness, mutation) }
    }

    private func assertSettled(_ runtime: RetainedViewRuntime) throws {
        var receipt: RetainedLayoutSettlementReceipt?
        if case .settled(let current) = runtime.layoutSettlementStatus { receipt = current }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try XCTUnwrap(receipt)))
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint)
    }
}

private enum UIAReaderButtonMode: Equatable {
    case accepted
    case empty
    case revoked
    case acceptedWithRejectedButton
}

@MainActor
private final class UIAReaderButtonProbe {
    let mode: UIAReaderButtonMode
    let identity: RetainedViewIdentity
    weak var originalReader: ViewNode?
    weak var runtime: RetainedViewRuntime?
    weak var actionCapture: UIAReaderButtonActionCapture?
    var primaryButton: ViewNode?
    var escapedButton: ViewNode?
    var savedActivation: (() -> Void)?
    var beforeReturn: (@MainActor () -> Void)?
    var onActionCaptureRelease: (@MainActor () -> Void)?
    var builds = 0
    var bodyAttempts = 0
    var actions: [String] = []
    var pendingDuringBody: [Bool] = []
    var sawConstructionFrame = false
    var releases = 0
    var retiredAtRelease: Bool?
    var constructionAtRelease: Bool?
    var primaryWasAttachedAtRelease: Bool?

    init(mode: UIAReaderButtonMode, slot: Int) {
        self.mode = mode
        identity = RetainedViewIdentity(segments: [.role(.content), .slot(slot)])
    }

    func makeReader() -> ViewNode {
        let reader = ViewNode(preferredSize: Size(width: 120, height: 20))
        reader.retainedViewIdentity = identity
        install(on: reader, builtSize: Size(width: 120, height: 20))
        originalReader = reader
        return reader
    }

    private func install(on node: ViewNode, builtSize: Size) {
        node.geometryReaderBuiltSize = builtSize
        node.geometryReaderBuild = { [self] runtime, slot in
            self.runtime = runtime
            builds += 1
            sawConstructionFrame = runtime.buttonActionConstruction != nil
            let candidate = ViewNode(preferredSize: Size(width: 120, height: 20))
            candidate.retainedViewIdentity = identity
            install(on: candidate, builtSize: slot)
            let primary: ViewNode
            if mode == .empty || mode == .revoked {
                primary = makeEscapedButton(in: runtime)
            } else {
                primary = makeButton(in: runtime) { [weak self] in self?.actions.append("accepted") }
            }
            primaryButton = primary
            candidate.setChildren([primary])
            attemptDuringBody(primary)
            if mode == .acceptedWithRejectedButton {
                let unreturned = makeEscapedButton(in: runtime)
                attemptDuringBody(unreturned)
            }
            beforeReturn?()
            return mode == .empty ? [] : [candidate]
        }
    }

    private func attemptDuringBody(_ button: ViewNode) {
        pendingDuringBody.append(button.buttonActionOwner?.isPending == true)
        bodyAttempts += 2
        button.onActivate?()
        button.onRepeatActivate?()
    }

    @inline(never)
    private func makeEscapedButton(in runtime: RetainedViewRuntime) -> ViewNode {
        let capture = UIAReaderButtonActionCapture { [weak self] in self?.recordRelease() }
        actionCapture = capture
        let button = makeButton(in: runtime) { [weak self, capture] in
            withExtendedLifetime(capture) { self?.actions.append("rejected") }
        }
        escapedButton = button
        savedActivation = button.onActivate
        return button
    }

    private func makeButton(in runtime: RetainedViewRuntime, action: @escaping () -> Void) -> ViewNode {
        Controls.button(
            runtime: runtime, frame: Rect(x: 0, y: 0, width: 80, height: 16), cornerRadius: 4,
            palette: SurfacePalette(idle: .gray, focused: .blue, pressed: .black), action: action)
    }

    private func recordRelease() {
        releases += 1
        retiredAtRelease = escapedButton?.buttonActionOwner?.isRetired
        constructionAtRelease = runtime?.buttonActionConstruction != nil
        if let primaryButton, let originalReader, let runtime {
            primaryWasAttachedAtRelease =
                primaryButton.parent === originalReader
                && primaryButton.retainedLazyListRuntime === runtime
        } else {
            primaryWasAttachedAtRelease = false
        }
        escapedButton?.onActivate?()
        savedActivation?()
        onActionCaptureRelease?()
    }
}

@MainActor
private final class UIAReaderButtonActionCapture {
    let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

@MainActor
private final class UIAReaderButtonFixture {
    let factories = UIAReaderButtonFactories()
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let list: ViewNode
    let scroll: ViewNode
    let runtime: RetainedViewRuntime

    init(beforeList: [ViewNode]) throws {
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        let factories = factories
        let factory: @MainActor @Sendable (Int, RetainedViewIdentity) -> [ViewNode] = { id, prefix in
            factories.values.append(id)
            let row = ViewNode(preferredSize: Size(width: 120, height: 20))
            row.retainedViewIdentity = prefix.appending(.slot(0)).appending(.role(.row))
            row.dynamicContentIndex = id
            return [row]
        }
        XCTAssertTrue(source.replaceData(Array(0..<1000), id: \.self, identityRoot: identity, rowContent: factory))
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 16, maximumMountedLeaves: 32, maximumProtectedRecords: 2))
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        list.retainedViewIdentity = identity
        list.retainedLazyListAdapter = adapter
        list.retainedSubtreeBuildLease = UIAReaderButtonBuildLease()
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 60), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)),
            scrollAxis: .vertical, children: beforeList + [list])
        let runtime = RetainedViewRuntime(root: scroll)
        runtime.clock = { 0 }
        self.source = source
        self.list = list
        self.scroll = scroll
        self.runtime = runtime
        // Match the existing raw UIA controls' explicit allowance. Production
        // defaults and every existing budget assertion remain unchanged.
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 16))
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: scroll))
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint)
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertFalse(factories.values.contains(300))
    }

    func target() throws -> RetainedLazyListAccessibilityItem {
        let token = try XCTUnwrap(source.token(for: .init(300)))
        return try XCTUnwrap(runtime.lazyListTarget(in: list, token: token))
    }

    func close() {
        runtime.stopRenderLifecycleCallbacks()
        source.close()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private final class UIAReaderButtonFactories {
    var values: [Int] = []
}

@MainActor
private final class UIAReaderButtonBuildLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { UIAReaderButtonBuildEpoch() }
}

@MainActor
private final class UIAReaderButtonBuildEpoch: RetainedBuildEpoch {
    private var prepared = false
    private var wasSuperseded = false
    var canAdopt: Bool { !prepared && !wasSuperseded }
    func supersede() { if !prepared { wasSuperseded = true } }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}
