import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Captured row ancestry does not prove canonical leaf structure or authorize
/// adoption, focus, or input. Public List does not use this provider yet.
@MainActor
final class RetainedLazyListProviderIdentityTests: XCTestCase {
    func testPlainFactoryDoesNotClaimIdentityAndKeepsItsOutputBehavior() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime(source) {} }
        var calls = 0
        XCTAssertTrue(
            source.replaceData([7], id: \.self) { value in
                calls += 1
                return value + 1
            })
        let request = try request(source)
        let provider: any RetainedLazyListProvider<Int> = source
        XCTAssertNil(provider.identityPrefix(for: request))
        XCTAssertTrue(request.isGenerationCurrent)
        XCTAssertEqual(calls, 0)
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))

        guard case .built(let built) = provider.materialize(request, budget: budget) else {
            return XCTFail("The original factory path must still materialize")
        }
        XCTAssertEqual(built.request, request)
        XCTAssertEqual(built.content, 8)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(budget.remainingElements, 0)
    }

    func testProviderDefaultRequiresExplicitIdentityOptIn() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(source.replaceData([1], id: \.self, identityRoot: root) { value, _ in value })
        let request = try request(source)
        XCTAssertNotNil(source.identityPrefix(for: request))
        let wrapper = LazyListIdentityDefaultProvider(source: source)
        let provider: any RetainedLazyListProvider<Int> = wrapper

        XCTAssertNil(provider.identityPrefix(for: request))
        XCTAssertEqual(wrapper.calls, 0, "The default must not infer identity from another requirement")
        XCTAssertTrue(request.isGenerationCurrent)
    }

    func testCapturedTypedKeysAndDuplicateOccurrencesReachFactory() async throws {
        let source = RetainedLazyListDataSource<Int, RetainedViewIdentity>()
        defer { withExtendedLifetime(source) {} }
        var calls = 0
        XCTAssertTrue(
            source.replaceData([11, 11, 12], id: \.self, identityRoot: root) { _, prefix in
                calls += 1
                return prefix
            })
        XCTAssertEqual(calls, 0)
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 3, roundLimit: 1))
        let keys = [11, 11, 12]
        let occurrences = [0, 1, 0]
        for index in keys.indices {
            let request = try request(source, at: index)
            let expected = prefix(root: root, id: keys[index], occurrence: occurrences[index])
            XCTAssertEqual(source.identityPrefix(for: request), expected)
            guard case .built(let built) = source.materialize(request, budget: budget) else {
                return XCTFail("Each requested item must receive its captured prefix")
            }
            XCTAssertEqual(built.content, expected)
        }
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(budget.remainingElements, 0)

        let narrow = RetainedLazyListDataSource<Int8, Int>()
        defer { withExtendedLifetime(narrow) {} }
        XCTAssertTrue(narrow.replaceData([Int8(11)], id: \.self, identityRoot: root) { value, _ in Int(value) })
        let narrowPrefix = try XCTUnwrap(narrow.identityPrefix(for: try request(narrow)))
        XCTAssertEqual(narrowPrefix, prefix(root: root, id: Int8(11)))
        XCTAssertNotEqual(narrowPrefix, source.identityPrefix(for: try request(source)))
    }

    func testPrefixQueriesAndFactoryContextDoNotReadOrCompareAdditionalIDs() async throws {
        let hooks = LazyListIdentityHooks()
        let source = RetainedLazyListDataSource<LazyListIdentityElement, Int>()
        defer { withExtendedLifetime(source) {} }
        let values = (0..<128).map { LazyListIdentityElement(identifier: $0, hooks: hooks) }
        var received: RetainedViewIdentity?
        XCTAssertTrue(
            source.replaceData(values, id: \.id, identityRoot: root) { value, prefix in
                hooks.factoryCalls += 1
                received = prefix
                return value.identifier
            })
        XCTAssertEqual(hooks.keyReads, values.count)
        XCTAssertEqual(hooks.factoryCalls, 0)
        let request = try request(source, at: 93)
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        let before = hooks.counts
        for _ in 0..<64 {
            XCTAssertNotNil(source.identityPrefix(for: request))
        }
        XCTAssertEqual(hooks.counts, before)
        XCTAssertEqual(budget.remainingElements, 1)
        XCTAssertEqual(budget.remainingRounds, 1)

        guard case .built(let built) = source.materialize(request, budget: budget) else {
            return XCTFail("One budgeted factory must build the requested item")
        }
        XCTAssertEqual(built.content, 93)
        XCTAssertEqual(hooks.keyReads, before[0] + 2, "Keep exactly the existing pre/post-factory ID checks")
        XCTAssertEqual(hooks.hashCalls, before[1])
        XCTAssertEqual(hooks.equalityCalls, before[2] + 2)
        XCTAssertEqual(hooks.factoryCalls, 1)
        XCTAssertEqual(budget.remainingElements, 0)
        // Compare only after the callback counters above; identity equality can
        // itself invoke the authored Hashable implementation.
        XCTAssertEqual(received, source.identityPrefix(for: request))
    }

    func testStableRowPrefixSurvivesReorderAndDeletionReinsertion() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(source.replaceData([11, 12, 11], id: \.self, identityRoot: root) { value, _ in value })
        let first = try request(source)
        let duplicate = try request(source, at: 2)
        let firstPrefix = try XCTUnwrap(source.identityPrefix(for: first))
        let duplicatePrefix = try XCTUnwrap(source.identityPrefix(for: duplicate))
        XCTAssertNotEqual(firstPrefix, duplicatePrefix)

        XCTAssertTrue(source.replaceData([12, 11, 11], id: \.self, identityRoot: root) { value, _ in value })
        let reordered = try request(source, at: 1)
        let reorderedDuplicate = try request(source, at: 2)
        XCTAssertEqual(first.token, reordered.token)
        XCTAssertEqual(duplicate.token, reorderedDuplicate.token)
        XCTAssertEqual(source.identityPrefix(for: reordered), firstPrefix)
        XCTAssertEqual(source.identityPrefix(for: reorderedDuplicate), duplicatePrefix)
        XCTAssertNil(source.identityPrefix(for: first))
        XCTAssertFalse(first.isGenerationCurrent)

        XCTAssertTrue(source.replaceData([12], id: \.self, identityRoot: root) { value, _ in value })
        XCTAssertTrue(source.replaceData([11, 12, 11], id: \.self, identityRoot: root) { value, _ in value })
        let reinserted = try request(source)
        let reinsertedDuplicate = try request(source, at: 2)
        XCTAssertNotEqual(reinserted.token, first.token)
        XCTAssertNotEqual(reinsertedDuplicate.token, duplicate.token)
        XCTAssertEqual(source.identityPrefix(for: reinserted), firstPrefix)
        XCTAssertEqual(source.identityPrefix(for: reinsertedDuplicate), duplicatePrefix)
        XCTAssertNil(source.identityPrefix(for: reordered))
    }

    func testIdentityRootChangeAndPlainReplacementRevokeOldQueries() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(source.replaceData([1], id: \.self, identityRoot: root) { value, _ in value })
        let old = try request(source)
        let oldPrefix = try XCTUnwrap(source.identityPrefix(for: old))
        let changedRoot = root.appending(.slot(9))
        XCTAssertTrue(source.replaceData([1], id: \.self, identityRoot: changedRoot) { value, _ in value })
        let changed = try request(source)
        XCTAssertEqual(changed.token, old.token)
        XCTAssertEqual(source.identityPrefix(for: changed), prefix(root: changedRoot, id: 1))
        XCTAssertNotEqual(source.identityPrefix(for: changed), oldPrefix)
        XCTAssertNil(source.identityPrefix(for: old))

        XCTAssertTrue(source.replaceData([1], id: \.self, rowContent: { $0 }))
        let plain = try request(source)
        XCTAssertEqual(plain.token, old.token)
        XCTAssertNil(source.identityPrefix(for: plain))
        XCTAssertTrue(plain.isGenerationCurrent)
        XCTAssertFalse(changed.isGenerationCurrent)
    }

    func testQueryRejectsForeignClosedAndBusyRequestsWithoutRevokingReadOnlyReentry() async throws {
        let hooks = LazyListIdentityHooks()
        let element = LazyListIdentityElement(identifier: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListIdentityElement, Int>()
        let other = RetainedLazyListDataSource<LazyListIdentityElement, Int>()
        defer {
            withExtendedLifetime(source) {}
            withExtendedLifetime(other) {}
        }
        var current: RetainedLazyListRowRequest?
        var observed: [Bool] = []
        XCTAssertTrue(
            source.replaceData([element], id: \.id, identityRoot: root) { [weak source] value, _ in
                if let current {
                    observed.append(source?.identityPrefix(for: current) == nil)
                    observed.append(current.isGenerationCurrent)
                }
                return value.identifier
            })
        XCTAssertTrue(other.replaceData([element], id: \.id, identityRoot: root) { value, _ in value.identifier })
        let request = try request(source)
        current = request
        XCTAssertNil(other.identityPrefix(for: request))
        XCTAssertNil(source.identityPrefix(for: try self.request(other)))
        XCTAssertTrue(request.isGenerationCurrent)
        let inspect: @MainActor () -> Void = {
            observed.append(source.identityPrefix(for: request) == nil)
            observed.append(request.isGenerationCurrent)
        }
        hooks.onHash = inspect
        XCTAssertEqual(source.token(for: .init(LazyListIdentityKey(value: 1, hooks: hooks))), request.token)
        XCTAssertEqual(observed, [true, true])
        hooks.onEquality = inspect
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        guard case .built = source.materialize(request, budget: budget) else {
            return XCTFail("Read-only identity queries must not invalidate materialization")
        }
        XCTAssertEqual(observed, [true, true, true, true, true, true])
        XCTAssertNotNil(source.identityPrefix(for: request))
        XCTAssertTrue(request.isGenerationCurrent)
        source.close()
        XCTAssertNil(source.identityPrefix(for: request))
        XCTAssertFalse(request.isGenerationCurrent)
    }

    func testCapturedPrefixDoesNotObserveIDDriftUntilMaterialization() async throws {
        let hooks = LazyListIdentityHooks()
        let element = LazyListIdentityElement(identifier: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListIdentityElement, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(
            source.replaceData([element], id: \.id, identityRoot: root) { value, _ in
                hooks.factoryCalls += 1
                return value.identifier
            })
        let request = try request(source)
        let captured = try XCTUnwrap(source.identityPrefix(for: request))
        element.identifier = 2
        let before = hooks.counts
        let stillCaptured = source.identityPrefix(for: request)
        XCTAssertEqual(hooks.counts, before)
        XCTAssertEqual(stillCaptured, captured)
        XCTAssertTrue(request.isGenerationCurrent, "Native proof reads do not observe arbitrary model changes")
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))

        guard case .obsolete = source.materialize(request, budget: budget) else {
            return XCTFail("The existing ID check must revoke the changed snapshot")
        }
        XCTAssertEqual(hooks.factoryCalls, 0)
        XCTAssertFalse(request.isGenerationCurrent)
        XCTAssertNil(source.identityPrefix(for: request))
        element.identifier = 1
        XCTAssertNil(source.identityPrefix(for: request), "Restoring an ID cannot revive the old generation")
    }

    func testFactoryIDDriftUsesCapturedPrefixAndRevokesWithoutRetry() async throws {
        let hooks = LazyListIdentityHooks()
        let element = LazyListIdentityElement(identifier: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListIdentityElement, Int>()
        defer { withExtendedLifetime(source) {} }
        var received: RetainedViewIdentity?
        XCTAssertTrue(
            source.replaceData([element], id: \.id, identityRoot: root) { value, prefix in
                hooks.factoryCalls += 1
                received = prefix
                value.identifier = 2
                return value.identifier
            })
        let request = try request(source)
        let captured = try XCTUnwrap(source.identityPrefix(for: request))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        guard case .obsolete = source.materialize(request, budget: budget) else {
            return XCTFail("Post-factory ID drift must discard the candidate")
        }
        XCTAssertEqual(hooks.factoryCalls, 1)
        XCTAssertEqual(hooks.keyReads, 3)
        XCTAssertEqual(received, captured)
        XCTAssertFalse(request.isGenerationCurrent)
        XCTAssertNil(source.identityPrefix(for: request))
        XCTAssertEqual(budget.remainingElements, 0)
    }

    func testIdentifiedFactoryPreservesZeroAndMultipleStructuralLeavesWithinElementBudget() async throws {
        let source = RetainedLazyListDataSource<Int, [RetainedViewIdentity]>()
        defer { withExtendedLifetime(source) {} }
        let paths: [[RetainedViewIdentity.Segment]] = [
            [.slot(4), .branch(true)], [.slot(9), .branch(false)],
        ]
        var calls = 0
        XCTAssertTrue(
            source.replaceData([0, 2, 1], id: \.self, identityRoot: root) { value, prefix in
                calls += 1
                return paths.prefix(value).map { prefix.appending(contentsOf: $0) }
            })
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 3, roundLimit: 1))
        let counts = [0, 2, 1]
        for index in counts.indices {
            let request = try request(source, at: index)
            let expectedPrefix = prefix(root: root, id: counts[index])
            guard case .built(let built) = source.materialize(request, budget: budget) else {
                return XCTFail("Work is charged per data element, including zero and multiple leaves")
            }
            let expectedLeaves = paths.prefix(counts[index]).map { expectedPrefix.appending(contentsOf: $0) }
            XCTAssertEqual(built.content, expectedLeaves)
            XCTAssertEqual(source.identityPrefix(for: request), expectedPrefix)
        }
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(budget.remainingElements, 0)
        guard case .budgetExhausted = source.materialize(try request(source), budget: budget) else {
            return XCTFail("Identity context must not bypass the element budget")
        }
        XCTAssertEqual(calls, 3)
    }

    func testNestedIdentifiedReplacementRevokesBeforeDiscardedContentCleanup() async throws {
        let source = RetainedLazyListDataSource<Int, LazyListIdentityPayload>()
        defer { withExtendedLifetime(source) {} }
        var current: RetainedLazyListRowRequest?
        var nested: Bool?
        var observed: [Bool] = []
        var calls = 0
        let identityRoot = root
        XCTAssertTrue(
            source.replaceData([1], id: \.self, identityRoot: identityRoot) { [weak source] _, _ in
                calls += 1
                nested = source?.replaceData([2], id: \.self, identityRoot: identityRoot) { _, _ in
                    LazyListIdentityPayload()
                }
                return LazyListIdentityPayload { [weak source] in
                    observed.append(current?.isGenerationCurrent == true)
                    if let current { observed.append(source?.identityPrefix(for: current) != nil) }
                }
            })
        let request = try request(source)
        current = request
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        guard case .obsolete = source.materialize(request, budget: budget) else {
            return XCTFail("A rejected nested replacement still revokes its outer generation")
        }
        XCTAssertEqual(nested, false)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(observed, [false, false])
        XCTAssertNil(source.metadata)
        XCTAssertFalse(request.isGenerationCurrent)
        XCTAssertEqual(budget.remainingElements, 0)
    }

    func testIdentifiedReplacementRefusesNestedCollectionIntentAndRecovers() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime(source) {} }
        let identityRoot = root
        XCTAssertTrue(source.replaceData([1], id: \.self, identityRoot: identityRoot) { value, _ in value })
        let old = try request(source)
        var nested: Bool?
        var observed: [Bool] = []
        let values = LazyListIdentityReadCollection(values: [2]) {
            observed.append(old.isGenerationCurrent)
            observed.append(source.identityPrefix(for: old) != nil)
            nested = source.replaceData([3], id: \.self, identityRoot: identityRoot) { value, _ in value }
        }

        XCTAssertFalse(source.replaceData(values, id: \.self, identityRoot: identityRoot) { value, _ in value })
        XCTAssertEqual(nested, false)
        XCTAssertEqual(observed, [false, false])
        XCTAssertNil(source.metadata)
        XCTAssertTrue(source.replaceData([1], id: \.self, identityRoot: identityRoot) { value, _ in value })
        XCTAssertNotNil(source.identityPrefix(for: try request(source)))
        XCTAssertNil(source.identityPrefix(for: old))
        XCTAssertFalse(old.isGenerationCurrent)
    }

    func testPrefixEqualityCanRevokeGenerationAndIsNotAdoptionAuthority() async throws {
        let hooks = LazyListIdentityHooks()
        let element = LazyListIdentityElement(identifier: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListIdentityElement, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(source.replaceData([element], id: \.id, identityRoot: root) { value, _ in value.identifier })
        let request = try request(source)
        let actual = try XCTUnwrap(source.identityPrefix(for: request))
        let expected = prefix(root: root, id: LazyListIdentityKey(value: 1, hooks: hooks))
        hooks.onEquality = { source.close() }

        XCTAssertEqual(actual, expected, "Equal prefixes do not make callbacks during equality harmless")
        XCTAssertTrue(source.isClosed)
        XCTAssertFalse(request.isGenerationCurrent)
        XCTAssertNil(source.identityPrefix(for: request))
    }

    func testRetainedPrefixOwnsKeysButNotSourceModelFactoryOrNativeProofLifetime() async throws {
        var source: RetainedLazyListDataSource<LazyListIdentityOwnedElement, Int>? = .init()
        weak var releasedSource = source
        weak var releasedModel: LazyListIdentityOwnedElement?
        weak var releasedFactory: LazyListIdentityPayload?
        weak var retainedKey: LazyListIdentityOwnedKey?
        weak var retainedRoot: LazyListIdentityOwnedKey?
        var current: RetainedLazyListRowRequest?
        var destroyed: [String] = []
        var observed: [Bool] = []
        @MainActor func install() {
            let key = LazyListIdentityOwnedKey(value: 1) { destroyed.append("key") }
            let rootKey = LazyListIdentityOwnedKey(value: 2) { destroyed.append("root") }
            let element = LazyListIdentityOwnedElement(id: key) {
                destroyed.append("model")
                observed.append(current?.isGenerationCurrent == true)
            }
            let payload = LazyListIdentityPayload {
                destroyed.append("factory")
                observed.append(current?.isGenerationCurrent == true)
            }
            releasedModel = element
            releasedFactory = payload
            retainedKey = key
            retainedRoot = rootKey
            let ancestor = RetainedViewIdentity(segments: [.explicit(.init(rootKey))])
            XCTAssertEqual(
                source?.replaceData([element], id: \.id, identityRoot: ancestor) { [payload] value, _ in
                    withExtendedLifetime(payload) {}
                    return value.id.value
                }, true)
        }
        install()
        let token = try XCTUnwrap(source?.metadata?.rows.first?.token)
        let request = try XCTUnwrap(source?.request(for: token))
        current = request
        var retainedPrefix = source?.identityPrefix(for: request)
        withExtendedLifetime(source) {
            XCTAssertNotNil(retainedPrefix)
            XCTAssertTrue(request.isGenerationCurrent)
        }
        source = nil

        XCTAssertNil(releasedSource)
        XCTAssertNil(releasedModel)
        XCTAssertNil(releasedFactory)
        XCTAssertEqual(Set(destroyed), Set(["model", "factory"]))
        XCTAssertEqual(observed, [false, false])
        XCTAssertNotNil(retainedKey, "A returned identity intentionally contains the captured authored key")
        XCTAssertNotNil(retainedRoot, "A returned identity intentionally contains the captured ancestor path")
        XCTAssertFalse(request.isGenerationCurrent)
        withExtendedLifetime(retainedPrefix) {}
        retainedPrefix = nil
        XCTAssertNil(retainedKey)
        XCTAssertNil(retainedRoot)
        XCTAssertEqual(destroyed.count, 4)
        XCTAssertEqual(Set(destroyed), Set(["model", "factory", "key", "root"]))
        XCTAssertFalse(request.isGenerationCurrent)
    }

    func testOutgoingIdentityRootDestructionReentersAfterNewConfigurationAssignment() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime(source) {} }
        weak var outgoingRoot: LazyListIdentityOwnedKey?
        var current: RetainedLazyListRowRequest?
        var observed: [Bool] = []
        @MainActor func install() {
            let key = LazyListIdentityOwnedKey(value: 1) { [weak source] in
                observed.append(current?.isGenerationCurrent == true)
                source?.close()
            }
            outgoingRoot = key
            let ancestor = RetainedViewIdentity(segments: [.explicit(.init(key))])
            XCTAssertTrue(source.replaceData([1], id: \.self, identityRoot: ancestor) { value, _ in value })
        }
        install()
        current = try request(source)

        XCTAssertFalse(source.replaceData([2], id: \.self, identityRoot: root) { value, _ in value })
        XCTAssertNil(outgoingRoot)
        XCTAssertEqual(observed, [false])
        XCTAssertTrue(source.isClosed)
        XCTAssertNil(source.metadata)
        XCTAssertEqual(current?.isGenerationCurrent, false)
    }

    private var root: RetainedViewIdentity {
        RetainedViewIdentity(segments: [.role(.body), .slot(7)])
    }

    private func prefix<ID: Hashable>(
        root: RetainedViewIdentity, id: ID, occurrence: Int = 0
    ) -> RetainedViewIdentity {
        RetainedViewIdentity(segments: root.segments + [.role(.row), .keyed(.init(id)), .occurrence(occurrence)])
    }

    private func request<Element, Output>(
        _ source: RetainedLazyListDataSource<Element, Output>, at index: Int = 0
    ) throws -> RetainedLazyListRowRequest {
        let metadata = try XCTUnwrap(source.metadata)
        let token = try XCTUnwrap(metadata.rows.indices.contains(index) ? metadata.rows[index].token : nil)
        return try XCTUnwrap(source.request(for: token))
    }
}

@MainActor
private final class LazyListIdentityDefaultProvider<Element, Output>: RetainedLazyListProvider {
    typealias RowContent = Output
    let source: RetainedLazyListDataSource<Element, Output>
    var calls = 0

    init(source: RetainedLazyListDataSource<Element, Output>) {
        self.source = source
    }

    var metadata: RetainedLazyListMetadata? {
        calls += 1
        return source.metadata
    }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        calls += 1
        return source.request(for: token)
    }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        calls += 1
        return source.isCurrent(request)
    }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<Output> {
        calls += 1
        return source.materialize(request, budget: budget)
    }
}

@MainActor
private final class LazyListIdentityHooks {
    var keyReads = 0
    var hashCalls = 0
    var equalityCalls = 0
    var factoryCalls = 0
    var onHash: (@MainActor () -> Void)?
    var onEquality: (@MainActor () -> Void)?

    var counts: [Int] { [keyReads, hashCalls, equalityCalls, factoryCalls] }

    func hash() {
        hashCalls += 1
        let action = onHash
        onHash = nil
        action?()
    }

    func equality() {
        equalityCalls += 1
        let action = onEquality
        onEquality = nil
        action?()
    }
}

private struct LazyListIdentityKey: Hashable {
    let value: Int
    let hooks: LazyListIdentityHooks

    static func == (lhs: Self, rhs: Self) -> Bool {
        let hooks = lhs.hooks
        MainActor.assumeIsolated { [hooks] in hooks.equality() }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { [hooks] in hooks.hash() }
        hasher.combine(value)
    }
}

private final class LazyListIdentityElement {
    var identifier: Int
    let hooks: LazyListIdentityHooks

    init(identifier: Int, hooks: LazyListIdentityHooks) {
        self.identifier = identifier
        self.hooks = hooks
    }

    var id: LazyListIdentityKey {
        MainActor.assumeIsolated { [hooks] in hooks.keyReads += 1 }
        return LazyListIdentityKey(value: identifier, hooks: hooks)
    }
}

private struct LazyListIdentityReadCollection<Element>: RandomAccessCollection {
    let values: [Element]
    let onRead: @MainActor () -> Void
    var startIndex: Int { values.startIndex }
    var endIndex: Int { values.endIndex }
    func index(after index: Int) -> Int { index + 1 }
    func index(before index: Int) -> Int { index - 1 }

    subscript(position: Int) -> Element {
        MainActor.assumeIsolated { [onRead] in onRead() }
        return values[position]
    }
}

private final class LazyListIdentityPayload {
    let onDestroy: (@MainActor () -> Void)?

    init(onDestroy: (@MainActor () -> Void)? = nil) {
        self.onDestroy = onDestroy
    }

    deinit {
        MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
    }
}

private final class LazyListIdentityOwnedKey: Hashable {
    let value: Int
    let onDestroy: (@MainActor () -> Void)?

    init(value: Int, onDestroy: (@MainActor () -> Void)? = nil) {
        self.value = value
        self.onDestroy = onDestroy
    }

    static func == (lhs: LazyListIdentityOwnedKey, rhs: LazyListIdentityOwnedKey) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    deinit {
        MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
    }
}

private final class LazyListIdentityOwnedElement {
    let id: LazyListIdentityOwnedKey
    let onDestroy: (@MainActor () -> Void)?

    init(id: LazyListIdentityOwnedKey, onDestroy: (@MainActor () -> Void)? = nil) {
        self.id = id
        self.onDestroy = onDestroy
    }

    deinit {
        MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
    }
}
