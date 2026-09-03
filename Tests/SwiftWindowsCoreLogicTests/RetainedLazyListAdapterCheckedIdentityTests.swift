import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Exercise identity validation through the adapter's concrete build admission.
/// These tests do not adopt, lay out, or present the prepared children.
@MainActor
final class RetainedLazyListAdapterCheckedIdentityTests: XCTestCase {
    func testDistinctScalarTypedAndDifferentLengthIdentitiesKeepCandidateOrder() async throws {
        let pairs: [[[RetainedViewIdentity.Segment]]] = [
            [[.slot(0)], [.slot(1)]],
            [[.slot(0)], [.slot(0), .branch(true)]],
            [[.slot(0), .keyed(.init(Int8(7)))], [.slot(0), .keyed(.init(Int64(7)))]],
            [[.slot(0), .keyed(.init(7))], [.slot(0), .explicit(.init(7))]],
        ]
        for paths in pairs {
            let fixture = try AdapterCheckedIdentityFixture { prefix in
                paths.enumerated().map { index, path in
                    let node = ViewNode()
                    node.nodeTag = String(index)
                    node.retainedViewIdentity = prefix.appending(contentsOf: path)
                    return node
                }
            }
            defer { fixture.finish() }

            guard case .ready(let candidate) = fixture.prepare() else {
                return XCTFail("Distinct identities must remain eligible for a bounded candidate")
            }

            XCTAssertEqual(candidate.children.map(\.nodeTag), ["0", "1"])
            XCTAssertEqual(candidate.recordLeafCounts, [2])
            assertUnpublished(fixture)
        }
    }

    func testEqualScalarAndNestedIdentitiesRemainUnsupported() async throws {
        for wrapper in AdapterCheckedIdentityWrapper.allCases {
            let events = AdapterCheckedIdentityEvents()
            let fixture = try AdapterCheckedIdentityFixture { prefix in
                (0..<2).map { _ in
                    let node = ViewNode()
                    node.retainedViewIdentity = prefix.appending(contentsOf: [
                        .slot(0), .keyed(self.nestedKey(wrapper, events: events)),
                        .explicit(.init(AdapterCheckedIdentityKey(value: 3, events: events))),
                    ])
                    return node
                }
            }
            defer { fixture.finish() }

            guard case .unsupported = fixture.prepare() else {
                return XCTFail("Equal nested identities must not produce a candidate: \(wrapper)")
            }

            XCTAssertEqual(events.callbacks, ["equal:1:1", "equal:2:2", "equal:3:3"])
            assertUnpublished(fixture)
        }
        let fixture = try AdapterCheckedIdentityFixture { prefix in
            (0..<2).map { _ in self.node(prefix.appending(.slot(0))) }
        }
        defer { fixture.finish() }
        guard case .unsupported = fixture.prepare() else {
            return XCTFail("Equal scalar identities must not produce a candidate")
        }
        assertUnpublished(fixture)
    }

    func testMissingWrongExactAndAuthoredOnlySuffixesRemainUnsupported() async throws {
        for shape in 0..<4 {
            let fixture = try AdapterCheckedIdentityFixture { prefix in
                let identity: RetainedViewIdentity?
                switch shape {
                case 0:
                    identity = nil
                case 1:
                    identity = RetainedViewIdentity(segments: [.role(.content), .slot(99)])
                        .appending(contentsOf: Array(prefix.segments.dropFirst(2))).appending(.slot(0))
                case 2:
                    identity = prefix
                default:
                    identity = prefix.appending(contentsOf: [.keyed(.init(1)), .explicit(.init(2))])
                }
                return [self.node(identity)]
            }
            defer { fixture.finish() }

            guard case .unsupported = fixture.prepare() else {
                return XCTFail("A missing, wrong, or structurally incomplete prefix must be rejected: \(shape)")
            }

            assertUnpublished(fixture)
        }
    }

    func testNestedPrefixEqualityKeepsEqualAndDifferentResults() async throws {
        for wrapper in AdapterCheckedIdentityWrapper.allCases {
            for first in [1, 9] {
                let events = AdapterCheckedIdentityEvents()
                let expectedRoot = nestedRoot(wrapper, events: events)
                let fixture = try AdapterCheckedIdentityFixture(identityRoot: expectedRoot) { prefix in
                    // Build an independent box; shared array storage must not
                    // short-circuit the authored equality this test exercises.
                    let root = self.nestedRoot(wrapper, first: first, events: events)
                    let identity = root.appending(
                        contentsOf: Array(prefix.segments.dropFirst(expectedRoot.segments.count)))
                    return [self.node(identity.appending(.branch(false)))]
                }
                defer { fixture.finish() }

                let result = fixture.prepare()

                if first == 1 {
                    guard case .ready(let candidate) = result else {
                        return XCTFail("An equal nested prefix must remain accepted: \(wrapper)")
                    }
                    XCTAssertEqual(candidate.children.count, 1)
                    XCTAssertEqual(events.callbacks, ["equal:1:1", "equal:2:2"])
                } else {
                    guard case .unsupported = result else {
                        return XCTFail("A different nested prefix must remain rejected: \(wrapper)")
                    }
                    XCTAssertEqual(events.callbacks, ["equal:9:1"])
                }
                assertUnpublished(fixture)
            }
        }
    }

    func testNestedPrefixRevocationStopsBeforeTheSecondAuthoredKey() async throws {
        for wrapper in AdapterCheckedIdentityWrapper.allCases {
            let events = AdapterCheckedIdentityEvents()
            let expectedRoot = nestedRoot(wrapper, events: events)
            let fixture = try AdapterCheckedIdentityFixture(identityRoot: expectedRoot) { prefix in
                let root = self.nestedRoot(wrapper, events: events)
                let identity = root.appending(
                    contentsOf: Array(prefix.segments.dropFirst(expectedRoot.segments.count)))
                return [
                    self.node(
                        identity.appending(contentsOf: [
                            .slot(0), .keyed(.init(AdapterCheckedIdentityKey(value: 3, events: events))),
                        ]))
                ]
            }
            defer {
                events.onEquality = nil
                fixture.finish()
            }
            events.onEquality = { [weak source = fixture.source] in source?.close() }

            guard case .obsolete = fixture.prepare() else {
                return XCTFail("Nested prefix revocation must discard preparation: \(wrapper)")
            }

            XCTAssertEqual(events.callbacks, ["equal:1:1"])
            XCTAssertNil(fixture.source.metadata)
            assertUnpublished(fixture)
        }
    }

    func testNestedDuplicateRevocationStopsBeforeTheSecondAuthoredKey() async throws {
        for wrapper in AdapterCheckedIdentityWrapper.allCases {
            for explicit in [false, true] {
                let events = AdapterCheckedIdentityEvents()
                let fixture = try AdapterCheckedIdentityFixture { prefix in
                    (0..<2).map { _ in
                        let key = self.nestedKey(wrapper, events: events)
                        return self.node(
                            prefix.appending(contentsOf: [
                                .slot(0), explicit ? .explicit(key) : .keyed(key),
                                .keyed(.init(AdapterCheckedIdentityKey(value: 3, events: events))),
                            ]))
                    }
                }
                defer {
                    events.onEquality = nil
                    fixture.finish()
                }
                events.onEquality = { [weak source = fixture.source] in source?.close() }

                guard case .obsolete = fixture.prepare() else {
                    return XCTFail("Nested duplicate comparison must stop after revocation: \(wrapper)")
                }

                XCTAssertEqual(events.callbacks, ["equal:1:1"])
                XCTAssertNil(fixture.source.metadata)
                assertUnpublished(fixture)
            }
        }
    }

    func testIdentityReleaseRevocationIsObservedBeforePreparationReturns() async throws {
        let events = AdapterCheckedIdentityEvents()
        let first = ViewNode()
        let second = ViewNode()
        let fixture = try AdapterCheckedIdentityFixture { prefix in
            first.retainedViewIdentity = prefix.appending(contentsOf: [
                .slot(0), .keyed(.init(AdapterCheckedReleasedIdentityKey(events: events))),
            ])
            self.installReleasedIdentity(on: second, prefix: prefix, events: events)
            return [first, second]
        }
        defer {
            events.onEquality = nil
            events.onRelease = nil
            fixture.finish()
        }
        events.onEquality = { [weak second] in second?.retainedViewIdentity = nil }
        events.onRelease = { [weak source = fixture.source] in source?.close() }

        guard case .obsolete = fixture.prepare() else {
            return XCTFail("The retiring helper identity must revoke the generation before preparation returns")
        }

        XCTAssertEqual(events.callbacks, ["equal:released", "release"])
        XCTAssertNil(events.releasedKey)
        XCTAssertNil(second.retainedViewIdentity)
        XCTAssertNil(fixture.source.metadata)
        assertUnpublished(fixture)
    }

    private func node(_ identity: RetainedViewIdentity?) -> ViewNode {
        let node = ViewNode()
        node.retainedViewIdentity = identity
        return node
    }

    private func nestedRoot(
        _ wrapper: AdapterCheckedIdentityWrapper, first: Int = 1, events: AdapterCheckedIdentityEvents
    ) -> RetainedViewIdentity {
        .init(segments: [.role(.content), .keyed(nestedKey(wrapper, first: first, events: events))])
    }

    private func nestedKey(
        _ wrapper: AdapterCheckedIdentityWrapper, first: Int = 1, events: AdapterCheckedIdentityEvents
    ) -> RetainedViewIdentity.Key {
        let inner = RetainedViewIdentity(segments: [
            .keyed(.init(AdapterCheckedIdentityKey(value: first, events: events))),
            .explicit(.init(AdapterCheckedIdentityKey(value: 2, events: events))),
        ])
        switch wrapper {
        case .identity:
            return .init(inner)
        case .key:
            return .init(RetainedViewIdentity.Key(inner))
        case .segment:
            return .init(RetainedViewIdentity.Segment.explicit(.init(inner)))
        case .recursive:
            return .init(
                RetainedViewIdentity.Key(
                    RetainedViewIdentity.Segment.keyed(
                        .init(RetainedViewIdentity(segments: [.explicit(.init(inner))])))))
        }
    }

    private func installReleasedIdentity(
        on node: ViewNode, prefix: RetainedViewIdentity, events: AdapterCheckedIdentityEvents
    ) {
        let key = AdapterCheckedReleasedIdentityKey(events: events, reportsRelease: true)
        events.releasedKey = key
        node.retainedViewIdentity = prefix.appending(contentsOf: [.slot(0), .keyed(.init(key))])
    }

    private func assertUnpublished(_ fixture: AdapterCheckedIdentityFixture) {
        XCTAssertEqual(fixture.factoryCalls, 1)
        XCTAssertEqual(fixture.budget.remainingElements, 0)
        XCTAssertEqual(fixture.budget.remainingRounds, 1)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 0)
        XCTAssertTrue(fixture.container.children.isEmpty)
        XCTAssertFalse(fixture.admission.didMutate)
    }
}

@MainActor
private final class AdapterCheckedIdentityFixture {
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let runtime: RetainedViewRuntime
    let admission: RetainedLazyListAdoptionAdmission
    let budget: RetainedLazyListWorkBudget
    private let viewport: RetainedLazyListRuntimeAdapter.Viewport
    private let lease: AdapterCheckedIdentityLease
    private let epoch: AdapterCheckedIdentityEpoch
    private let calls: AdapterCheckedIdentityFactoryCalls
    var factoryCalls: Int { calls.count }

    init(
        identityRoot: RetainedViewIdentity = .init(segments: [.role(.content), .slot(0)]),
        content: @escaping @MainActor (RetainedViewIdentity) -> [ViewNode]
    ) throws {
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        let calls = AdapterCheckedIdentityFactoryCalls()
        guard
            source.replaceData(
                [0], id: \.self, identityRoot: identityRoot,
                rowContent: { _, prefix in
                    calls.count += 1
                    return content(prefix)
                })
        else { throw AdapterCheckedIdentityFixtureError.setup }
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 1, maximumMountedLeaves: 4, maximumProtectedRecords: 1))
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 20))
        budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20))
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20)))
        runtime.root.addChild(container)
        let lease = AdapterCheckedIdentityLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = AdapterCheckedIdentityEpoch()
        coordinator.install(epoch, startedAt: sequence)
        admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime, coordinator: coordinator, sequence: sequence)
        self.source = source
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.lease = lease
        self.epoch = epoch
        self.calls = calls
    }

    func prepare() -> RetainedLazyListRuntimeAdapter.Preparation {
        adapter.prepare(viewport: viewport, protectedRoots: [], budget: budget, admission: admission)
    }

    func finish() {
        admission.revoke()
        source.close()
        epoch.abandon()
        epoch.finishAfterCallbacks()
        runtime.retainedBuildCoordinator.finishBuild()
    }
}

@MainActor
private final class AdapterCheckedIdentityFactoryCalls { var count = 0 }

private enum AdapterCheckedIdentityFixtureError: Error { case setup }
private enum AdapterCheckedIdentityWrapper: CaseIterable { case identity, key, segment, recursive }

@MainActor
private final class AdapterCheckedIdentityLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { AdapterCheckedIdentityEpoch() }
}

@MainActor
private final class AdapterCheckedIdentityEpoch: RetainedBuildEpoch {
    var canAdopt: Bool { true }
    func supersede() {}
    func willAdopt() -> Bool { true }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}

@MainActor
private final class AdapterCheckedIdentityEvents {
    var callbacks: [String] = []
    var onEquality: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?
    weak var releasedKey: AdapterCheckedReleasedIdentityKey?

    func equal(_ callback: String) {
        callbacks.append(callback)
        let action = onEquality
        onEquality = nil
        action?()
    }
}

private struct AdapterCheckedIdentityKey: Hashable {
    let value: Int
    let events: AdapterCheckedIdentityEvents

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.events.equal("equal:\(lhs.value):\(rhs.value)") }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

private final class AdapterCheckedReleasedIdentityKey: Hashable {
    let events: AdapterCheckedIdentityEvents
    let reportsRelease: Bool

    init(events: AdapterCheckedIdentityEvents, reportsRelease: Bool = false) {
        self.events = events
        self.reportsRelease = reportsRelease
    }

    static func == (lhs: AdapterCheckedReleasedIdentityKey, rhs: AdapterCheckedReleasedIdentityKey) -> Bool {
        MainActor.assumeIsolated { lhs.events.equal("equal:released") }
        return true
    }

    func hash(into hasher: inout Hasher) { hasher.combine(0) }

    deinit {
        if reportsRelease {
            MainActor.assumeIsolated { [events] in
                events.callbacks.append("release")
                events.onRelease?()
            }
        }
    }
}
