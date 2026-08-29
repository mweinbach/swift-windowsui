import SwiftWindowsCore

/// These identities contain no application payload and never own a provider.
/// Retaining a token keeps its identity from being reused after its source dies.
fileprivate final class RetainedLazyListIdentity: Sendable {}

/// Weak proof reads may retain this empty marker, never the provider itself.
fileprivate final class RetainedLazyListProviderLifetime: Sendable {}

@MainActor
fileprivate final class RetainedLazyListGenerationValidity {
    private weak var lifetime: RetainedLazyListProviderLifetime?
    private var isRevoked = false

    init(lifetime: RetainedLazyListProviderLifetime) {
        self.lifetime = lifetime
    }

    var isCurrent: Bool {
        !isRevoked && lifetime != nil
    }

    func revoke() {
        isRevoked = true
    }
}

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
    private let validity: RetainedLazyListGenerationValidity

    fileprivate init(
        owner: RetainedLazyListIdentity, intent: RetainedLazyListIdentity,
        validity: RetainedLazyListGenerationValidity
    ) {
        self.owner = owner
        self.intent = intent
        self.validity = validity
    }

    /// Reads only native proof state. It does not call a provider or authored ID
    /// getter, observe unreported model changes, or authorize node adoption/input.
    @MainActor
    package var isCurrent: Bool {
        validity.isCurrent
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.owner === rhs.owner && lhs.intent === rhs.intent
    }

    fileprivate func belongs(to owner: RetainedLazyListIdentity) -> Bool {
        self.owner === owner
    }
}

/// Native provenance for an independently staged source. It retains neither
/// provider nor application keys, and never authorizes attachment or adoption.
@MainActor
package final class RetainedLazyListProviderContinuation {
    package let predecessorGeneration: RetainedLazyListGeneration
    package let successorGeneration: RetainedLazyListGeneration
    private let owner: RetainedLazyListIdentity
    private let predecessorIdentity: ObjectIdentifier
    private let successorIdentity: ObjectIdentifier

    fileprivate init(
        owner: RetainedLazyListIdentity, predecessor: AnyObject, successor: AnyObject,
        predecessorGeneration: RetainedLazyListGeneration,
        successorGeneration: RetainedLazyListGeneration
    ) {
        self.owner = owner
        predecessorIdentity = ObjectIdentifier(predecessor)
        successorIdentity = ObjectIdentifier(successor)
        self.predecessorGeneration = predecessorGeneration
        self.successorGeneration = successorGeneration
    }

    package var isCurrent: Bool {
        predecessorGeneration.belongs(to: owner) && successorGeneration.belongs(to: owner)
            && predecessorGeneration.isCurrent && successorGeneration.isCurrent
    }

    /// The generation proofs also reject address reuse after either source
    /// dies. Comparing the providers themselves invokes no protocol getter.
    func matches(predecessor: AnyObject, successor: AnyObject) -> Bool {
        isCurrent && predecessorIdentity == ObjectIdentifier(predecessor)
            && successorIdentity == ObjectIdentifier(successor)
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

    /// Generation freshness only; attachment, build, and input checks are separate.
    @MainActor
    package var isGenerationCurrent: Bool {
        generation.isCurrent
    }
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

/// The facade can supply AnyView content or project directly to retained nodes.
/// This contract imports neither facade nor renderer types.
/// A successful build is only a candidate: the caller still checks its build
/// lease, request, attachment, and layout settlement before adoption or input.
@MainActor
package protocol RetainedLazyListProvider<RowContent>: AnyObject {
    associatedtype RowContent

    var metadata: RetainedLazyListMetadata? { get }
    func token(for key: RetainedViewIdentity.Key, occurrence: Int) -> RetainedLazyListRowToken?
    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest?
    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool
    func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity?
    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<RowContent>
}

/// Only the final framework data source implements this module-internal
/// capability. Logical accessibility reads must not call an arbitrary provider
/// getter, authored key, or factory before its adapter has a prepared snapshot.
@MainActor
protocol RetainedLazyListNativeTokenMembershipProvider: AnyObject {
    func containsCommittedToken(
        _ token: RetainedLazyListRowToken, in generation: RetainedLazyListGeneration
    ) -> Bool
}

extension RetainedLazyListProvider {
    /// Opaque providers need not implement authored-key search. A concrete
    /// data source uses its checked typed index without building row content.
    package func token(for key: RetainedViewIdentity.Key, occurrence: Int) -> RetainedLazyListRowToken? {
        nil
    }

    /// Providers must opt in to captured row identity before checked adoption.
    /// A prefix authenticates row ancestry, not a leaf's structural suffix or
    /// the request's current lifetime. Comparisons and cleanup can call out.
    package func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity? {
        nil
    }
}

/// A single debit for one provider, request, and shared convergence budget.
/// This receipt contains only native proofs; it never keeps a source or its
/// model, key getter, row factory, or facade resolution alive.
@MainActor
package final class RetainedLazyListPrepaidElement {
    fileprivate enum Phase {
        case reserved
        case consumed
        case abandoned
    }

    package let request: RetainedLazyListRowRequest
    fileprivate let providerIdentity: RetainedLazyListIdentity
    fileprivate weak var budget: RetainedLazyListWorkBudget?
    fileprivate weak var reservation: RetainedLazyListElementReservation?
    fileprivate var phase: Phase = .reserved

    fileprivate init(
        request: RetainedLazyListRowRequest, provider: RetainedLazyListIdentity,
        budget: RetainedLazyListWorkBudget, reservation: RetainedLazyListElementReservation
    ) {
        self.request = request
        providerIdentity = provider
        self.budget = budget
        self.reservation = reservation
    }

    /// This is reservation freshness, not descriptor, attachment, or adoption
    /// authority. The adapter must retain all of its original admission checks.
    package var isCurrent: Bool {
        phase == .reserved && request.isGenerationCurrent && budget != nil
            && reservation?.current === self
    }

    /// A rejected attempt remains charged. Cleanup cannot revive a receipt or
    /// clear a different receipt installed on either provider.
    package func abandon() {
        guard phase == .reserved else { return }
        phase = .abandoned
        if reservation?.current === self { reservation?.current = nil }
    }
}

@MainActor
fileprivate final class RetainedLazyListElementReservation {
    weak var current: RetainedLazyListPrepaidElement?

    var hasCurrent: Bool { current != nil }

    func abandonCurrent() { current?.abandon() }

    func claim(
        _ receipt: RetainedLazyListPrepaidElement, request: RetainedLazyListRowRequest,
        provider: RetainedLazyListIdentity, budget: RetainedLazyListWorkBudget
    ) -> Bool {
        guard receipt.isCurrent, receipt.reservation === self, current === receipt,
            receipt.providerIdentity === provider, receipt.request == request, receipt.budget === budget
        else {
            receipt.abandon()
            return false
        }
        receipt.phase = .consumed
        current = nil
        return true
    }
}

/// Managed adapters opt in to prepayment before facade key/equality resolution.
/// The existing provider protocol and untagged materialization path stay valid.
@MainActor
package protocol RetainedLazyListPrepaidProvider<RowContent>: RetainedLazyListProvider {
    func prepay(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListPrepaidElement?
    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget,
        prepaid: RetainedLazyListPrepaidElement
    ) -> RetainedLazyListMaterialization<RowContent>
}

/// Shared by layout convergence and opaque-ID searches. Consuming a
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
/// Managed List descriptors stage snapshots before Runtime selects row work.
@MainActor
package final class RetainedLazyListDataSource<Element, Output>: RetainedLazyListPrepaidProvider,
    RetainedLazyListNativeTokenMembershipProvider
{
    package typealias RowContent = Output

    private struct QualifiedKey: Hashable {
        let key: RetainedViewIdentity.Key
        let occurrence: Int
    }

    private struct ManagedKeyEntry {
        let key: RetainedViewIdentity.Key
        var tokens: [RetainedLazyListRowToken]
    }

    /// Buckets hash native integers only. Typed key comparisons are explicit
    /// callouts, and occurrence counters are native array counts.
    private struct ManagedKeyIndex {
        var buckets: [Int: [Int]] = [:]
        var entries: [ManagedKeyEntry] = []
    }

    private enum KeyIndex {
        case ordinary([QualifiedKey: RetainedLazyListRowToken])
        case managed(ManagedKeyIndex)
    }

    /// This finite record is never stored in Configuration or its factory.
    /// A later lookup uses its current generation, not an expired build scope.
    private enum KeyAdmission {
        case metadata(
            generation: RetainedLazyListGeneration, scope: RetainedLazyListDescriptorBuildScope)
        case staged(
            generation: RetainedLazyListGeneration, predecessor: RetainedLazyListGeneration,
            scope: RetainedLazyListDescriptorBuildScope)
        case provider(RetainedLazyListGeneration)
    }

    private enum ManagedKeyLookup {
        case found(Int)
        case missing
        case rejected
    }

    private enum ManagedElementStep {
        case appended
        case finished
        case rejected
    }

    private enum Factory {
        case plain(@MainActor (Element) -> Output)
        case identified(
            identityRoot: RetainedViewIdentity,
            content: @MainActor (Element, RetainedViewIdentity) -> Output)
    }

    @MainActor
    private final class Configuration {
        let metadata: RetainedLazyListMetadata
        let elements: [Element]
        let keyIndex: KeyIndex
        let positionsByToken: [RetainedLazyListRowToken: Int]
        let key: @MainActor (Element) -> RetainedViewIdentity.Key
        let factory: Factory

        init(
            metadata: RetainedLazyListMetadata, elements: [Element],
            keyIndex: KeyIndex,
            positionsByToken: [RetainedLazyListRowToken: Int],
            key: @escaping @MainActor (Element) -> RetainedViewIdentity.Key,
            factory: Factory
        ) {
            self.metadata = metadata
            self.elements = elements
            self.keyIndex = keyIndex
            self.positionsByToken = positionsByToken
            self.key = key
            self.factory = factory
        }
    }

    private let owner: RetainedLazyListIdentity
    private var intent = RetainedLazyListIdentity()
    private var lifetime: RetainedLazyListProviderLifetime? = .init()
    private var generationValidity: RetainedLazyListGenerationValidity?
    private var configuration: Configuration?
    private var isReplacingData = false
    private var isMaterializing = false
    private var isLookingUpKey = false
    private let elementReservation = RetainedLazyListElementReservation()
    package private(set) var isClosed = false
    package private(set) var predecessorContinuation: RetainedLazyListProviderContinuation?

    package init() { owner = RetainedLazyListIdentity() }

    private init(owner: RetainedLazyListIdentity) { self.owner = owner }

    deinit {
        // Revoke weak lifetime proofs before automatic model/factory teardown.
        // The marker is Sendable and has no callback-bearing payload.
        lifetime = nil
    }

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
        _ data: Data, id: KeyPath<Element, ID>,
        descriptorBuildScope: RetainedLazyListDescriptorBuildScope? = nil,
        rowContent: @escaping @MainActor (Element) -> Output
    ) -> Bool where Data.Element == Element {
        if let descriptorBuildScope {
            return replaceManagedData(
                data, id: id, factory: .plain(rowContent), scope: descriptorBuildScope)
        }
        return replaceData(data, id: id, factory: .plain(rowContent))
    }

    /// Captures one ancestor path for the generation. Each requested prefix is
    /// derived from the captured typed ID and duplicate occurrence before the
    /// factory runs; it never rereads an ID to invent another identity matcher.
    /// The facade must append its canonical leaf/branch path through its build
    /// context. A flattened leaf index cannot replace that structural suffix.
    @discardableResult
    package func replaceData<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Element, ID>, identityRoot: RetainedViewIdentity,
        descriptorBuildScope: RetainedLazyListDescriptorBuildScope? = nil,
        rowContent: @escaping @MainActor (Element, RetainedViewIdentity) -> Output
    ) -> Bool where Data.Element == Element {
        if let descriptorBuildScope {
            return replaceManagedData(
                data, id: id, factory: .identified(identityRoot: identityRoot, content: rowContent),
                scope: descriptorBuildScope)
        }
        return replaceData(data, id: id, factory: .identified(identityRoot: identityRoot, content: rowContent))
    }

    /// Build a separate snapshot while the accepted source remains available.
    /// Native tokens survive checked typed-key/occurrence matches, but requests,
    /// generation validity, reservations, model values, and factories do not.
    package func stagedReplacement<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Element, ID>, identityRoot: RetainedViewIdentity,
        descriptorBuildScope: RetainedLazyListDescriptorBuildScope,
        rowContent: @escaping @MainActor (Element, RetainedViewIdentity) -> Output
    ) -> RetainedLazyListDataSource<Element, Output>? where Data.Element == Element {
        let successor = makeStagedReplacement(
            data, id: id, factory: .identified(identityRoot: identityRoot, content: rowContent),
            scope: descriptorBuildScope)
        // All old-key, iterator, and failed-configuration cleanup has unwound.
        guard descriptorBuildScope.canConstructDescriptors,
            let successor, successor.predecessorContinuation?.isCurrent == true
        else { return nil }
        return successor
    }

    @inline(never)
    private func makeStagedReplacement<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Element, ID>, factory: Factory,
        scope: RetainedLazyListDescriptorBuildScope
    ) -> RetainedLazyListDataSource<Element, Output>? where Data.Element == Element {
        guard scope.canConstructDescriptors, !isReplacingData, !isMaterializing, !isLookingUpKey,
            !elementReservation.hasCurrent, let previous = configuration, isCommitted(previous)
        else { return nil }
        let predecessorGeneration = previous.metadata.generation
        let successor = RetainedLazyListDataSource<Element, Output>(owner: owner)
        guard let lifetime = successor.lifetime else { return nil }
        let validity = RetainedLazyListGenerationValidity(lifetime: lifetime)
        successor.generationValidity = validity
        let generation = RetainedLazyListGeneration(owner: owner, intent: successor.intent, validity: validity)
        let admission = KeyAdmission.staged(
            generation: generation, predecessor: predecessorGeneration, scope: scope)
        successor.isReplacingData = true
        var didPublish = false
        defer {
            if !didPublish { validity.revoke() }
            successor.isReplacingData = false
        }
        guard successor.isCurrent(admission),
            let next = successor.makeManagedConfiguration(
                data, id: id, factory: factory, previous: previous, generation: generation, admission: admission),
            successor.isCurrent(admission), isCommitted(previous)
        else { return nil }
        successor.configuration = next
        successor.predecessorContinuation = RetainedLazyListProviderContinuation(
            owner: owner, predecessor: self, successor: successor,
            predecessorGeneration: predecessorGeneration, successorGeneration: generation)
        didPublish = true
        return successor
    }

    private func replaceData<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Element, ID>, factory: Factory
    ) -> Bool where Data.Element == Element {
        guard !isClosed else { return false }
        generationValidity?.revoke()
        predecessorContinuation = nil
        elementReservation.abandonCurrent()
        let replacementIntent = RetainedLazyListIdentity()
        intent = replacementIntent
        guard !isReplacingData, !isMaterializing, !isLookingUpKey, let lifetime else { return false }
        let replacementValidity = RetainedLazyListGenerationValidity(lifetime: lifetime)
        generationValidity = replacementValidity
        isReplacingData = true
        defer { isReplacingData = false }

        var previous = configuration
        guard
            let next = makeConfiguration(
                data, id: id, factory: factory, previous: previous, intent: replacementIntent,
                validity: replacementValidity),
            isCurrentIntent(replacementIntent)
        else { return false }

        configuration = next
        // Do not release the outgoing factory/model payload within the stored
        // property's write access. Cleanup can close or supersede this source.
        withExtendedLifetime(previous) {}
        previous = nil
        return isCurrentIntent(replacementIntent) && configuration === next
    }

    @inline(never)
    private func replaceManagedData<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Element, ID>, factory: Factory,
        scope: RetainedLazyListDescriptorBuildScope
    ) -> Bool where Data.Element == Element {
        guard !isClosed, scope.canConstructDescriptors else { return false }
        generationValidity?.revoke()
        predecessorContinuation = nil
        elementReservation.abandonCurrent()
        let replacementIntent = RetainedLazyListIdentity()
        intent = replacementIntent
        guard !isReplacingData, !isMaterializing, !isLookingUpKey, let lifetime else { return false }
        let validity = RetainedLazyListGenerationValidity(lifetime: lifetime)
        generationValidity = validity
        let generation = RetainedLazyListGeneration(owner: owner, intent: replacementIntent, validity: validity)
        let admission = KeyAdmission.metadata(generation: generation, scope: scope)
        isReplacingData = true
        var didPublish = false
        defer {
            if !didPublish { validity.revoke() }
            isReplacingData = false
        }

        var previous = configuration
        guard isCurrent(admission),
            let next = makeManagedConfiguration(
                data, id: id, factory: factory, previous: previous, generation: generation, admission: admission),
            isCurrent(admission)
        else { return false }

        configuration = next
        // Releasing the displaced model/factory is an explicit callout boundary,
        // outside the stored property's write. A close cannot publish this new
        // generation merely because the provider itself remains open.
        withExtendedLifetime(previous) {}
        previous = nil
        guard isCurrent(admission), configuration === next else { return false }
        didPublish = true
        return true
    }

    package func token(for key: RetainedViewIdentity.Key, occurrence: Int = 0) -> RetainedLazyListRowToken? {
        guard occurrence >= 0, !isReplacingData, !isMaterializing, !isLookingUpKey, !elementReservation.hasCurrent,
            let configuration, isCommitted(configuration)
        else { return nil }
        isLookingUpKey = true
        defer { isLookingUpKey = false }
        let token: RetainedLazyListRowToken?
        switch configuration.keyIndex {
        case .ordinary(let tokens):
            token = tokens[QualifiedKey(key: key, occurrence: occurrence)]
        case .managed(let index):
            token = managedToken(
                for: key, occurrence: occurrence, in: index,
                admission: .provider(configuration.metadata.generation))
        }
        // Both paths may have called the authored key's hash/equality. Managed
        // lookups also check between individual invocations, without the finite
        // descriptor scope used to construct their metadata.
        guard isCommitted(configuration) else { return nil }
        return token
    }

    /// Presence in the exact committed source, not permission to construct a
    /// row or revive an old physical receipt. The existing token index hashes
    /// only native identities and needs no additional per-record storage.
    func containsCommittedToken(
        _ token: RetainedLazyListRowToken, in generation: RetainedLazyListGeneration
    ) -> Bool {
        guard generation.isCurrent, !isReplacingData, !isMaterializing, !isLookingUpKey,
            !elementReservation.hasCurrent, token.belongs(to: owner),
            let configuration, isCommitted(configuration), configuration.metadata.generation == generation
        else { return false }
        return configuration.positionsByToken[token] != nil
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

    /// Copies only the requested captured path, with no authored getter, hash,
    /// equality, or factory call and no O(data count) prefix cache. The returned
    /// value can retain application keys; requests and generation proofs cannot.
    /// Callers bound queries and recheck native admission after using/releasing it.
    package func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity? {
        guard !isReplacingData, !isMaterializing, !isLookingUpKey,
            isCurrent(request), let configuration,
            case .identified(let root, _) = configuration.factory
        else { return nil }
        let prefix = Self.rowIdentityPrefix(root: root, row: configuration.metadata.rows[request.sourceIndex])
        guard isCurrent(request) else { return nil }
        return prefix
    }

    package func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<Output> {
        guard !isMaterializing, !isLookingUpKey, !elementReservation.hasCurrent else { return .reentrant }
        guard isCurrent(request), let configuration else { return .obsolete }
        guard budget.consumeElement() else { return .budgetExhausted }
        isMaterializing = true
        defer { isMaterializing = false }
        return materializeContent(request, configuration: configuration)
    }

    package func prepay(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListPrepaidElement? {
        guard !isReplacingData, !isMaterializing, !isLookingUpKey, !elementReservation.hasCurrent,
            isCurrent(request), let configuration,
            configuration.elements.indices.contains(request.sourceIndex)
        else { return nil }
        guard budget.consumeElement() else { return nil }
        let receipt = RetainedLazyListPrepaidElement(
            request: request, provider: owner, budget: budget, reservation: elementReservation)
        elementReservation.current = receipt
        return receipt
    }

    package func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget,
        prepaid: RetainedLazyListPrepaidElement
    ) -> RetainedLazyListMaterialization<Output> {
        guard !isMaterializing, !isLookingUpKey else {
            prepaid.abandon()
            return .reentrant
        }
        guard isCurrent(request), let configuration,
            elementReservation.claim(prepaid, request: request, provider: owner, budget: budget)
        else {
            prepaid.abandon()
            return .obsolete
        }
        // The receipt was charged before facade resolution and consumed before
        // any key or content call. This overload never charges a second element.
        isMaterializing = true
        defer { isMaterializing = false }
        return materializeContent(request, configuration: configuration)
    }

    @inline(never)
    private func materializeContent(
        _ request: RetainedLazyListRowRequest, configuration: Configuration
    ) -> RetainedLazyListMaterialization<Output> {
        let element = configuration.elements[request.sourceIndex]
        let keyMatches = matchesSnapshotKey(element, configuration: configuration, request: request)
        guard isCurrent(request) else { return .obsolete }
        guard keyMatches else {
            // A reference-type element changed its ID without a replacement.
            // Changing it back cannot revive this request or its old metadata.
            generationValidity?.revoke()
            intent = RetainedLazyListIdentity()
            return .obsolete
        }

        let content = makeContent(element, configuration: configuration, request: request)
        guard isCurrent(request) else { return .obsolete }
        let keyStillMatches = matchesSnapshotKey(element, configuration: configuration, request: request)
        guard isCurrent(request) else { return .obsolete }
        guard keyStillMatches else {
            generationValidity?.revoke()
            intent = RetainedLazyListIdentity()
            return .obsolete
        }
        return .built(RetainedLazyListBuiltRow(request: request, content: content))
    }

    package func close() {
        guard !isClosed else { return }
        generationValidity?.revoke()
        predecessorContinuation = nil
        elementReservation.abandonCurrent()
        isClosed = true
        intent = RetainedLazyListIdentity()
        let previous = configuration
        configuration = nil
        withExtendedLifetime(previous) {}
    }

    private func isCurrentIntent(_ expected: RetainedLazyListIdentity) -> Bool {
        !isClosed && intent === expected
    }

    private func isCurrent(_ admission: KeyAdmission) -> Bool {
        switch admission {
        case .metadata(let generation, let scope):
            return isCurrentIntent(generation.intent) && generation.isCurrent && scope.canConstructDescriptors
        case .staged(let generation, let predecessor, let scope):
            return isCurrentIntent(generation.intent) && generation.isCurrent && predecessor.isCurrent
                && scope.canConstructDescriptors
        case .provider(let generation):
            return isCurrentIntent(generation.intent) && generation.isCurrent
        }
    }

    private func isCommitted(_ candidate: Configuration) -> Bool {
        !isClosed && configuration === candidate && intent === candidate.metadata.generation.intent
            && candidate.metadata.generation.isCurrent
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

    /// Scope the temporary prefix before the caller's primitive post-factory
    /// checks. Captured keys and the ancestor path remain configuration-owned;
    /// the source keeps no separate cache of assembled prefixes.
    private func makeContent(
        _ element: Element, configuration: Configuration, request: RetainedLazyListRowRequest
    ) -> Output {
        switch configuration.factory {
        case .plain(let content):
            return content(element)
        case .identified(let root, let content):
            let prefix = Self.rowIdentityPrefix(root: root, row: configuration.metadata.rows[request.sourceIndex])
            return content(element, prefix)
        }
    }

    private static func rowIdentityPrefix(
        root: RetainedViewIdentity, row: RetainedLazyListRowMetadata
    ) -> RetainedViewIdentity {
        root.appending(contentsOf: [.role(.row), .keyed(row.key), .occurrence(row.occurrence)])
    }

    private func makeConfiguration<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Element, ID>, factory: Factory,
        previous: Configuration?, intent replacementIntent: RetainedLazyListIdentity,
        validity: RetainedLazyListGenerationValidity
    ) -> Configuration? where Data.Element == Element {
        let generation = RetainedLazyListGeneration(owner: owner, intent: replacementIntent, validity: validity)
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
            let previousToken = previousToken(for: qualified, in: previous, generation: generation)
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
            metadata: RetainedLazyListMetadata(generation: generation, rows: rows),
            elements: elements, keyIndex: .ordinary(tokensByKey), positionsByToken: positionsByToken,
            key: key, factory: factory)
    }

    @inline(never)
    private func previousToken(
        for qualified: QualifiedKey, in previous: Configuration?, generation: RetainedLazyListGeneration
    ) -> RetainedLazyListRowToken? {
        guard let previous else { return nil }
        switch previous.keyIndex {
        case .ordinary(let tokens):
            return tokens[qualified]
        case .managed(let index):
            return managedToken(
                for: qualified.key, occurrence: qualified.occurrence, in: index, admission: .provider(generation))
        }
    }

    /// All iterator and temporary-key cleanup finishes in this helper before
    /// the replacement entry point checks its original admission and publishes.
    @inline(never)
    private func makeManagedConfiguration<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Element, ID>, factory: Factory, previous: Configuration?,
        generation: RetainedLazyListGeneration, admission: KeyAdmission
    ) -> Configuration? where Data.Element == Element {
        guard isCurrent(admission), let previousIndex = managedIndex(of: previous, admission: admission),
            isCurrent(admission)
        else { return nil }
        var rows: [RetainedLazyListRowMetadata] = []
        var elements: [Element] = []
        var index = ManagedKeyIndex()
        var positionsByToken: [RetainedLazyListRowToken: Int] = [:]
        let key: @MainActor (Element) -> RetainedViewIdentity.Key = { .init($0[keyPath: id]) }
        guard isCurrent(admission) else { return nil }
        var iterator = data.makeIterator()
        guard isCurrent(admission) else { return nil }

        while true {
            guard isCurrent(admission) else { return nil }
            let step = appendManagedElement(
                from: &iterator, key: key, previous: previousIndex, index: &index, rows: &rows,
                elements: &elements, positionsByToken: &positionsByToken, admission: admission)
            // The helper returns only a native enum. Its element, key, and
            // failed-result temporaries have unwound before any next callout.
            guard isCurrent(admission) else { return nil }
            switch step {
            case .appended:
                continue
            case .finished:
                return Configuration(
                    metadata: RetainedLazyListMetadata(generation: generation, rows: rows),
                    elements: elements, keyIndex: .managed(index), positionsByToken: positionsByToken,
                    key: key, factory: factory)
            case .rejected:
                return nil
            }
        }
    }

    @inline(never)
    private func appendManagedElement<Iterator: IteratorProtocol>(
        from iterator: inout Iterator, key: @MainActor (Element) -> RetainedViewIdentity.Key,
        previous: ManagedKeyIndex, index: inout ManagedKeyIndex,
        rows: inout [RetainedLazyListRowMetadata], elements: inout [Element],
        positionsByToken: inout [RetainedLazyListRowToken: Int], admission: KeyAdmission
    ) -> ManagedElementStep where Iterator.Element == Element {
        guard isCurrent(admission) else { return .rejected }
        let next = iterator.next()
        guard isCurrent(admission) else { return .rejected }
        guard let element = next else { return .finished }
        guard isCurrent(admission) else { return .rejected }
        let elementKey = key(element)
        guard isCurrent(admission), let hash = managedHash(elementKey, admission: admission),
            isCurrent(admission)
        else { return .rejected }

        let lookup = managedEntry(for: elementKey, hash: hash, in: index, admission: admission)
        guard isCurrent(admission) else { return .rejected }
        let entryIndex: Int?
        let occurrence: Int
        switch lookup {
        case .found(let existing):
            entryIndex = existing
            occurrence = index.entries[existing].tokens.count
        case .missing:
            entryIndex = nil
            occurrence = 0
        case .rejected:
            return .rejected
        }
        guard occurrence < Int.max else { return .rejected }

        let reused = managedToken(
            for: elementKey, hash: hash, occurrence: occurrence, in: previous, admission: admission)
        guard isCurrent(admission) else { return .rejected }
        let token = reused ?? RetainedLazyListRowToken(owner: owner)
        if let entryIndex {
            index.entries[entryIndex].tokens.append(token)
        } else {
            let nextIndex = index.entries.count
            index.entries.append(ManagedKeyEntry(key: elementKey, tokens: [token]))
            index.buckets[hash, default: []].append(nextIndex)
        }
        guard isCurrent(admission) else { return .rejected }
        let position = rows.count
        positionsByToken[token] = position
        rows.append(.init(token: token, key: elementKey, occurrence: occurrence, sourceIndex: position))
        elements.append(element)
        return .appended
    }

    /// An ordinary previous snapshot is converted without invoking its authored
    /// dictionary keys. Reuse still compares typed key plus exact occurrence.
    @inline(never)
    private func managedIndex(of previous: Configuration?, admission: KeyAdmission) -> ManagedKeyIndex? {
        guard isCurrent(admission) else { return nil }
        guard let previous else { return ManagedKeyIndex() }
        switch previous.keyIndex {
        case .managed(let index):
            return index
        case .ordinary:
            var index = ManagedKeyIndex()
            for row in previous.metadata.rows {
                guard isCurrent(admission), appendManagedMetadata(row, to: &index, admission: admission),
                    isCurrent(admission)
                else { return nil }
            }
            return isCurrent(admission) ? index : nil
        }
    }

    @inline(never)
    private func appendManagedMetadata(
        _ row: RetainedLazyListRowMetadata, to index: inout ManagedKeyIndex, admission: KeyAdmission
    ) -> Bool {
        guard isCurrent(admission), let hash = managedHash(row.key, admission: admission),
            isCurrent(admission)
        else { return false }
        let lookup = managedEntry(for: row.key, hash: hash, in: index, admission: admission)
        guard isCurrent(admission) else { return false }
        switch lookup {
        case .found(let existing):
            guard row.occurrence == index.entries[existing].tokens.count else { return false }
            index.entries[existing].tokens.append(row.token)
        case .missing:
            guard row.occurrence == 0 else { return false }
            let nextIndex = index.entries.count
            index.entries.append(ManagedKeyEntry(key: row.key, tokens: [row.token]))
            index.buckets[hash, default: []].append(nextIndex)
        case .rejected:
            return false
        }
        return isCurrent(admission)
    }

    @inline(never)
    private func managedToken(
        for key: RetainedViewIdentity.Key, occurrence: Int, in index: ManagedKeyIndex, admission: KeyAdmission
    ) -> RetainedLazyListRowToken? {
        guard isCurrent(admission), let hash = managedHash(key, admission: admission), isCurrent(admission) else {
            return nil
        }
        return managedToken(for: key, hash: hash, occurrence: occurrence, in: index, admission: admission)
    }

    @inline(never)
    private func managedToken(
        for key: RetainedViewIdentity.Key, hash: Int, occurrence: Int,
        in index: ManagedKeyIndex, admission: KeyAdmission
    ) -> RetainedLazyListRowToken? {
        guard occurrence >= 0, isCurrent(admission) else { return nil }
        let lookup = managedEntry(for: key, hash: hash, in: index, admission: admission)
        guard isCurrent(admission), case .found(let entry) = lookup,
            index.entries[entry].tokens.indices.contains(occurrence)
        else { return nil }
        return index.entries[entry].tokens[occurrence]
    }

    @inline(never)
    private func managedEntry(
        for key: RetainedViewIdentity.Key, hash: Int, in index: ManagedKeyIndex, admission: KeyAdmission
    ) -> ManagedKeyLookup {
        guard isCurrent(admission) else { return .rejected }
        let bucket = index.buckets[hash] ?? []
        for candidate in bucket {
            guard isCurrent(admission),
                let matches = managedKeysEqual(key, index.entries[candidate].key, admission: admission),
                isCurrent(admission)
            else { return .rejected }
            if matches { return .found(candidate) }
        }
        return isCurrent(admission) ? .missing : .rejected
    }

    @inline(never)
    private func managedHash(_ key: RetainedViewIdentity.Key, admission: KeyAdmission) -> Int? {
        guard isCurrent(admission) else { return nil }
        var hasher = Hasher()
        key.hash(into: &hasher)
        guard isCurrent(admission) else { return nil }
        return hasher.finalize()
    }

    @inline(never)
    private func managedKeysEqual(
        _ lhs: RetainedViewIdentity.Key, _ rhs: RetainedViewIdentity.Key, admission: KeyAdmission
    ) -> Bool? {
        guard isCurrent(admission) else { return nil }
        let matches = lhs == rhs
        guard isCurrent(admission) else { return nil }
        return matches
    }
}
