import SwiftWindowsCore
import SwiftWindowsUI

/// A Table keeps the original construction attribution across its authored
/// builders. Key lookups use a separate operation receipt: normal child view
/// installation may publish owners, but a key callback may not renew a lookup
/// after a nested installation changes the captured registry revision.
@MainActor
final class TableConstructionAdmission {
    private let lazy: LazyListViewAttribution?
    private let descriptor: RetainedDescriptorComponentAttribution?
    private weak var coordinator: StateMountCoordinator?
    private var rejected = false

    init(context: ViewBuildContext) {
        lazy = context.viewIdentity.lazyList
        descriptor = context.viewIdentity.descriptorComponent
        coordinator = context.stateMountCoordinator
    }

    var isCurrent: Bool {
        guard !rejected, lazy == nil || descriptor == nil,
            lazy?.isCurrent != false, descriptor?.canConstruct != false
        else {
            reject()
            return false
        }
        return true
    }

    func reject() {
        guard !rejected else { return }
        rejected = true
        lazy?.admission.reject()
        lazy?.native.rejectComponent()
        descriptor?.rejectComponent()
    }

    /// Only callbacks that produce values belong in this scope. Typed child
    /// construction has its own checked owner publication and must not run
    /// beneath a lookup receipt that forbids those legitimate publications.
    @inline(never)
    func withLookup<Value>(_ body: (_ isCurrent: () -> Bool) -> Value?) -> Value? {
        guard isCurrent else { return nil }
        let lookup: LazyListLookupReceipt?
        if let lazy {
            guard let original = lazy.admission.beginLookup() else {
                reject()
                return nil
            }
            lookup = original
        } else if let descriptor {
            guard let original = coordinator?.descriptorLookupReceipt(for: descriptor) else {
                reject()
                return nil
            }
            lookup = original
        } else {
            lookup = nil
        }
        func canContinue() -> Bool { isCurrent && lookup?.isCurrent != false }
        guard canContinue() else {
            reject()
            return nil
        }
        // The callback's local maps and value pins are released before the
        // final check. A rejected operation cannot acquire a fresh receipt.
        let result = body(canContinue)
        guard let result, canContinue() else {
            reject()
            return nil
        }
        return result
    }

    /// The callback's own Optional result is a value, not failed admission.
    func withValueLookup<Value>(_ body: (_ isCurrent: () -> Bool) -> Value) -> Value? {
        withLookup { isCurrent in Optional<Value>.some(body(isCurrent)) }
    }

    func headerIdentities<RowValue>(
        for columns: [AnyTableColumn<RowValue>]
    ) -> [[RetainedViewIdentity.Segment]]? {
        withLookup { isCurrent in
            var occurrences: ManagedKeyedMap<RetainedViewIdentity.Key, Int> = [:]
            var result: [[RetainedViewIdentity.Segment]] = []
            result.reserveCapacity(columns.count)
            defer { withExtendedLifetime((columns, occurrences)) {} }
            for (index, column) in columns.enumerated() {
                guard isCurrent() else { return nil }
                if column.isSortable, let value = column.sortKey {
                    let key = RetainedViewIdentity.Key(value)
                    let occurrence = occurrences[key, while: isCurrent] ?? 0
                    guard isCurrent(), occurrences.setValue(occurrence + 1, for: key, isCurrent: isCurrent),
                        isCurrent()
                    else { return nil }
                    result.append([.keyed(key), .occurrence(occurrence)])
                } else {
                    result.append([.slot(index)])
                }
            }
            return result
        }
    }
}
