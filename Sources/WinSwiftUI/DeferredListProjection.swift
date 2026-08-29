import Foundation
import SwiftWindowsCore
import SwiftWindowsUI

/// One retained data collection and one factory, shared by every logical row
/// in a ForEach. Metadata collection never invokes the factory. Only an
/// explicitly eager consumer populates the compatibility cache; viewport
/// requests do not accumulate previously visited View values here.
@MainActor
struct DeferredViewListData {
    struct Element {
        let key: RetainedViewIdentity.Key
        let implicitSelectionTag: AnyHashable
        let occurrence: Int
    }

    @MainActor
    enum Edit {
        case delete(((IndexSet) -> Void)?)
        case move(((IndexSet, Int) -> Void)?)
        case insert([String], (Int, [NSItemProvider]) -> Void)
        case drop(String, ([Any], Int) -> Void)

        func applying(to view: AnyView) -> AnyView {
            view.mappingViewIdentity { content in
                switch self {
                case .delete(let action):
                    return AnyView(DynamicListEditMetadataView(content: content, deleteAction: .some(action)))
                case .move(let action):
                    return AnyView(DynamicListEditMetadataView(content: content, moveAction: .some(action)))
                case .insert(let identifiers, let action):
                    return AnyView(
                        DynamicListEditMetadataView(
                            content: content, insertContentTypes: identifiers, insertAction: action))
                case .drop(let type, let action):
                    return AnyView(
                        DynamicListEditMetadataView(content: content, dropPayloadType: type, dropAction: action))
                }
            }
        }
    }

    @MainActor
    private final class Storage {
        let rowFactory: (Int) -> [AnyView]
        let validateSource: (Int, ViewListProjectionActivity) -> Bool
        let generation: DeferredViewListGeneration
        private var eagerRows: [AnyView]?

        init(
            generation: DeferredViewListGeneration,
            validateSource: @escaping (Int, ViewListProjectionActivity) -> Bool,
            rowFactory: @escaping (Int) -> [AnyView]
        ) {
            self.generation = generation
            self.validateSource = validateSource
            self.rowFactory = rowFactory
        }

        func materializedRows(count: Int) -> [AnyView] {
            guard generation.isCurrent else { return [] }
            if let eagerRows { return eagerRows }
            let activity = ViewListProjectionActivity()
            var rows: [AnyView] = []
            for ordinal in 0..<count {
                guard activity.isCurrent, generation.isCurrent else {
                    generation.revoke()
                    return []
                }
                rows.append(contentsOf: rowFactory(ordinal))
            }
            guard activity.isCurrent, generation.isCurrent else {
                generation.revoke()
                return []
            }
            eagerRows = rows
            return rows
        }
    }

    let elements: [Element]
    let contentType: ObjectIdentifier
    let isValid: Bool
    private let storage: Storage
    private let sourceGenerations: [DeferredViewListGeneration]
    private var edits: [Edit] = []

    var isCurrent: Bool {
        isValid && storage.generation.isCurrent && sourceGenerations.allSatisfy { $0.isCurrent }
    }

    func revoke() { storage.generation.revoke() }

    private struct Metadata<ID: Hashable> {
        let identifiers: [ID]
        let elements: [Element]
        let sourceGenerations: [DeferredViewListGeneration]
    }

    init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Data.Element, ID>, contentType: ObjectIdentifier,
        rowContent: @escaping (Data.Element) -> [AnyView]
    ) {
        let activity = ViewListProjectionActivity()
        let metadata = Self.collectMetadata(data, id: id, activity: activity)
        let identifiers = metadata.identifiers
        let sourceGenerations = metadata.sourceGenerations
        let isValid = activity.isCurrent && sourceGenerations.allSatisfy { $0.isCurrent }
        self.isValid = isValid
        self.elements = isValid ? metadata.elements : []
        self.contentType = contentType
        self.sourceGenerations = sourceGenerations
        let generation = DeferredViewListGeneration(isCurrent: isValid)
        self.storage = Storage(
            generation: generation,
            validateSource: { ordinal, activity in
                let isCurrent = {
                    activity.isCurrent && generation.isCurrent && sourceGenerations.allSatisfy { $0.isCurrent }
                }
                guard isCurrent(), identifiers.indices.contains(ordinal) else {
                    generation.revoke()
                    activity.reject()
                    return false
                }
                let valid = Self.validateSourceElement(
                    in: data, ordinal: ordinal, count: identifiers.count,
                    id: id, capturedID: identifiers[ordinal], isCurrent: isCurrent)
                // Model/index/key temporaries have left the helper before this
                // original lookup is checked. Cleanup cannot hide reentry.
                guard valid, isCurrent() else {
                    generation.revoke()
                    activity.reject()
                    return false
                }
                return true
            },
            rowFactory: { ordinal in
                guard generation.isCurrent, identifiers.indices.contains(ordinal) else { return [] }
                let activity = ViewListProjectionActivity()
                let isCurrent = {
                    activity.isCurrent && generation.isCurrent && sourceGenerations.allSatisfy { $0.isCurrent }
                }
                guard isCurrent() else {
                    generation.revoke()
                    return []
                }
                let elementID = identifiers[ordinal]
                guard
                    let element = Self.checkedSourceElement(
                        in: data, ordinal: ordinal, count: identifiers.count,
                        id: id, capturedID: elementID, isCurrent: isCurrent),
                    isCurrent()
                else {
                    generation.revoke()
                    return []
                }
                let authored = rowContent(element)
                guard isCurrent() else {
                    generation.revoke()
                    return []
                }
                guard
                    Self.validateSourceElement(
                        in: data, ordinal: ordinal, count: identifiers.count,
                        id: id, capturedID: elementID, isCurrent: isCurrent),
                    isCurrent()
                else {
                    generation.revoke()
                    return []
                }
                let rows = normalizedProjectedViewList(authored)
                guard isCurrent() else {
                    generation.revoke()
                    return []
                }
                var result: [AnyView] = []
                for (outputIndex, view) in rows.enumerated() {
                    guard isCurrent() else {
                        generation.revoke()
                        return []
                    }
                    let row = view.ensuringViewIdentitySlot(outputIndex).mappingViewIdentity { content in
                        AnyView(
                            DynamicListEditMetadataView(
                                content: AnyView(content.implicitForEachScrollTarget(elementID, index: outputIndex)),
                                dynamicContentIndex: ordinal))
                    }
                    .prefixedViewIdentity([.keyed(RetainedViewIdentity.Key(elementID))])
                    result.append(row)
                }
                guard isCurrent() else {
                    generation.revoke()
                    return []
                }
                guard
                    Self.validateSourceElement(
                        in: data, ordinal: ordinal, count: identifiers.count,
                        id: id, capturedID: elementID, isCurrent: isCurrent),
                    isCurrent()
                else {
                    generation.revoke()
                    return []
                }
                return result
            })
    }

    /// Returns only model data. The native provider's immutable aggregate
    /// identity cannot prove that a reference-backed source still carries the
    /// ID captured before an authored row body or component was entered.
    @inline(never)
    private static func checkedSourceElement<Data: RandomAccessCollection, ID: Hashable>(
        in data: Data, ordinal: Int, count expectedCount: Int,
        id: KeyPath<Data.Element, ID>, capturedID: ID, isCurrent: () -> Bool
    ) -> Data.Element? {
        guard isCurrent() else { return nil }
        let count = data.count
        guard isCurrent(), count == expectedCount, ordinal >= 0, ordinal < count else { return nil }
        let startIndex = data.startIndex
        guard isCurrent() else { return nil }
        let endIndex = data.endIndex
        guard isCurrent() else { return nil }
        let candidate = data.index(startIndex, offsetBy: ordinal, limitedBy: endIndex)
        guard isCurrent(), let index = candidate else { return nil }
        let isEnd = index == endIndex
        guard isCurrent(), !isEnd else { return nil }
        let element = data[index]
        guard isCurrent() else { return nil }
        let currentID = element[keyPath: id]
        guard isCurrent() else { return nil }
        let matches = RetainedViewIdentity.Key(currentID).checkedEquals(
            RetainedViewIdentity.Key(capturedID), isCurrent: isCurrent)
        guard isCurrent(), matches == true else { return nil }
        if let validated = element as? any DeferredListElementValidation {
            let valid = validated.validateDeferredListElement()
            guard isCurrent(), valid else { return nil }
        }
        return element
    }

    /// The optional model and all index/key payloads are destroyed before the
    /// caller checks its original activity. No row View is constructed here.
    @inline(never)
    private static func validateSourceElement<Data: RandomAccessCollection, ID: Hashable>(
        in data: Data, ordinal: Int, count expectedCount: Int,
        id: KeyPath<Data.Element, ID>, capturedID: ID, isCurrent: () -> Bool
    ) -> Bool {
        checkedSourceElement(
            in: data, ordinal: ordinal, count: expectedCount,
            id: id, capturedID: capturedID, isCurrent: isCurrent) != nil
    }

    /// The initializer checks its original receipt after this helper releases
    /// iterator state and hash buckets, before publishing the retained factory.
    @inline(never)
    private static func collectMetadata<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Data.Element, ID>, activity: ViewListProjectionActivity
    ) -> Metadata<ID> {
        var identifiers: [ID] = []
        var elements: [Element] = []
        var sourceGenerations: [DeferredViewListGeneration] = []
        var sourceGenerationIDs: Set<ObjectIdentifier> = []
        var occurrences = ManagedKeyedMap<RetainedViewIdentity.Key, Int>()
        var iterator = activity.isCurrent ? data.makeIterator() : nil
        while activity.isCurrent {
            let next = iterator?.next()
            guard activity.isCurrent, let value = next else { break }
            let identifier = value[keyPath: id]
            guard activity.isCurrent else { break }
            if let validated = value as? any DeferredListElementValidation {
                let generation = validated.deferredListGeneration
                guard activity.isCurrent else { break }
                if sourceGenerationIDs.insert(ObjectIdentifier(generation)).inserted {
                    sourceGenerations.append(generation)
                }
            }
            let key = RetainedViewIdentity.Key(identifier)
            let occurrence = occurrences[key, while: { activity.isCurrent }] ?? 0
            guard activity.isCurrent else { break }
            occurrences[key, while: { activity.isCurrent }] = occurrence + 1
            guard activity.isCurrent else { break }
            identifiers.append(identifier)
            elements.append(Element(key: key, implicitSelectionTag: AnyHashable(identifier), occurrence: occurrence))
        }
        return Metadata(identifiers: identifiers, elements: elements, sourceGenerations: sourceGenerations)
    }

    func appending(_ edit: Edit) -> DeferredViewListData {
        var result = self
        result.edits.append(edit)
        return result
    }

    /// Explicit array/stack projection retains the historical once-only
    /// evaluation of authored row factories, including across edit modifiers.
    func materializedRows() -> [AnyView] {
        let activity = ViewListProjectionActivity()
        guard isCurrent, activity.isCurrent else { return [] }
        let rows = storage.materializedRows(count: elements.count)
        guard isCurrent, activity.isCurrent else {
            revoke()
            return []
        }
        let result = applyingEdits(to: rows, activity: activity)
        guard isCurrent, activity.isCurrent else {
            revoke()
            return []
        }
        return result
    }

    func rowViews(for ordinal: Int) -> [AnyView] {
        let activity = ViewListProjectionActivity()
        guard isCurrent, activity.isCurrent, elements.indices.contains(ordinal) else { return [] }
        let rows = storage.rowFactory(ordinal)
        guard isCurrent, activity.isCurrent else {
            revoke()
            return []
        }
        let result = applyingEdits(to: rows, activity: activity)
        guard isCurrent, activity.isCurrent else {
            revoke()
            return []
        }
        return result
    }

    /// Recheck the original source after an authored component/node boundary.
    /// Each call starts a new metadata lookup after legitimate child state
    /// publications, then keeps that lookup unchanged through every callback.
    /// Supplying context also gives binding-source validators that exact row's
    /// admission instead of whichever ambient build happens to be active.
    func validateSource(
        for ordinal: Int, context: ViewBuildContext? = ViewBuildContextScope.current
    ) -> Bool {
        if let context {
            return ViewBuildContextScope.withCurrent(context) { validateSourceInCurrentContext(for: ordinal) }
        }
        return validateSourceInCurrentContext(for: ordinal)
    }

    private func validateSourceInCurrentContext(for ordinal: Int) -> Bool {
        guard elements.indices.contains(ordinal) else { return false }
        let activity = ViewListProjectionActivity()
        guard isCurrent, activity.isCurrent else {
            revoke()
            activity.reject()
            return false
        }
        let valid = storage.validateSource(ordinal, activity)
        guard valid, isCurrent, activity.isCurrent else {
            revoke()
            activity.reject()
            return false
        }
        return true
    }

    @inline(never)
    private func applyingEdits(to rows: [AnyView], activity: ViewListProjectionActivity) -> [AnyView] {
        var result = rows
        for edit in edits {
            var decorated: [AnyView] = []
            for view in result {
                guard activity.isCurrent else { return [] }
                decorated.append(edit.applying(to: view))
            }
            result = decorated
        }
        return activity.isCurrent ? result : []
    }
}

/// A List owns this aggregate instead of an array of materialized dynamic
/// rows. Static authored leaves are retained directly. Every ForEach contributes
/// a single segment and lightweight metadata for its model elements.
///
/// Identities and returned View prefixes are relative to the authored List
/// content. The native provider owns its List/row/keyed namespace; rowViews
/// supplies the authored path beneath that namespace. The facade must not
/// prepend the authored path a second time before building the returned views.
@MainActor
struct DeferredListProjection {
    struct Element {
        let segmentIndex: Int
        let sourceOrdinal: Int
        let identity: RetainedViewIdentity
        let implicitSelectionTag: AnyHashable?
    }

    private enum Segment {
        case authored(AnyView)
        case data(DeferredViewListData, prefix: [RetainedViewIdentity.Segment])
    }

    private struct Snapshot {
        let elements: [Element]
        let segments: [Segment]
        let containsDeferredData: Bool
        let rejected: Bool
    }

    let elements: [Element]
    let containsDeferredData: Bool
    let isValid: Bool
    private let segments: [Segment]

    var count: Int { elements.count }
    var segmentCount: Int { segments.count }
    var isCurrent: Bool {
        isValid
            && segments.allSatisfy { segment in
                switch segment {
                case .authored: return true
                case .data(let data, _): return data.isCurrent
                }
            }
    }

    init<Content: View>(_ content: Content) {
        self.init(projectedViewList(content))
    }

    init(_ projection: ViewListProjection, startingType: ObjectIdentifier? = nil) {
        let activity = ViewListProjectionActivity()
        let snapshot = Self.flatten(projection, startingType: startingType, activity: activity)
        let isValid = !snapshot.rejected && activity.isCurrent
        self.isValid = isValid
        self.elements = isValid ? snapshot.elements : []
        self.segments = isValid ? snapshot.segments : []
        self.containsDeferredData = snapshot.containsDeferredData
    }

    @inline(never)
    private static func flatten(
        _ projection: ViewListProjection, startingType: ObjectIdentifier?, activity: ViewListProjectionActivity
    ) -> Snapshot {
        var elements: [Element] = []
        var segments: [Segment] = []
        var containsDeferredData = false
        var rejected = false
        var pending = [(projection, ViewListIdentityCursor(currentType: startingType))]
        while let (next, cursor) = pending.popLast() {
            guard activity.isCurrent else {
                rejected = true
                break
            }
            switch next {
            case .leaf(let view):
                let row = view.prefixedViewIdentity(cursor.prefix)
                let identity = RetainedViewIdentity(segments: row.structuralIdentity)
                    .appending(.view(view.viewTypeIdentifier))
                elements.append(
                    Element(
                        segmentIndex: segments.count, sourceOrdinal: 0, identity: identity,
                        implicitSelectionTag: view.selectionTag))
                segments.append(.authored(row))
            case .value(let view):
                pending.append((view.viewListProjection(), cursor))
            case .deferredData(let data):
                containsDeferredData = true
                guard data.isCurrent else {
                    activity.reject()
                    rejected = true
                    break
                }
                let segmentIndex = segments.count
                segments.append(.data(data, prefix: cursor.prefix))
                for (ordinal, element) in data.elements.enumerated() {
                    elements.append(
                        Element(
                            segmentIndex: segmentIndex, sourceOrdinal: ordinal,
                            identity: RetainedViewIdentity(
                                segments: cursor.prefix + [
                                    .occurrence(element.occurrence), .keyed(element.key), .view(data.contentType),
                                ]),
                            implicitSelectionTag: element.implicitSelectionTag))
                }
            case .retainedStructure(let deferred, _):
                // Group's ordinary path adds an occurrence after its child
                // builder has finished. The deferred path preserves the same
                // outer boundary without expanding dynamic model elements.
                pending.append((deferred, cursor.applying(.prefix([.occurrence(0)]))))
            case .scope(let transition, _, let children):
                let childCursor = cursor.applying(transition)
                for child in children.reversed() { pending.append((child, childCursor)) }
            }
            if rejected { break }
        }
        return Snapshot(
            elements: elements, segments: segments, containsDeferredData: containsDeferredData, rejected: rejected)
    }

    /// Zero or multiple outputs belong to this one model element. Their local
    /// slots and conditionals are normalized only after its factory is chosen.
    func rowViews(for index: Int) -> [AnyView] {
        let activity = ViewListProjectionActivity()
        guard isCurrent, activity.isCurrent, elements.indices.contains(index) else { return [] }
        let element = elements[index]
        switch segments[element.segmentIndex] {
        case .authored(let view):
            return [view]
        case .data(let data, let prefix):
            let occurrence = data.elements[element.sourceOrdinal].occurrence
            let rows = data.rowViews(for: element.sourceOrdinal)
            guard activity.isCurrent, data.isCurrent else {
                data.revoke()
                return []
            }
            return rows.map {
                $0.prefixedViewIdentity(prefix + [.occurrence(occurrence)])
            }
        }
    }

    /// Validation follows only this record's source and never materializes
    /// an authored leaf. A fresh lookup is needed after child State ownership
    /// has been published; the finite row admission itself is never refreshed.
    func validateSource(
        for index: Int, context: ViewBuildContext? = ViewBuildContextScope.current
    ) -> Bool {
        if let context {
            return ViewBuildContextScope.withCurrent(context) { validateSourceInCurrentContext(for: index) }
        }
        return validateSourceInCurrentContext(for: index)
    }

    private func validateSourceInCurrentContext(for index: Int) -> Bool {
        guard elements.indices.contains(index) else { return false }
        let activity = ViewListProjectionActivity()
        guard isCurrent, activity.isCurrent else {
            activity.reject()
            return false
        }
        let valid = validateSegmentSource(for: elements[index], activity: activity)
        guard valid, isCurrent, activity.isCurrent else {
            activity.reject()
            return false
        }
        return true
    }

    @inline(never)
    private func validateSegmentSource(for element: Element, activity: ViewListProjectionActivity) -> Bool {
        guard activity.isCurrent else { return false }
        switch segments[element.segmentIndex] {
        case .authored:
            return true
        case .data(let data, _):
            let valid = data.validateSource(for: element.sourceOrdinal)
            guard valid, activity.isCurrent else {
                data.revoke()
                return false
            }
            return true
        }
    }
}

@MainActor
final class DeferredViewListGeneration {
    private(set) var isCurrent: Bool

    init(isCurrent: Bool) { self.isCurrent = isCurrent }
    func revoke() { isCurrent = false }
}

@MainActor
protocol DeferredListElementValidation {
    var deferredListGeneration: DeferredViewListGeneration { get }
    func validateDeferredListElement() -> Bool
}

/// A Binding ForEach retains one shared resolver, not one Binding (and two
/// captured accessors) per model row. A requested binding locates its key in
/// the current collection, so reordering never redirects a positional write.
@MainActor
final class DeferredListBindingSource<Element, ID: Hashable> {
    let identifiers: [ID]
    let generation: DeferredViewListGeneration
    private let createBinding: (Int) -> Binding<Element>
    private let validateKey: (Int) -> Bool

    private struct Snapshot {
        let values: [Element]
        let identifiers: [ID]
        let occurrences: [Int]
    }

    init<Collection>(
        _ source: Binding<Collection>, id: KeyPath<Element, ID>
    ) where Collection: MutableCollection & RandomAccessCollection, Collection.Element == Element {
        let activity = ViewListProjectionActivity()
        let snapshot = Self.collectSnapshot(source, id: id, activity: activity)
        let identifiers = snapshot.identifiers
        let occurrences = snapshot.occurrences
        let generation = DeferredViewListGeneration(isCurrent: activity.isCurrent)
        self.generation = generation
        self.identifiers = generation.isCurrent ? identifiers : []
        self.validateKey = { ordinal in
            let activity = ViewListProjectionActivity()
            let isCurrent = { activity.isCurrent && generation.isCurrent }
            guard isCurrent(), identifiers.indices.contains(ordinal) else {
                generation.revoke()
                return false
            }
            let collection = source.wrappedValue
            guard isCurrent() else {
                generation.revoke()
                return false
            }
            guard
                Self.index(
                    for: identifiers[ordinal], occurrence: occurrences[ordinal], in: collection,
                    id: id, isCurrent: isCurrent) != nil,
                isCurrent()
            else {
                generation.revoke()
                return false
            }
            return true
        }
        self.createBinding = { ordinal in
            guard snapshot.values.indices.contains(ordinal), identifiers.indices.contains(ordinal) else {
                preconditionFailure("Only a declared binding element can request a binding")
            }
            let key = identifiers[ordinal]
            let occurrence = occurrences[ordinal]
            // The source snapshot is plain model data, not one Binding per
            // element. Built-in Array access performs no authored callbacks
            // while creating the fallback for a newly requested binding.
            let initial = snapshot.values[ordinal]
            let lease = DeferredListBindingLease(initial)
            let attribution = ViewBuildContextScope.current?.viewIdentity.lazyList
            let membership = attribution?.native.logicalMembership
            let admission = attribution?.admission
            let coordinator = ViewBuildContextScope.current?.stateMountCoordinator
            let isCurrent: @MainActor @Sendable () -> Bool = {
                guard !lease.retired, generation.isCurrent else { return false }
                guard let membership else { return true }
                return membership.isDeclared || (membership.phase == .proposed && admission?.isCurrent == true)
            }
            return Binding(
                get: { [weak coordinator] in
                    guard isCurrent() else { return lease.lastValue }
                    let operation = DeferredListBindingOperation(membership: membership, coordinator: coordinator)
                    let permitsOperation = { isCurrent() && operation.isCurrent }
                    let collection = source.wrappedValue
                    guard permitsOperation() else { return lease.lastValue }
                    guard
                        let index = Self.index(
                            for: key, occurrence: occurrence, in: collection, id: id, isCurrent: permitsOperation)
                    else {
                        if permitsOperation() {
                            lease.retired = true
                            generation.revoke()
                        }
                        return lease.lastValue
                    }
                    guard permitsOperation() else { return lease.lastValue }
                    let value = collection[index]
                    guard permitsOperation() else { return lease.lastValue }
                    lease.lastValue = value
                    return value
                },
                set: { [weak coordinator] value in
                    guard isCurrent() else { return }
                    let operation = DeferredListBindingOperation(membership: membership, coordinator: coordinator)
                    let permitsOperation = { isCurrent() && operation.isCurrent }
                    var collection = source.wrappedValue
                    guard permitsOperation() else { return }
                    guard
                        let index = Self.index(
                            for: key, occurrence: occurrence, in: collection, id: id, isCurrent: permitsOperation)
                    else {
                        if permitsOperation() {
                            lease.retired = true
                            generation.revoke()
                        }
                        return
                    }
                    guard permitsOperation() else { return }
                    collection[index] = value
                    guard permitsOperation() else { return }
                    source.wrappedValue = collection
                    if isCurrent() { lease.lastValue = value }
                },
                isValidForWrite: isCurrent)
        }
    }

    @inline(never)
    private static func collectSnapshot<Values: RandomAccessCollection>(
        _ source: Binding<Values>, id: KeyPath<Element, ID>, activity: ViewListProjectionActivity
    ) -> Snapshot where Values.Element == Element {
        var values: [Element] = []
        var identifiers: [ID] = []
        var occurrences: [Int] = []
        guard activity.isCurrent else { return Snapshot(values: [], identifiers: [], occurrences: []) }
        let sourceValue = source.wrappedValue
        guard activity.isCurrent else { return Snapshot(values: [], identifiers: [], occurrences: []) }
        var seen = ManagedKeyedMap<RetainedViewIdentity.Key, Int>()
        var iterator = sourceValue.makeIterator()
        while activity.isCurrent {
            let next = iterator.next()
            guard activity.isCurrent, let element = next else { break }
            let identifier = element[keyPath: id]
            guard activity.isCurrent else { break }
            let key = RetainedViewIdentity.Key(identifier)
            let occurrence = seen[key, while: { activity.isCurrent }] ?? 0
            guard activity.isCurrent else { break }
            seen[key, while: { activity.isCurrent }] = occurrence + 1
            guard activity.isCurrent else { break }
            values.append(element)
            identifiers.append(identifier)
            occurrences.append(occurrence)
        }
        return Snapshot(values: values, identifiers: identifiers, occurrences: occurrences)
    }

    func binding(for ordinal: Int) -> Binding<Element> {
        createBinding(ordinal)
    }

    func isCurrent(for ordinal: Int) -> Bool { validateKey(ordinal) }

    private static func index<Values: Collection>(
        for key: ID, occurrence: Int, in collection: Values, id: KeyPath<Element, ID>,
        isCurrent: () -> Bool
    ) -> Values.Index? where Values.Element == Element {
        guard isCurrent() else { return nil }
        let startIndex = collection.startIndex
        guard isCurrent() else { return nil }
        let endIndex = collection.endIndex
        guard isCurrent() else { return nil }
        var index = startIndex
        var remaining = occurrence
        while isCurrent() {
            let reachedEnd = index == endIndex
            guard isCurrent() else { return nil }
            if reachedEnd { break }
            let element = collection[index]
            guard isCurrent() else { return nil }
            let candidate = element[keyPath: id]
            guard isCurrent() else { return nil }
            let matches =
                RetainedViewIdentity.Key(candidate).checkedEquals(
                    RetainedViewIdentity.Key(key), isCurrent: isCurrent) == true
            guard isCurrent() else { return nil }
            if matches {
                if remaining == 0 { return index }
                remaining -= 1
            }
            let nextIndex = collection.index(after: index)
            guard isCurrent() else { return nil }
            index = nextIndex
        }
        return nil
    }
}

@MainActor
private struct DeferredListBindingOperation {
    let membership: RetainedLazyListLogicalMembershipSnapshot?
    let stateRequest: (any RetainedBuildRequest)?

    init(membership: RetainedLazyListLogicalMembershipReceipt?, coordinator: StateMountCoordinator?) {
        self.membership = membership?.scope.snapshot()
        self.stateRequest = coordinator?.captureBuildRequest()
    }

    var isCurrent: Bool {
        stateRequest?.isCurrent != false && membership.map { $0.scope.isCurrent($0) } != false
    }
}

@MainActor
private final class DeferredListBindingLease<Element> {
    var lastValue: Element
    var retired = false

    init(_ value: Element) { lastValue = value }
}
