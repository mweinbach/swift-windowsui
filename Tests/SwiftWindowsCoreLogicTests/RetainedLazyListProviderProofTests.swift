import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Native generation freshness is not node, focus, or UI Automation authority.
/// These fixtures do not enable the deferred provider in public List.
@MainActor
final class RetainedLazyListProviderProofTests: XCTestCase {
    func testProofReadsDoNotCallProviderRequirementsOrAuthoredCode() async throws {
        let hooks = LazyListProofHooks()
        let element = LazyListProofElement(identifier: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListProofElement, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(
            source.replaceData([element], id: \.id) { value in
                hooks.factoryCalls += 1
                return value.identifier
            })
        let spy = LazyListProofProviderSpy(source: source)
        let provider: any RetainedLazyListProvider<Int> = spy
        let metadata = try XCTUnwrap(provider.metadata)
        let request = try XCTUnwrap(provider.request(for: try XCTUnwrap(metadata.rows.first?.token)))
        let generation = metadata.generation
        requireSendable(generation)
        requireSendable(request)
        requireSendable(request.token)

        for expectedCurrent in [true, false] {
            if !expectedCurrent { source.close() }
            let counts = hooks.counts
            for _ in 0..<64 {
                XCTAssertEqual(generation.isCurrent, expectedCurrent)
                XCTAssertEqual(request.isGenerationCurrent, expectedCurrent)
            }
            XCTAssertEqual(hooks.counts, counts)
            XCTAssertEqual(spy.calls, 2, "Proof reads must not consult a protocol getter or method")
        }
    }

    func testSameKeyReplacementRevokesProofsWithoutChangingTheirEquality() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(source.replaceData([1], id: \.self, rowContent: { $0 }))
        let old = try currentProofs(source)
        let generationCopy = old.generation
        let requestCopy = old.request
        XCTAssertTrue(old.generation.isCurrent)
        XCTAssertTrue(old.request.isGenerationCurrent)

        XCTAssertTrue(source.replaceData([1], id: \.self, rowContent: { $0 + 1 }))
        let fresh = try currentProofs(source)
        XCTAssertEqual(old.request.token, fresh.request.token)
        XCTAssertNotEqual(old.generation, fresh.generation)
        XCTAssertEqual(old.generation, generationCopy)
        XCTAssertEqual(old.request, requestCopy)
        XCTAssertFalse(old.generation.isCurrent)
        XCTAssertFalse(generationCopy.isCurrent)
        XCTAssertFalse(old.request.isGenerationCurrent)
        XCTAssertFalse(requestCopy.isGenerationCurrent)
        XCTAssertTrue(fresh.generation.isCurrent)
        XCTAssertTrue(fresh.request.isGenerationCurrent)
    }

    func testReplacementRevokesProofBeforeAuthoredCollectionAccess() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(source.replaceData([1], id: \.self, rowContent: { $0 }))
        let old = try currentProofs(source)
        var observed: [Bool] = []
        let replacement = LazyListProofReadCollection(values: [2]) {
            observed.append(old.generation.isCurrent)
            observed.append(old.request.isGenerationCurrent)
        }

        XCTAssertTrue(source.replaceData(replacement, id: \.self, rowContent: { $0 }))
        XCTAssertEqual(observed, [false, false])
        XCTAssertFalse(old.generation.isCurrent)
        XCTAssertFalse(old.request.isGenerationCurrent)
        let fresh = try currentProofs(source)
        XCTAssertTrue(fresh.generation.isCurrent)
        XCTAssertTrue(fresh.request.isGenerationCurrent)
    }

    func testNestedReplacementDuringMetadataBuildCannotReviveTheOldProof() async throws {
        let source = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(source.replaceData([1], id: \.self, rowContent: { $0 }))
        let old = try currentProofs(source)
        var observed: [Bool] = []
        var nestedReplacement: Bool?
        let replacement = LazyListProofReadCollection(values: [2]) {
            observed.append(old.generation.isCurrent)
            nestedReplacement = source.replaceData([3], id: \.self, rowContent: { $0 })
            observed.append(old.request.isGenerationCurrent)
        }

        XCTAssertFalse(source.replaceData(replacement, id: \.self, rowContent: { $0 }))
        XCTAssertEqual(nestedReplacement, false)
        XCTAssertEqual(observed, [false, false])
        XCTAssertNil(source.metadata)
        XCTAssertTrue(source.replaceData([1], id: \.self, rowContent: { $0 }))
        let fresh = try currentProofs(source)
        XCTAssertTrue(fresh.generation.isCurrent)
        XCTAssertFalse(old.generation.isCurrent)
        XCTAssertFalse(old.request.isGenerationCurrent)
    }

    func testRejectedReplacementInHashOrEqualityRevokesProofBeforeReturning() async throws {
        for useEquality in [false, true] {
            let hooks = LazyListProofHooks()
            let key = LazyListProofKey(value: 1, hooks: hooks)
            let source = RetainedLazyListDataSource<LazyListProofKey, Int>()
            defer { withExtendedLifetime(source) {} }
            XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { $0.value }))
            let old = try currentProofs(source)
            var observed: [Bool] = []
            var nestedReplacement: Bool?
            let replace: @MainActor () -> Void = {
                observed.append(old.generation.isCurrent)
                nestedReplacement = source.replaceData([key], id: \.self, rowContent: { $0.value })
                observed.append(old.generation.isCurrent)
                observed.append(old.request.isGenerationCurrent)
            }
            if useEquality { hooks.onEquality = replace } else { hooks.onHash = replace }

            XCTAssertNil(source.token(for: .init(key)))
            XCTAssertEqual(nestedReplacement, false)
            XCTAssertEqual(observed, [true, false, false])
            XCTAssertNil(source.metadata)
            XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { $0.value }))
            XCTAssertFalse(old.generation.isCurrent)
            XCTAssertFalse(old.request.isGenerationCurrent)
            XCTAssertTrue(try currentProofs(source).generation.isCurrent)
        }
    }

    func testFactoryReplacementRevokesProofBeforeDiscardedOutputDestruction() async throws {
        let source = RetainedLazyListDataSource<Int, LazyListProofPayload>()
        defer { withExtendedLifetime(source) {} }
        var generation: RetainedLazyListGeneration?
        var request: RetainedLazyListRowRequest?
        var nestedReplacement: Bool?
        var observed: [Bool] = []
        var calls = 0
        XCTAssertTrue(
            source.replaceData([1], id: \.self) { [weak source] _ in
                calls += 1
                nestedReplacement = source?.replaceData([2], id: \.self) { _ in LazyListProofPayload() }
                return LazyListProofPayload {
                    observed.append(generation?.isCurrent == true)
                    observed.append(request?.isGenerationCurrent == true)
                }
            })
        let proof = try currentProofs(source)
        generation = proof.generation
        request = proof.request
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))

        guard case .obsolete = source.materialize(proof.request, budget: budget) else {
            return XCTFail("A nested replacement must revoke the discarded candidate's generation")
        }
        XCTAssertEqual(nestedReplacement, false)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(observed, [false, false])
        XCTAssertFalse(proof.generation.isCurrent)
        XCTAssertFalse(proof.request.isGenerationCurrent)
        XCTAssertEqual(budget.remainingElements, 0)
    }

    func testCloseAndReplacementRevokeProofBeforeOwnedPayloadDestruction() async throws {
        for shouldClose in [false, true] {
            let source = RetainedLazyListDataSource<LazyListProofOwnedElement, Int>()
            defer { withExtendedLifetime(source) {} }
            var generation: RetainedLazyListGeneration?
            var request: RetainedLazyListRowRequest?
            var observed: [Bool] = []
            weak var releasedElement: LazyListProofOwnedElement?
            weak var releasedKey: LazyListProofOwnedKey?
            weak var releasedFactoryPayload: LazyListProofPayload?
            let inspect: @MainActor () -> Void = {
                observed.append(generation?.isCurrent == true)
                observed.append(request?.isGenerationCurrent == true)
            }
            @MainActor func install() {
                let key = LazyListProofOwnedKey(value: 1, onDestroy: inspect)
                let element = LazyListProofOwnedElement(id: key, onDestroy: inspect)
                let payload = LazyListProofPayload(onDestroy: inspect)
                releasedElement = element
                releasedKey = key
                releasedFactoryPayload = payload
                XCTAssertTrue(
                    source.replaceData([element], id: \.id) { [payload] value in
                        withExtendedLifetime(payload) {}
                        return value.id.value
                    })
            }
            install()
            let old = try currentProofs(source)
            generation = old.generation
            request = old.request
            XCTAssertTrue(observed.isEmpty)

            if shouldClose {
                source.close()
            } else {
                let replacement = LazyListProofOwnedElement(id: .init(value: 2))
                XCTAssertTrue(source.replaceData([replacement], id: \.id, rowContent: { $0.id.value }))
            }
            XCTAssertNil(releasedElement)
            XCTAssertNil(releasedKey)
            XCTAssertNil(releasedFactoryPayload)
            XCTAssertEqual(observed, Array(repeating: false, count: 6))
            XCTAssertFalse(old.generation.isCurrent)
            XCTAssertFalse(old.request.isGenerationCurrent)
            if !shouldClose { XCTAssertTrue(try currentProofs(source).generation.isCurrent) }
        }
    }

    func testProviderDeathRevokesProofBeforeModelKeyAndFactoryPayloadCleanup() async throws {
        var source: RetainedLazyListDataSource<LazyListProofOwnedElement, Int>? = .init()
        weak var releasedSource = source
        weak var releasedElement: LazyListProofOwnedElement?
        weak var releasedKey: LazyListProofOwnedKey?
        weak var releasedFactoryPayload: LazyListProofPayload?
        var generation: RetainedLazyListGeneration?
        var request: RetainedLazyListRowRequest?
        var observed: [Bool] = []
        let inspect: @MainActor () -> Void = {
            observed.append(generation?.isCurrent == true)
            observed.append(request?.isGenerationCurrent == true)
        }
        @MainActor func install(_ owner: RetainedLazyListDataSource<LazyListProofOwnedElement, Int>) throws {
            let key = LazyListProofOwnedKey(value: 1, onDestroy: inspect)
            let element = LazyListProofOwnedElement(id: key, onDestroy: inspect)
            let payload = LazyListProofPayload(onDestroy: inspect)
            releasedElement = element
            releasedKey = key
            releasedFactoryPayload = payload
            XCTAssertTrue(
                owner.replaceData([element], id: \.id) { [payload] value in
                    withExtendedLifetime(payload) {}
                    return value.id.value
                })
            let proof = try currentProofs(owner)
            generation = proof.generation
            request = proof.request
        }
        try install(try XCTUnwrap(source))
        let retainedGeneration = try XCTUnwrap(generation)
        let retainedRequest = try XCTUnwrap(request)
        let retainedToken = retainedRequest.token
        withExtendedLifetime(source) {
            XCTAssertTrue(observed.isEmpty)
            XCTAssertTrue(retainedGeneration.isCurrent)
        }

        source = nil
        XCTAssertNil(releasedSource)
        XCTAssertNil(releasedElement)
        XCTAssertNil(releasedKey)
        XCTAssertNil(releasedFactoryPayload)
        XCTAssertEqual(observed, Array(repeating: false, count: 6))
        XCTAssertFalse(retainedGeneration.isCurrent)
        XCTAssertFalse(retainedRequest.isGenerationCurrent)
        XCTAssertEqual(retainedToken, retainedRequest.token)
    }

    func testPayloadFreeProviderReleaseOnAnotherActorRevokesRetainedProofs() async throws {
        var source: RetainedLazyListDataSource<Int, Int>? = .init()
        XCTAssertTrue(try XCTUnwrap(source).replaceData([1], id: \.self, rowContent: { $0 }))
        let proof = try currentProofs(try XCTUnwrap(source))
        let releaseOwner = LazyListProofReleaseOwner(source: try XCTUnwrap(source))
        source = nil
        XCTAssertTrue(proof.generation.isCurrent)
        XCTAssertTrue(proof.request.isGenerationCurrent)

        await releaseOwner.release()
        XCTAssertFalse(proof.generation.isCurrent)
        XCTAssertFalse(proof.request.isGenerationCurrent)
    }

    func testDeadSourceProofCannotReviveForAnotherSourceWithTheSameKey() async throws {
        var source: RetainedLazyListDataSource<Int, Int>? = .init()
        XCTAssertTrue(try XCTUnwrap(source).replaceData([1], id: \.self, rowContent: { $0 }))
        let old = try currentProofs(try XCTUnwrap(source))
        source = nil
        XCTAssertFalse(old.generation.isCurrent)
        XCTAssertFalse(old.request.isGenerationCurrent)

        for _ in 0..<16 {
            let fresh = RetainedLazyListDataSource<Int, Int>()
            defer { withExtendedLifetime(fresh) {} }
            XCTAssertTrue(fresh.replaceData([1], id: \.self, rowContent: { $0 }))
            let proof = try currentProofs(fresh)
            XCTAssertNotEqual(proof.generation, old.generation)
            XCTAssertNotEqual(proof.request.token, old.request.token)
            XCTAssertNil(fresh.request(for: old.request.token))
            XCTAssertTrue(proof.generation.isCurrent)
            XCTAssertFalse(old.generation.isCurrent)
            XCTAssertFalse(old.request.isGenerationCurrent)
        }
    }

    func testClosingOneProviderDoesNotRevokeAnotherProvidersProofs() async throws {
        let first = RetainedLazyListDataSource<Int, Int>()
        let second = RetainedLazyListDataSource<Int, Int>()
        defer { withExtendedLifetime((first, second)) {} }
        XCTAssertTrue(first.replaceData([1], id: \.self, rowContent: { $0 }))
        XCTAssertTrue(second.replaceData([1], id: \.self, rowContent: { $0 }))
        let firstProof = try currentProofs(first)
        let secondProof = try currentProofs(second)
        first.close()
        XCTAssertFalse(firstProof.generation.isCurrent)
        XCTAssertFalse(firstProof.request.isGenerationCurrent)
        XCTAssertTrue(secondProof.generation.isCurrent)
        XCTAssertTrue(secondProof.request.isGenerationCurrent)
    }

    func testDetectedIDDriftBeforeFactoryRevokesProofWithoutBuilding() async throws {
        let hooks = LazyListProofHooks()
        let element = LazyListProofElement(identifier: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListProofElement, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(
            source.replaceData([element], id: \.id) { value in
                hooks.factoryCalls += 1
                return value.identifier
            })
        let old = try currentProofs(source)
        element.identifier = 2
        let reads = hooks.keyReads
        XCTAssertTrue(old.generation.isCurrent, "The primitive does not inspect unreported model changes")
        XCTAssertTrue(old.request.isGenerationCurrent)
        XCTAssertEqual(hooks.keyReads, reads)
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))

        guard case .obsolete = source.materialize(old.request, budget: budget) else {
            return XCTFail("Materialization must detect the changed ID")
        }
        XCTAssertEqual(hooks.factoryCalls, 0)
        XCTAssertFalse(old.generation.isCurrent)
        XCTAssertFalse(old.request.isGenerationCurrent)
        element.identifier = 1
        XCTAssertFalse(old.generation.isCurrent)
        XCTAssertFalse(old.request.isGenerationCurrent)
        XCTAssertTrue(source.replaceData([element], id: \.id, rowContent: { $0.identifier }))
        XCTAssertTrue(try currentProofs(source).generation.isCurrent)
        XCTAssertFalse(old.generation.isCurrent)
    }

    func testDetectedIDDriftAfterFactoryRevokesProofBeforeOutputCleanup() async throws {
        let hooks = LazyListProofHooks()
        let element = LazyListProofElement(identifier: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListProofElement, LazyListProofPayload>()
        defer { withExtendedLifetime(source) {} }
        var generation: RetainedLazyListGeneration?
        var request: RetainedLazyListRowRequest?
        var observed: [Bool] = []
        XCTAssertTrue(
            source.replaceData([element], id: \.id) { value in
                hooks.factoryCalls += 1
                value.identifier = 2
                return LazyListProofPayload {
                    observed.append(generation?.isCurrent == true)
                    observed.append(request?.isGenerationCurrent == true)
                }
            })
        let old = try currentProofs(source)
        generation = old.generation
        request = old.request
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))

        guard case .obsolete = source.materialize(old.request, budget: budget) else {
            return XCTFail("Detected post-factory ID drift must revoke its candidate proof")
        }
        XCTAssertEqual(observed, [false, false])
        XCTAssertEqual(hooks.factoryCalls, 1)
        XCTAssertFalse(old.generation.isCurrent)
        XCTAssertFalse(old.request.isGenerationCurrent)
        element.identifier = 1
        XCTAssertFalse(old.generation.isCurrent)
    }

    func testTemporaryKeyCleanupCanRevokeProofBeforeOrAfterFactory() async throws {
        for closeAfterFactory in [false, true] {
            let element = LazyListProofTemporaryKeyElement(value: 1)
            let source = RetainedLazyListDataSource<LazyListProofTemporaryKeyElement, Int>()
            defer { withExtendedLifetime(source) {} }
            var generation: RetainedLazyListGeneration?
            var request: RetainedLazyListRowRequest?
            var observed: [Bool] = []
            var calls = 0
            let close: @MainActor () -> Void = { [weak source] in
                source?.close()
                observed.append(generation?.isCurrent == true)
                observed.append(request?.isGenerationCurrent == true)
            }
            XCTAssertTrue(
                source.replaceData([element], id: \.key) { value in
                    calls += 1
                    if closeAfterFactory { value.nextKeyDestruction = close }
                    return value.value
                })
            let old = try currentProofs(source)
            generation = old.generation
            request = old.request
            if !closeAfterFactory { element.nextKeyDestruction = close }
            let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))

            guard case .obsolete = source.materialize(old.request, budget: budget) else {
                return XCTFail("Key cleanup must invalidate the proof before any candidate is accepted")
            }
            XCTAssertEqual(observed, [false, false])
            XCTAssertEqual(calls, closeAfterFactory ? 1 : 0)
            XCTAssertFalse(old.generation.isCurrent)
            XCTAssertFalse(old.request.isGenerationCurrent)
        }
    }

    func testReadOnlyReentryAndBudgetExhaustionDoNotRevokeAValidProof() async throws {
        let hooks = LazyListProofHooks()
        let key = LazyListProofKey(value: 1, hooks: hooks)
        let source = RetainedLazyListDataSource<LazyListProofKey, Int>()
        defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(source.replaceData([key], id: \.self, rowContent: { $0.value }))
        let proof = try currentProofs(source)
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 0, roundLimit: 1))
        var nestedWasRefused = false
        var observed: [Bool] = []
        hooks.onHash = {
            observed.append(proof.generation.isCurrent)
            if case .reentrant = source.materialize(proof.request, budget: budget) {
                nestedWasRefused = true
            }
            observed.append(proof.request.isGenerationCurrent)
        }

        XCTAssertEqual(source.token(for: .init(key)), proof.request.token)
        XCTAssertTrue(nestedWasRefused)
        XCTAssertEqual(observed, [true, true])
        guard case .budgetExhausted = source.materialize(proof.request, budget: budget) else {
            return XCTFail("An exhausted budget must refuse work without revoking its generation")
        }
        XCTAssertTrue(proof.generation.isCurrent)
        XCTAssertTrue(proof.request.isGenerationCurrent)
    }

    private func currentProofs<Element, Output>(
        _ source: RetainedLazyListDataSource<Element, Output>
    ) throws -> (generation: RetainedLazyListGeneration, request: RetainedLazyListRowRequest) {
        let metadata = try XCTUnwrap(source.metadata)
        let token = try XCTUnwrap(metadata.rows.first?.token)
        let request = try XCTUnwrap(source.request(for: token))
        return (metadata.generation, request)
    }

    private func requireSendable<Value: Sendable>(_ value: Value) {
        withExtendedLifetime(value) {}
    }
}

@MainActor
private final class LazyListProofProviderSpy<Element, Output>: RetainedLazyListProvider {
    typealias RowContent = Output
    let source: RetainedLazyListDataSource<Element, Output>
    private(set) var calls = 0

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
private final class LazyListProofHooks {
    var keyReads = 0
    var hashCalls = 0
    var equalityCalls = 0
    var factoryCalls = 0
    var onHash: (@MainActor () -> Void)?
    var onEquality: (@MainActor () -> Void)?

    var counts: [Int] { [keyReads, hashCalls, equalityCalls, factoryCalls] }

    func read() {
        keyReads += 1
    }

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

private struct LazyListProofKey: Hashable {
    let value: Int
    let hooks: LazyListProofHooks

    static func == (lhs: Self, rhs: Self) -> Bool {
        let hooks = lhs.hooks
        MainActor.assumeIsolated { [hooks] in hooks.equality() }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { [hooks] in hooks.hash() }
        hasher.combine(0)
    }
}

private final class LazyListProofElement {
    var identifier: Int
    let hooks: LazyListProofHooks

    init(identifier: Int, hooks: LazyListProofHooks) {
        self.identifier = identifier
        self.hooks = hooks
    }

    var id: LazyListProofKey {
        MainActor.assumeIsolated { [hooks] in hooks.read() }
        return LazyListProofKey(value: identifier, hooks: hooks)
    }
}

private struct LazyListProofReadCollection<Element>: RandomAccessCollection {
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

private final class LazyListProofPayload {
    let onDestroy: (@MainActor () -> Void)?

    init(onDestroy: (@MainActor () -> Void)? = nil) {
        self.onDestroy = onDestroy
    }

    deinit {
        MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
    }
}

private final class LazyListProofOwnedKey: Hashable {
    let value: Int
    let onDestroy: (@MainActor () -> Void)?

    init(value: Int, onDestroy: (@MainActor () -> Void)? = nil) {
        self.value = value
        self.onDestroy = onDestroy
    }

    static func == (lhs: LazyListProofOwnedKey, rhs: LazyListProofOwnedKey) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    deinit {
        MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
    }
}

private final class LazyListProofOwnedElement {
    let id: LazyListProofOwnedKey
    let onDestroy: (@MainActor () -> Void)?

    init(id: LazyListProofOwnedKey, onDestroy: (@MainActor () -> Void)? = nil) {
        self.id = id
        self.onDestroy = onDestroy
    }

    deinit {
        MainActor.assumeIsolated { [onDestroy] in onDestroy?() }
    }
}

private final class LazyListProofTemporaryKeyElement {
    let value: Int
    var nextKeyDestruction: (@MainActor () -> Void)?

    init(value: Int) {
        self.value = value
    }

    var key: LazyListProofOwnedKey {
        let action = nextKeyDestruction
        nextKeyDestruction = nil
        return LazyListProofOwnedKey(value: value, onDestroy: action)
    }
}

/// No actor-assuming application destructor is used by the foreign-actor case.
private actor LazyListProofReleaseOwner {
    private var source: RetainedLazyListDataSource<Int, Int>?

    init(source: RetainedLazyListDataSource<Int, Int>) {
        self.source = source
    }

    func release() {
        source = nil
    }
}
