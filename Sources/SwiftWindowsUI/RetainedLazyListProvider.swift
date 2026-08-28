import SwiftWindowsCore

/// These identities contain no application payload and never own a provider.
/// Retaining a token keeps its identity from being reused after its source dies.
fileprivate final class RetainedLazyListIdentity: Sendable {}

/// A logical item, not a ViewNode, state owner, or UI Automation authorization.
/// Hashing a token cannot call application Hashable implementations.
package struct RetainedLazyListRowToken: Hashable, Sendable {
    private let owner: RetainedLazyListIdentity
    private let item: RetainedLazyListIdentity

    fileprivate init(owner: RetainedLazyListIdentity) {
        self.owner = owner
        self.item = RetainedLazyListIdentity()
    }

    fileprivate func belongs(to owner: RetainedLazyListIdentity) -> Bool {
        self.owner === owner
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.owner === rhs.owner && lhs.item === rhs.item
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(owner))
        hasher.combine(ObjectIdentifier(item))
    }
}

/// A fresh identity, rather than a wrapping integer, revokes prior requests.
package struct RetainedLazyListGeneration: Equatable, Sendable {
    private let owner: RetainedLazyListIdentity
    fileprivate let intent: RetainedLazyListIdentity

    fileprivate init(owner: RetainedLazyListIdentity, intent: RetainedLazyListIdentity) {
        self.owner = owner
        self.intent = intent
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.owner === rhs.owner && lhs.intent === rhs.intent
    }
}

/// One data element can project zero or multiple leaf rows later. Its ordinal
/// is a model position; it is not a flattened view slot or a measured height.
package struct RetainedLazyListRowMetadata {
    package let token: RetainedLazyListRowToken
    package let key: RetainedViewIdentity.Key
    package let occurrence: Int
    package let sourceIndex: Int
}

/// O(data count) logical metadata. The source does not construct or cache row
/// outputs, nodes, tasks, renderer resources, or mounted state here. Application
/// model values and Hashable IDs can themselves retain arbitrary payloads.
package struct RetainedLazyListMetadata {
    package let generation: RetainedLazyListGeneration
    package let rows: [RetainedLazyListRowMetadata]
}

package struct RetainedLazyListRowRequest: Equatable, Sendable {
    package let token: RetainedLazyListRowToken
    package let sourceIndex: Int
    fileprivate let generation: RetainedLazyListGeneration
}

package struct RetainedLazyListBuiltRow<RowContent> {
    package let request: RetainedLazyListRowRequest
    package let content: RowContent

    package init(request: RetainedLazyListRowRequest, content: RowContent) {
        self.request = request
        self.content = content
    }
}

package enum RetainedLazyListMaterialization<RowContent> {
    case built(RetainedLazyListBuiltRow<RowContent>)
    case obsolete
    case reentrant
    case budgetExhausted
}

/// The facade can supply AnyView content while a future retained adapter can
/// supply nodes. This contract imports neither facade nor renderer types.
/// A successful build is only a candidate: the caller still checks its build
/// lease, request, attachment, and layout settlement before adoption or input.
@MainActor
package protocol RetainedLazyListProvider<RowContent>: AnyObject {
    associatedtype RowContent

    var metadata: RetainedLazyListMetadata? { get }
    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest?
    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool
    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<RowContent>
}

/// Shared by future layout convergence and opaque-ID searches. Consuming a
/// data element counts before its authored key getter and even when its factory
/// returns no leaves or invalidates the request. This object performs no
/// scheduling and cannot claim settlement.
@MainActor
package final class RetainedLazyListWorkBudget {
    package enum Completion: Equatable {
        case complete
        case workRemaining
        case budgetExhausted
    }

    package private(set) var remainingElements: Int
    package private(set) var remainingRounds: Int

    package init?(elementLimit: Int, roundLimit: Int) {
        guard elementLimit >= 0, roundLimit >= 0 else { return nil }
        self.remainingElements = elementLimit
        self.remainingRounds = roundLimit
    }

    /// The integration owns the round loop; materialize consumes only elements.
    package func consumeRound() -> Bool {
        guard remainingRounds > 0 else { return false }
        remainingRounds -= 1
        return true
    }

    package func consumeElement() -> Bool {
        guard remainingElements > 0 else { return false }
        remainingElements -= 1
        return true
    }

    package func completion(hasPendingWork: Bool) -> Completion {
        guard hasPendingWork else { return .complete }
        return remainingElements == 0 || remainingRounds == 0 ? .budgetExhausted : .workRemaining
    }
}

/// A data snapshot and a single factory, not a row-view cache. Model values and
/// typed IDs are O(data count); only explicit, budgeted requests call the factory.
/// Public List does not use this source yet.
@MainActor
package final class RetainedLazyListDataSource<Element, Output>: RetainedLazyListProvider {
    package typealias RowContent = Output

    private struct QualifiedKey: Hashable {
        let key: RetainedViewIdentity.Key
        let occurrence: Int
    }

    @MainActor
    private final class Configuration {
        let metadata: RetainedLazyListMetadata
        let elements: [Element]
        let tokensByKey: [QualifiedKey: RetainedLazyListRowToken]
        let positionsByToken: [RetainedLazyListRowToken: Int]
        let key: @MainActor (Element) -> RetainedViewIdentity.Key
        let content: @MainActor (Element) -> Output

        init(
            metadata: RetainedLazyListMetadata, elements: [Element],
            tokensByKey: [QualifiedKey: RetainedLazyListRowToken],
            positionsByToken: [RetainedLazyListRowToken: Int],
            key: @escaping @MainActor (Element) -> RetainedViewIdentity.Key,
            content: @escaping @MainActor (Element) -> Output
        ) {
            self.metadata = metadata
            self.elements = elements
            self.tokensByKey = tokensByKey
            self.positionsByToken = positionsByToken
            self.key = key
            self.content = content
        }
    }

    private let owner = RetainedLazyListIdentity()
    private var intent = RetainedLazyListIdentity()
    private var configuration: Configuration?
    private var isReplacingData = false
    private var isMaterializing = false
    private var isLookingUpKey = false
    package private(set) var isClosed = false

    package init() {}

    package var metadata: RetainedLazyListMetadata? {
        guard let configuration, isCommitted(configuration), !isReplacingData else { return nil }
        return configuration.metadata
    }

    /// Snapshotting collection values, key getters, equality, and hashing can
    /// run application code. A nested replacement revokes the outer intent but
    /// does not queue work or publish a partial snapshot; a fresh call is needed.
    /// A failed replacement leaves old requests unavailable until that call.
    @discardableResult
    package func replaceData<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Element, ID>, rowContent: @escaping @MainActor (Element) -> Output
    ) -> Bool where Data.Element == Element {
        guard !isClosed else { return false }
        let replacementIntent = RetainedLazyListIdentity()
        intent = replacementIntent
        guard !isReplacingData, !isMaterializing, !isLookingUpKey else { return false }
        isReplacingData = true
        defer { isReplacingData = false }

        var previous = configuration
        guard
            let next = makeConfiguration(
                data, id: id, rowContent: rowContent, previous: previous, intent: replacementIntent),
            isCurrentIntent(replacementIntent)
        else { return false }

        configuration = next
        // Do not release the outgoing factory/model payload within the stored
        // property's write access. Cleanup can close or supersede this source.
        withExtendedLifetime(previous) {}
        previous = nil
        return isCurrentIntent(replacementIntent) && configuration === next
    }

    package func token(for key: RetainedViewIdentity.Key, occurrence: Int = 0) -> RetainedLazyListRowToken? {
        guard occurrence >= 0, !isReplacingData, !isMaterializing, !isLookingUpKey,
            let configuration, isCommitted(configuration)
        else { return nil }
        isLookingUpKey = true
        defer { isLookingUpKey = false }
        let token = configuration.tokensByKey[QualifiedKey(key: key, occurrence: occurrence)]
        // Dictionary lookup may have called the authored key's hash/equality.
        guard isCommitted(configuration) else { return nil }
        return token
    }

    package func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        guard !isReplacingData, !isMaterializing, !isLookingUpKey, token.belongs(to: owner),
            let configuration, isCommitted(configuration),
            let position = configuration.positionsByToken[token]
        else { return nil }
        return RetainedLazyListRowRequest(
            token: token, sourceIndex: position, generation: configuration.metadata.generation)
    }

    package func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        guard !isReplacingData, request.token.belongs(to: owner),
            let configuration, isCommitted(configuration),
            request.generation == configuration.metadata.generation
        else { return false }
        return configuration.positionsByToken[request.token] == request.sourceIndex
    }

    package func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<Output> {
        guard !isMaterializing, !isLookingUpKey else { return .reentrant }
        guard isCurrent(request), let configuration else { return .obsolete }
        guard budget.consumeElement() else { return .budgetExhausted }
        isMaterializing = true
        defer { isMaterializing = false }

        let element = configuration.elements[request.sourceIndex]
        let keyMatches = matchesSnapshotKey(element, configuration: configuration, request: request)
        guard isCurrent(request) else { return .obsolete }
        guard keyMatches else {
            // A reference-type element changed its ID without a replacement.
            // Changing it back cannot revive this request or its old metadata.
            intent = RetainedLazyListIdentity()
            return .obsolete
        }

        let content = configuration.content(element)
        guard isCurrent(request) else { return .obsolete }
        let keyStillMatches = matchesSnapshotKey(element, configuration: configuration, request: request)
        guard isCurrent(request) else { return .obsolete }
        guard keyStillMatches else {
            intent = RetainedLazyListIdentity()
            return .obsolete
        }
        return .built(RetainedLazyListBuiltRow(request: request, content: content))
    }

    package func close() {
        guard !isClosed else { return }
        isClosed = true
        intent = RetainedLazyListIdentity()
        let previous = configuration
        configuration = nil
        withExtendedLifetime(previous) {}
    }

    private func isCurrentIntent(_ expected: RetainedLazyListIdentity) -> Bool {
        !isClosed && intent === expected
    }

    private func isCommitted(_ candidate: Configuration) -> Bool {
        !isClosed && configuration === candidate && intent === candidate.metadata.generation.intent
    }

    /// The temporary authored key is released when this helper returns. Its
    /// destruction can call application code, so callers recheck the primitive
    /// request generation afterward. IDs must still be stable for a published
    /// snapshot; this check is not observation of arbitrary model mutations.
    private func matchesSnapshotKey(
        _ element: Element, configuration: Configuration, request: RetainedLazyListRowRequest
    ) -> Bool {
        let key = configuration.key(element)
        guard isCurrent(request) else { return false }
        return key == configuration.metadata.rows[request.sourceIndex].key
    }

    private func makeConfiguration<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Element, ID>, rowContent: @escaping @MainActor (Element) -> Output,
        previous: Configuration?, intent replacementIntent: RetainedLazyListIdentity
    ) -> Configuration? where Data.Element == Element {
        var rows: [RetainedLazyListRowMetadata] = []
        var elements: [Element] = []
        var occurrences: [RetainedViewIdentity.Key: Int] = [:]
        var tokensByKey: [QualifiedKey: RetainedLazyListRowToken] = [:]
        var positionsByToken: [RetainedLazyListRowToken: Int] = [:]
        let key: @MainActor (Element) -> RetainedViewIdentity.Key = { .init($0[keyPath: id]) }
        var iterator = data.makeIterator()
        guard isCurrentIntent(replacementIntent) else { return nil }

        while isCurrentIntent(replacementIntent) {
            guard let element = iterator.next() else { break }
            guard isCurrentIntent(replacementIntent) else { return nil }
            let elementKey = key(element)
            guard isCurrentIntent(replacementIntent) else { return nil }
            let occurrence = occurrences[elementKey, default: 0]
            guard isCurrentIntent(replacementIntent), occurrence < Int.max else { return nil }
            occurrences[elementKey] = occurrence + 1
            guard isCurrentIntent(replacementIntent) else { return nil }
            let qualified = QualifiedKey(key: elementKey, occurrence: occurrence)
            let previousToken = previous?.tokensByKey[qualified]
            guard isCurrentIntent(replacementIntent) else { return nil }
            let token = previousToken ?? RetainedLazyListRowToken(owner: owner)
            tokensByKey[qualified] = token
            guard isCurrentIntent(replacementIntent) else { return nil }
            let position = rows.count
            positionsByToken[token] = position
            rows.append(.init(token: token, key: elementKey, occurrence: occurrence, sourceIndex: position))
            elements.append(element)
        }

        guard isCurrentIntent(replacementIntent) else { return nil }
        return Configuration(
            metadata: RetainedLazyListMetadata(
                generation: .init(owner: owner, intent: replacementIntent), rows: rows),
            elements: elements, tokensByKey: tokensByKey, positionsByToken: positionsByToken,
            key: key, content: rowContent)
    }
}
