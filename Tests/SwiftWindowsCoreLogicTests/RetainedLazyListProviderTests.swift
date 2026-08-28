import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// These are source/model tests. They do not enable List virtualization or
/// establish a viewport, render-resource, state-lifetime, or native UIA budget.
@MainActor
final class RetainedLazyListProviderTests: XCTestCase {
    func testMetadataEnumerationDoesNotInvokeAnyRowFactory() async throws {
        for count in [0, 100, 1000, 10_000] {
            let source = RetainedLazyListDataSource<Int, Int>()
            var calls = 0
            XCTAssertTrue(
                source.replaceData(0..<count, id: \.self) { value in
                    calls += 1
                    return value
                })
            let metadata = try XCTUnwrap(source.metadata)
            XCTAssertEqual(metadata.rows.count, count)
            XCTAssertEqual(metadata.rows.map(\.sourceIndex), Array(0..<count))
            XCTAssertEqual(Set(metadata.rows.map(\.token)).count, count)
            XCTAssertEqual(calls, 0)
        }
    }

    func testExplicitRequestsSpendOnlyTheirBoundedElementBudget() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        var calls: [Int] = []
        XCTAssertTrue(
            source.replaceData(0..<10_000, id: \.self) { value in
                calls.append(value)
                return value * 2
            })
        let provider: any RetainedLazyListProvider<Int> = source
        let rows = try XCTUnwrap(provider.metadata).rows
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 3, roundLimit: 1))
        for index in [0, 500, 9999] {
            let request = try XCTUnwrap(provider.request(for: rows[index].token))
            let built = try XCTUnwrap(builtRow(provider.materialize(request, budget: budget)))
            XCTAssertEqual(built.request, request)
            XCTAssertEqual(built.content, index * 2)
            XCTAssertTrue(provider.isCurrent(built.request))
        }
        let fourth = try XCTUnwrap(source.request(for: rows[1].token))
        guard case .budgetExhausted = source.materialize(fourth, budget: budget) else {
            return XCTFail("An exhausted element budget must refuse construction")
        }
        XCTAssertEqual(calls, [0, 500, 9999])
        XCTAssertEqual(budget.remainingElements, 0)
        XCTAssertEqual(source.metadata?.rows.count, 10_000)
    }

    func testEmptyAndMultipleLeafOutputsEachConsumeOneElementAttempt() async throws {
        let source = RetainedLazyListDataSource<Int, [Int]>()
        var calls = 0
        XCTAssertTrue(
            source.replaceData([0, 1, 3], id: \.self) { value in
                calls += 1
                return Array(repeating: value, count: value)
            })
        let rows = try XCTUnwrap(source.metadata).rows
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 3, roundLimit: 1))
        var cardinalities: [Int] = []
        for row in rows {
            let request = try XCTUnwrap(source.request(for: row.token))
            let built = try XCTUnwrap(builtRow(source.materialize(request, budget: budget)))
            cardinalities.append(built.content.count)
        }
        XCTAssertEqual(cardinalities, [0, 1, 3])
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(budget.remainingElements, 0)
        XCTAssertEqual(rows.map(\.sourceIndex), [0, 1, 2])
    }

    func testCollectionIndicesAreNotMistakenForSourceOrdinals() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        let slice = Array(0..<8)[3..<6]
        XCTAssertTrue(source.replaceData(slice, id: \.self, rowContent: { $0 }))
        let rows = try XCTUnwrap(source.metadata).rows
        XCTAssertEqual(rows.map(\.sourceIndex), [0, 1, 2])
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 3, roundLimit: 1))
        var values: [Int] = []
        for row in rows {
            let request = try XCTUnwrap(source.request(for: row.token))
            values.append(try XCTUnwrap(builtRow(source.materialize(request, budget: budget))).content)
        }
        XCTAssertEqual(values, [3, 4, 5])
    }

    func testTypedKeysWithEqualDescriptionsDoNotShareTokens() async throws {
        let source = RetainedLazyListDataSource<LazyListDescribedKey, Int>()
        let keys = [LazyListDescribedKey(value: 1), LazyListDescribedKey(value: 2)]
        XCTAssertEqual(keys[0].description, keys[1].description)
        XCTAssertTrue(source.replaceData(keys, id: \.self, rowContent: { $0.value }))
        let rows = try XCTUnwrap(source.metadata).rows
        XCTAssertNotEqual(rows[0].key, rows[1].key)
        XCTAssertNotEqual(rows[0].token, rows[1].token)
        XCTAssertEqual(source.token(for: .init(keys[1])), rows[1].token)

        let typed = RetainedLazyListDataSource<LazyListNumericKeys, Int>()
        let value = LazyListNumericKeys(narrow: 1, wide: 1)
        XCTAssertTrue(typed.replaceData([value], id: \.narrow, rowContent: { Int($0.narrow) }))
        let narrow = try XCTUnwrap(typed.metadata?.rows.first)
        XCTAssertTrue(typed.replaceData([value], id: \.wide, rowContent: { Int($0.wide) }))
        let wide = try XCTUnwrap(typed.metadata?.rows.first)
        XCTAssertNotEqual(narrow.key, wide.key)
        XCTAssertNotEqual(narrow.token, wide.token)
    }

    func testDuplicateKeysHaveDistinctOccurrenceTokensAndFirstLookup() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        XCTAssertTrue(source.replaceData([7, 7, 8], id: \.self, rowContent: { $0 }))
        let rows = try XCTUnwrap(source.metadata).rows
        XCTAssertEqual(rows.map(\.occurrence), [0, 1, 0])
        XCTAssertEqual(Set(rows.map(\.token)).count, 3)
        XCTAssertEqual(source.token(for: .init(7)), rows[0].token)
        XCTAssertEqual(source.token(for: .init(7), occurrence: 1), rows[1].token)
        XCTAssertNil(source.token(for: .init(7), occurrence: -1))
        XCTAssertNil(source.token(for: .init(7), occurrence: 2))
    }

    func testReorderKeepsTokensButRevokesEveryPriorRequest() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        XCTAssertTrue(source.replaceData([1, 2, 3], id: \.self, rowContent: { $0 }))
        let initial = try XCTUnwrap(source.metadata)
        let request = try XCTUnwrap(source.request(for: initial.rows[0].token))
        XCTAssertTrue(source.replaceData([3, 1, 2], id: \.self, rowContent: { $0 + 10 }))
        let reordered = try XCTUnwrap(source.metadata)
        XCTAssertNotEqual(initial.generation, reordered.generation)
        XCTAssertEqual(
            reordered.rows.map(\.token), [initial.rows[2].token, initial.rows[0].token, initial.rows[1].token])
        XCTAssertFalse(source.isCurrent(request))
        let current = try XCTUnwrap(source.request(for: initial.rows[0].token))
        XCTAssertEqual(current.sourceIndex, 1)
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        guard case .obsolete = source.materialize(request, budget: budget) else {
            return XCTFail("An earlier generation must not use a surviving token")
        }
        XCTAssertEqual(budget.remainingElements, 1)
        XCTAssertEqual(try XCTUnwrap(builtRow(source.materialize(current, budget: budget))).content, 11)
    }

    func testRemovedKeyReinsertionCannotReviveItsToken() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        XCTAssertTrue(source.replaceData([1, 2], id: \.self, rowContent: { $0 }))
        let initial = try XCTUnwrap(source.metadata).rows
        XCTAssertTrue(source.replaceData([2], id: \.self, rowContent: { $0 }))
        XCTAssertNil(source.request(for: initial[0].token))
        XCTAssertTrue(source.replaceData([1, 2], id: \.self, rowContent: { $0 }))
        let restored = try XCTUnwrap(source.metadata).rows
        XCTAssertNotEqual(restored[0].token, initial[0].token)
        XCTAssertEqual(restored[1].token, initial[1].token)
        XCTAssertNil(source.request(for: initial[0].token))
    }

    func testIdenticalDataInAnotherSourceDoesNotAuthorizeRequests() async throws {
        let first = RetainedLazyListDataSource<Int, Int>()
        let second = RetainedLazyListDataSource<Int, Int>()
        XCTAssertTrue(first.replaceData([1], id: \.self, rowContent: { $0 }))
        XCTAssertTrue(second.replaceData([1], id: \.self, rowContent: { $0 }))
        let row = try XCTUnwrap(first.metadata?.rows.first)
        let request = try XCTUnwrap(first.request(for: row.token))
        XCTAssertNotEqual(row.token, second.metadata?.rows.first?.token)
        XCTAssertNil(second.request(for: row.token))
        XCTAssertFalse(second.isCurrent(request))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        guard case .obsolete = second.materialize(request, budget: budget) else {
            return XCTFail("A foreign source must reject the request")
        }
        XCTAssertEqual(budget.remainingElements, 1)
    }

    func testClosingSourceIsIrreversibleAndDoesNotStayAliveThroughMetadata() async throws {
        var source: RetainedLazyListDataSource<Int, Int>? = .init()
        weak var releasedSource = source
        let metadata: RetainedLazyListMetadata
        let request: RetainedLazyListRowRequest
        do {
            let owner = try XCTUnwrap(source)
            XCTAssertTrue(owner.replaceData([1], id: \.self, rowContent: { $0 }))
            metadata = try XCTUnwrap(owner.metadata)
            request = try XCTUnwrap(owner.request(for: metadata.rows[0].token))
            owner.close()
            XCTAssertTrue(owner.isClosed)
            XCTAssertNil(owner.metadata)
            XCTAssertFalse(owner.isCurrent(request))
            XCTAssertFalse(owner.replaceData([1], id: \.self, rowContent: { $0 }))
        }
        source = nil
        XCTAssertNil(releasedSource)
        XCTAssertEqual(metadata.rows.count, 1)
        XCTAssertEqual(request.token, metadata.rows[0].token)
    }

    func testSourceDoesNotCacheMaterializedOutput() async throws {
        let source = RetainedLazyListDataSource<Int, LazyListMarker>()
        weak var marker: LazyListMarker?
        XCTAssertTrue(
            source.replaceData([1], id: \.self) { _ in
                let created = LazyListMarker()
                marker = created
                return created
            })
        XCTAssertNil(marker)
        let token = try XCTUnwrap(source.metadata?.rows.first?.token)
        let request = try XCTUnwrap(source.request(for: token))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        var result: RetainedLazyListMaterialization<LazyListMarker>? = source.materialize(request, budget: budget)
        XCTAssertNotNil(marker)
        XCTAssertNotNil(result)
        result = nil
        XCTAssertNil(marker, "Only the returned candidate, not the source metadata, owns row content")
    }

    func testExhaustedBudgetDoesNotReadAuthoredIDsOrInvokeFactories() async throws {
        let hooks = LazyListHooks()
        let element = LazyListReferenceElement(identifier: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListReferenceElement, Int>()
        var calls = 0
        XCTAssertTrue(
            source.replaceData([element], id: \.id) { value in
                calls += 1
                return value.identifier
            })
        let request = try XCTUnwrap(source.request(for: try XCTUnwrap(source.metadata?.rows.first?.token)))
        let reads = hooks.keyReads
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 0, roundLimit: 1))
        guard case .budgetExhausted = source.materialize(request, budget: budget) else {
            return XCTFail("Exhaustion must be checked before authored key access")
        }
        XCTAssertEqual(hooks.keyReads, reads)
        XCTAssertEqual(calls, 0)
    }

    func testKeyChangeBeforeMaterializationRevokesThePublishedGeneration() async throws {
        let element = LazyListReferenceElement(identifier: 1, hooks: LazyListHooks())
        let source = RetainedLazyListDataSource<LazyListReferenceElement, Int>()
        var calls = 0
        XCTAssertTrue(
            source.replaceData([element], id: \.id) { _ in
                calls += 1
                return 1
            })
        let request = try XCTUnwrap(source.request(for: try XCTUnwrap(source.metadata?.rows.first?.token)))
        element.identifier = 2
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        guard case .obsolete = source.materialize(request, budget: budget) else {
            return XCTFail("A changed reference-element ID must not build the old row")
        }
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(source.isCurrent(request))
        element.identifier = 1
        XCTAssertFalse(source.isCurrent(request))
        XCTAssertNil(source.metadata)
        XCTAssertTrue(source.replaceData([element], id: \.id, rowContent: { $0.identifier }))
    }

    func testFactoryChangingItsElementIDCannotPublishABuiltCandidate() async throws {
        let element = LazyListReferenceElement(identifier: 1, hooks: LazyListHooks())
        let source = RetainedLazyListDataSource<LazyListReferenceElement, Int>()
        var calls = 0
        XCTAssertTrue(
            source.replaceData([element], id: \.id) { value in
                calls += 1
                value.identifier = 2
                return value.identifier
            })
        let request = try XCTUnwrap(source.request(for: try XCTUnwrap(source.metadata?.rows.first?.token)))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        guard case .obsolete = source.materialize(request, budget: budget) else {
            return XCTFail("Factory completion must revalidate the captured row ID")
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(budget.remainingElements, 0)
        element.identifier = 1
        XCTAssertFalse(source.isCurrent(request))
    }

    func testFactoryReentryCannotConstructAnotherRowOrConsumeItsBudget() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 2, roundLimit: 1))
        var nestedRequest: RetainedLazyListRowRequest?
        var nestedWasRefused = false
        var calls = 0
        XCTAssertTrue(
            source.replaceData([1, 2], id: \.self) { [weak source] value in
                calls += 1
                if let source, let nestedRequest,
                    case .reentrant = source.materialize(nestedRequest, budget: budget)
                {
                    nestedWasRefused = true
                }
                return value
            })
        let rows = try XCTUnwrap(source.metadata).rows
        nestedRequest = source.request(for: rows[1].token)
        let request = try XCTUnwrap(source.request(for: rows[0].token))
        XCTAssertNotNil(builtRow(source.materialize(request, budget: budget)))
        XCTAssertTrue(nestedWasRefused)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(budget.remainingElements, 1)
    }

    func testFactoryReplacementInvalidatesWithoutRetryOrPartialPublication() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        var nestedReplacement: Bool?
        var calls = 0
        XCTAssertTrue(
            source.replaceData([1], id: \.self) { [weak source] value in
                calls += 1
                nestedReplacement = source?.replaceData([2], id: \.self, rowContent: { $0 })
                return value
            })
        let request = try XCTUnwrap(source.request(for: try XCTUnwrap(source.metadata?.rows.first?.token)))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 3, roundLimit: 1))
        guard case .obsolete = source.materialize(request, budget: budget) else {
            return XCTFail("A newer replacement intent must invalidate the factory candidate")
        }
        XCTAssertEqual(nestedReplacement, false)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(budget.remainingElements, 2)
        XCTAssertNil(source.metadata)
        XCTAssertTrue(source.replaceData([2], id: \.self, rowContent: { $0 }))
        XCTAssertFalse(source.isCurrent(request))
    }

    func testFactoryCloseDoesNotReturnItsOutputOrRestoreAvailability() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        var calls = 0
        XCTAssertTrue(
            source.replaceData([1], id: \.self) { [weak source] value in
                calls += 1
                source?.close()
                return value
            })
        let request = try XCTUnwrap(source.request(for: try XCTUnwrap(source.metadata?.rows.first?.token)))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        guard case .obsolete = source.materialize(request, budget: budget) else {
            return XCTFail("A closed source cannot publish a candidate")
        }
        XCTAssertTrue(source.isClosed)
        XCTAssertNil(source.metadata)
        XCTAssertEqual(calls, 1)
    }

    func testCollectionReadClosingSourceStopsMetadataEnumeration() async {
        let source = RetainedLazyListDataSource<Int, Int>()
        var reads = 0
        var factories = 0
        let data = LazyListReadCollection(values: Array(0..<100)) {
            reads += 1
            source.close()
        }
        XCTAssertFalse(
            source.replaceData(data, id: \.self) { value in
                factories += 1
                return value
            })
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(factories, 0)
        XCTAssertTrue(source.isClosed)
        XCTAssertNil(source.metadata)
    }

    func testHashReentryDuringMetadataReplacementDoesNotPublishEitherIntent() async {
        let hooks = LazyListHooks()
        let source = RetainedLazyListDataSource<LazyListCallbackKey, Int>()
        let key = LazyListCallbackKey(value: 1, hooks: hooks)
        var nestedReplacement: Bool?
        hooks.onHash = { [weak source] in
            nestedReplacement = source?.replaceData([key], id: \.self, rowContent: { $0.value })
        }
        XCTAssertFalse(source.replaceData([key], id: \.self, rowContent: { $0.value }))
        XCTAssertEqual(nestedReplacement, false)
        XCTAssertNil(source.metadata)
        XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { $0.value }))
    }

    func testHashAndEqualityLookupsRefuseNestedKeyLookup() async throws {
        for useEquality in [false, true] {
            let hooks = LazyListHooks()
            let key = LazyListCallbackKey(value: 1, hooks: hooks)
            let source = RetainedLazyListDataSource<LazyListCallbackKey, Int>()
            XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { $0.value }))
            let expected = try XCTUnwrap(source.metadata?.rows.first?.token)
            var nestedWasCalled = false
            var nestedToken: RetainedLazyListRowToken?
            let reenter: @MainActor () -> Void = {
                nestedWasCalled = true
                nestedToken = source.token(for: .init(key))
            }
            if useEquality { hooks.onEquality = reenter } else { hooks.onHash = reenter }
            XCTAssertEqual(source.token(for: .init(key)), expected)
            XCTAssertTrue(nestedWasCalled)
            XCTAssertNil(nestedToken)
            XCTAssertEqual(source.token(for: .init(key)), expected, "The guard must not remain stuck after lookup")
        }
    }

    func testKeyLookupCannotReenterMaterialization() async throws {
        let hooks = LazyListHooks()
        let key = LazyListCallbackKey(value: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListCallbackKey, Int>()
        XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { $0.value }))
        let token = try XCTUnwrap(source.metadata?.rows.first?.token)
        let request = try XCTUnwrap(source.request(for: token))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        var refused = false
        hooks.onHash = {
            if case .reentrant = source.materialize(request, budget: budget) { refused = true }
        }
        XCTAssertEqual(source.token(for: .init(key)), token)
        XCTAssertTrue(refused)
        XCTAssertEqual(budget.remainingElements, 1)
    }

    func testEqualityClosingSourceCannotReturnAStaleToken() async throws {
        let hooks = LazyListHooks()
        let key = LazyListCallbackKey(value: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListCallbackKey, Int>()
        XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { $0.value }))
        let request = try XCTUnwrap(source.request(for: try XCTUnwrap(source.metadata?.rows.first?.token)))
        hooks.onEquality = { source.close() }
        XCTAssertNil(source.token(for: .init(key)))
        XCTAssertTrue(source.isClosed)
        XCTAssertFalse(source.isCurrent(request))
    }

    func testHashAndEqualityReplacementDuringLookupInvalidatesBothIntents() async throws {
        for useEquality in [false, true] {
            let hooks = LazyListHooks()
            let key = LazyListCallbackKey(value: 1, hooks: hooks)
            let source = RetainedLazyListDataSource<LazyListCallbackKey, Int>()
            XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { $0.value }))
            let token = try XCTUnwrap(source.metadata?.rows.first?.token)
            let request = try XCTUnwrap(source.request(for: token))
            var nestedReplacement: Bool?
            let replace: @MainActor () -> Void = {
                nestedReplacement = source.replaceData([key], id: \.self, rowContent: { $0.value })
            }
            if useEquality { hooks.onEquality = replace } else { hooks.onHash = replace }
            XCTAssertNil(source.token(for: .init(key)))
            XCTAssertEqual(nestedReplacement, false)
            XCTAssertNil(source.metadata)
            XCTAssertFalse(source.isCurrent(request))
            XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { $0.value }))
            XCTAssertNotNil(source.token(for: .init(key)))
            XCTAssertFalse(source.isCurrent(request))
        }
    }

    func testOutgoingFactoryDestructionCanCloseTheReplacementBeforeSuccess() async {
        let source = RetainedLazyListDataSource<Int, Int>()
        var destructions = 0
        @MainActor func install() {
            let witness = LazyListDeinitAction { [weak source] in
                destructions += 1
                source?.close()
            }
            XCTAssertTrue(
                source.replaceData([1], id: \.self) { [witness] value in
                    withExtendedLifetime(witness) {}
                    return value
                })
        }
        install()
        XCTAssertEqual(destructions, 0)
        XCTAssertFalse(source.replaceData([2], id: \.self, rowContent: { $0 }))
        XCTAssertEqual(destructions, 1)
        XCTAssertTrue(source.isClosed)
        XCTAssertNil(source.metadata)
    }

    func testTemporaryKeyDestructionCannotPublishBeforeOrAfterTheFactory() async throws {
        for closeAfterFactory in [false, true] {
            let element = LazyListTemporaryKeyElement(value: 1)
            let source = RetainedLazyListDataSource<LazyListTemporaryKeyElement, Int>()
            var calls = 0
            XCTAssertTrue(
                source.replaceData([element], id: \.key) { [weak source] value in
                    calls += 1
                    if closeAfterFactory { value.nextKeyDestruction = { [weak source] in source?.close() } }
                    return value.value
                })
            let token = try XCTUnwrap(source.metadata?.rows.first?.token)
            let request = try XCTUnwrap(source.request(for: token))
            if !closeAfterFactory { element.nextKeyDestruction = { [weak source] in source?.close() } }
            let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
            guard case .obsolete = source.materialize(request, budget: budget) else {
                return XCTFail("Temporary-key cleanup must finish before candidate publication")
            }
            XCTAssertTrue(source.isClosed)
            XCTAssertEqual(calls, closeAfterFactory ? 1 : 0)
            XCTAssertEqual(budget.remainingElements, 0)
        }
    }

    func testOutgoingModelDestructionCannotPublishAReplacement() async {
        let source = RetainedLazyListDataSource<LazyListOwnedElement, Int>()
        var destructions = 0
        @MainActor func install() {
            let element = LazyListOwnedElement(id: 1) { [weak source] in
                destructions += 1
                source?.close()
            }
            XCTAssertTrue(source.replaceData([element], id: \.id, rowContent: { $0.id }))
        }
        install()
        XCTAssertEqual(destructions, 0)
        XCTAssertFalse(source.replaceData([LazyListOwnedElement(id: 2)], id: \.id, rowContent: { $0.id }))
        XCTAssertEqual(destructions, 1)
        XCTAssertTrue(source.isClosed)
        XCTAssertNil(source.metadata)
    }

    func testIteratorCreationAndDestructionCannotPublishMetadataAfterClose() async {
        for closeOnDestruction in [false, true] {
            let source = RetainedLazyListDataSource<Int, Int>()
            var factories = 0
            var closes = 0
            let close: @MainActor () -> Void = { [weak source] in
                closes += 1
                source?.close()
            }
            let data = LazyListIteratorCollection(
                values: [1, 2, 3], onCreate: closeOnDestruction ? nil : close,
                onDestroy: closeOnDestruction ? close : nil)
            XCTAssertFalse(
                source.replaceData(data, id: \.self) { value in
                    factories += 1
                    return value
                })
            XCTAssertEqual(closes, 1)
            XCTAssertEqual(factories, 0)
            XCTAssertTrue(source.isClosed)
            XCTAssertNil(source.metadata)
        }
    }

    func testSharedBudgetBoundsMultipleProvidersWithoutScheduling() async throws {
        let first = RetainedLazyListDataSource<Int, Int>()
        let second = RetainedLazyListDataSource<Int, Int>()
        XCTAssertTrue(first.replaceData([1], id: \.self, rowContent: { $0 }))
        XCTAssertTrue(second.replaceData([2], id: \.self, rowContent: { $0 }))
        let firstRequest = try XCTUnwrap(first.request(for: try XCTUnwrap(first.metadata?.rows.first?.token)))
        let secondRequest = try XCTUnwrap(second.request(for: try XCTUnwrap(second.metadata?.rows.first?.token)))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        XCTAssertTrue(budget.consumeRound())
        XCTAssertNotNil(builtRow(first.materialize(firstRequest, budget: budget)))
        guard case .budgetExhausted = second.materialize(secondRequest, budget: budget) else {
            return XCTFail("The budget is shared, not reset per provider")
        }
        XCTAssertEqual(budget.completion(hasPendingWork: true), .budgetExhausted)
        XCTAssertEqual(budget.completion(hasPendingWork: false), .complete)
        XCTAssertFalse(budget.consumeRound())
    }

    func testBudgetLimitsRejectNegativesAndReportRemainingWorkExplicitly() async throws {
        XCTAssertNil(RetainedLazyListWorkBudget(elementLimit: -1, roundLimit: 1))
        XCTAssertNil(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: -1))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 2, roundLimit: 2))
        XCTAssertEqual(budget.completion(hasPendingWork: true), .workRemaining)
        XCTAssertTrue(budget.consumeRound())
        XCTAssertTrue(budget.consumeElement())
        XCTAssertEqual(budget.completion(hasPendingWork: true), .workRemaining)
        XCTAssertTrue(budget.consumeElement())
        XCTAssertFalse(budget.consumeElement())
        XCTAssertEqual(budget.completion(hasPendingWork: true), .budgetExhausted)
        XCTAssertEqual(budget.completion(hasPendingWork: false), .complete)
    }

    private func builtRow<Output>(
        _ result: RetainedLazyListMaterialization<Output>, file: StaticString = #filePath, line: UInt = #line
    ) -> RetainedLazyListBuiltRow<Output>? {
        guard case .built(let row) = result else {
            XCTFail("Expected a row construction candidate", file: file, line: line)
            return nil
        }
        return row
    }
}

private struct LazyListDescribedKey: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "same description" }
}

private struct LazyListNumericKeys {
    let narrow: Int8
    let wide: Int64
}

private final class LazyListMarker {}

@MainActor
private final class LazyListHooks {
    var keyReads = 0
    var onHash: (@MainActor () -> Void)?
    var onEquality: (@MainActor () -> Void)?

    func hash() {
        let action = onHash
        onHash = nil
        action?()
    }

    func equality() {
        let action = onEquality
        onEquality = nil
        action?()
    }
}

private struct LazyListCallbackKey: Hashable {
    let value: Int
    let hooks: LazyListHooks

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.hooks.equality() }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { hooks.hash() }
        hasher.combine(0)
    }
}

private final class LazyListReferenceElement {
    var identifier: Int
    let hooks: LazyListHooks

    init(identifier: Int, hooks: LazyListHooks) {
        self.identifier = identifier
        self.hooks = hooks
    }

    var id: Int {
        MainActor.assumeIsolated { [hooks] in hooks.keyReads += 1 }
        return identifier
    }
}

private struct LazyListReadCollection: RandomAccessCollection {
    let values: [Int]
    let onRead: @MainActor () -> Void

    var startIndex: Int { values.startIndex }
    var endIndex: Int { values.endIndex }
    func index(after index: Int) -> Int { index + 1 }
    func index(before index: Int) -> Int { index - 1 }

    subscript(position: Int) -> Int {
        MainActor.assumeIsolated { onRead() }
        return values[position]
    }
}

private final class LazyListDeinitAction {
    let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    deinit {
        MainActor.assumeIsolated { [action] in action() }
    }
}

private final class LazyListTemporaryKey: Hashable {
    let value: Int
    let onDestroy: (@MainActor () -> Void)?

    init(value: Int, onDestroy: (@MainActor () -> Void)?) {
        self.value = value
        self.onDestroy = onDestroy
    }

    static func == (lhs: LazyListTemporaryKey, rhs: LazyListTemporaryKey) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    deinit {
        MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
    }
}

private final class LazyListTemporaryKeyElement {
    let value: Int
    var nextKeyDestruction: (@MainActor () -> Void)?

    init(value: Int) {
        self.value = value
    }

    var key: LazyListTemporaryKey {
        let action = nextKeyDestruction
        nextKeyDestruction = nil
        return LazyListTemporaryKey(value: value, onDestroy: action)
    }
}

private final class LazyListOwnedElement {
    let id: Int
    let onDestroy: (@MainActor () -> Void)?

    init(id: Int, onDestroy: (@MainActor () -> Void)? = nil) {
        self.id = id
        self.onDestroy = onDestroy
    }

    deinit {
        MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
    }
}

private struct LazyListIteratorCollection: RandomAccessCollection {
    final class Iterator: IteratorProtocol {
        let values: [Int]
        let onDestroy: (@MainActor () -> Void)?
        var position = 0

        init(values: [Int], onDestroy: (@MainActor () -> Void)?) {
            self.values = values
            self.onDestroy = onDestroy
        }

        func next() -> Int? {
            guard position < values.count else { return nil }
            defer { position += 1 }
            return values[position]
        }

        deinit {
            MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
        }
    }

    let values: [Int]
    let onCreate: (@MainActor () -> Void)?
    let onDestroy: (@MainActor () -> Void)?
    var startIndex: Int { values.startIndex }
    var endIndex: Int { values.endIndex }
    func index(after index: Int) -> Int { index + 1 }
    func index(before index: Int) -> Int { index - 1 }
    subscript(position: Int) -> Int { values[position] }

    func makeIterator() -> Iterator {
        MainActor.assumeIsolated { onCreate?() }
        return Iterator(values: values, onDestroy: onDestroy)
    }
}
