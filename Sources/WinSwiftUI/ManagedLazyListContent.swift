import SwiftWindowsCore
import SwiftWindowsUI

@MainActor
private final class ManagedLazyListDescriptorReference {
    private(set) var binding: RetainedLazyListManagedLogicalDescriptorBinding?

    func install(_ binding: RetainedLazyListManagedLogicalDescriptorBinding) -> Bool {
        guard self.binding == nil, binding.isCurrent else { return false }
        self.binding = binding
        return true
    }
}

/// Internal deferred data construction used to exercise the managed activity
/// bridge without public List projection and chrome.
@MainActor
struct ManagedLazyListContent<Data: RandomAccessCollection, ID: Hashable>: View {
    typealias Body = Never

    private let data: Data
    private let id: KeyPath<Data.Element, ID>
    private let estimatedExtent: Double
    private let prefetchExtent: Double
    private let maximumMountedRecords: Int
    private let maximumMountedLeaves: Int
    private let maximumProtectedRecords: Int
    private let rowContent: @MainActor (Data.Element) -> [AnyView]

    init(
        _ data: Data, id: KeyPath<Data.Element, ID>, estimatedExtent: Double, prefetchExtent: Double,
        maximumMountedRecords: Int, maximumMountedLeaves: Int, maximumProtectedRecords: Int,
        @ViewBuilder rowContent: @escaping @MainActor (Data.Element) -> [AnyView]
    ) {
        self.data = data
        self.id = id
        self.estimatedExtent = estimatedExtent
        self.prefetchExtent = prefetchExtent
        self.maximumMountedRecords = maximumMountedRecords
        self.maximumMountedLeaves = maximumMountedLeaves
        self.maximumProtectedRecords = maximumProtectedRecords
        self.rowContent = rowContent
    }

    var body: Never { fatalError("ManagedLazyListContent has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        withInstalledViewValue(self, context: context, isInstalledDelegate: true) { content, installedContext in
            content.makeDeferredComponent(context: installedContext)
        }
    }

    private func makeDeferredComponent(context: ViewBuildContext) -> Component {
        let rowContent = self.rowContent
        return Component { runtime in
            guard let coordinator = context.stateMountCoordinator,
                let owner = context.viewIdentity.installedOwner,
                let receipt = coordinator.descriptorResolutionReceipt(in: context), receipt.isCurrent
            else { return rejectedRetainedViewNode() }

            // Acquire the descriptor receipt before collection snapshotting or
            // typed key work. The long-lived factory captures only the source
            // context and native binding, never the facade membership proposal.
            let reference = ManagedLazyListDescriptorReference()
            let listIdentity = context.retainedViewIdentity.appending(.role(.content))
            let buildRows: @MainActor (Data.Element, RetainedViewIdentity) -> [ViewNode] = {
                [weak runtime] element, prefix in
                guard let runtime, let binding = reference.binding, binding.isCurrent,
                    var rowContext = coordinator.contextForEnteredLazyRow(from: context, descriptor: binding),
                    let attribution = rowContext.viewIdentity.lazyList, attribution.admission.isCurrent
                else { return [rejectedRetainedViewNode()] }
                rowContext.viewIdentity.path = prefix
                let views = ViewBuildContextScope.withCurrent(rowContext) { rowContent(element) }
                guard attribution.admission.isCurrent else { return [rejectedRetainedViewNode()] }
                let component = composeStructuralComponent(from: views, context: rowContext)
                guard attribution.admission.isCurrent else { return [rejectedRetainedViewNode()] }
                var nodes: [ViewNode] = []
                ViewBuildContextScope.withCurrent(rowContext) {
                    component.appendChildNodes(runtime: runtime, to: &nodes)
                }
                return attribution.admission.isCurrent ? nodes : [rejectedRetainedViewNode()]
            }

            // Keep the accepted cohort attached while the successor descriptor
            // waits for viewport construction. Otherwise an empty replacement
            // tree retires owned cells for rows whose logical keys still exist.
            let predecessor = runtime.lazyListPredecessor(for: listIdentity, during: receipt.nativeScope)
            guard receipt.isCurrent else { return rejectedRetainedViewNode() }
            let source: RetainedLazyListDataSource<Data.Element, [ViewNode]>
            if let previous = predecessor?.dataSource(for: Data.Element.self) {
                guard
                    let staged = previous.stagedReplacement(
                        data, id: id, identityRoot: listIdentity,
                        descriptorBuildScope: receipt.nativeScope, rowContent: buildRows)
                else { return rejectedRetainedViewNode() }
                source = staged
            } else {
                source = RetainedLazyListDataSource<Data.Element, [ViewNode]>()
                guard
                    source.replaceData(
                        data, id: id, identityRoot: listIdentity,
                        descriptorBuildScope: receipt.nativeScope, rowContent: buildRows)
                else {
                    source.close()
                    return rejectedRetainedViewNode()
                }
            }
            var installedSource = false
            defer { if !installedSource { source.close() } }

            guard receipt.isCurrent,
                let metadata = source.metadata, receipt.isCurrent,
                let proposal = coordinator.stageLazyMembership(
                    at: listIdentity, metadata: metadata, context: context, receipt: receipt), receipt.isCurrent
            else { return rejectedRetainedViewNode() }

            let binding = proposal.nativeBinding
            guard reference.install(binding), receipt.isCurrent,
                let adapter = RetainedLazyListRuntimeAdapter(
                    provider: source, estimatedExtent: estimatedExtent, prefetchExtent: prefetchExtent,
                    maximumMountedRecords: maximumMountedRecords, maximumMountedLeaves: maximumMountedLeaves,
                    maximumProtectedRecords: maximumProtectedRecords),
                adapter.installManagedLogicalDescriptor(binding), receipt.isCurrent
            else { return rejectedRetainedViewNode() }

            if let predecessor, let continuation = source.predecessorContinuation {
                guard adapter.stagePredecessor(predecessor, continuation: continuation), receipt.isCurrent else {
                    return rejectedRetainedViewNode()
                }
            }

            let lease = coordinator.subtreeLease(
                owner: owner, contentPrefix: listIdentity, lazyAttribution: context.viewIdentity.lazyList,
                descriptorAttribution: context.viewIdentity.descriptorComponent)
            guard receipt.isCurrent else { return rejectedRetainedViewNode() }
            let list = Controls.panel(
                layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)), isHitTestVisible: false)
            list.retainedViewIdentity = listIdentity
            list.retainedSubtreeBuildLease = lease
            list.retainedLazyListAdapter = adapter
            coordinator.materializeSubtreeLease(lease)
            guard receipt.isCurrent else { return rejectedRetainedViewNode() }
            let scroll = Controls.scrollPanel(
                axis: .vertical, stackLayout: .vertical(spacing: 0, alignment: .stretch),
                isHitTestVisible: false, children: [list])
            scroll.layoutFillAxes = .both
            installedSource = true
            return scroll
        }
    }
}
