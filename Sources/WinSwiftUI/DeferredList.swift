import SwiftWindowsCore
import SwiftWindowsUI

/// Model metadata is independent of physical row construction. One record is
/// one authored data element; it may later produce zero or several leaf rows.
@MainActor
private struct DeferredListRecord {
    let ordinal: Int
    let identity: RetainedViewIdentity
    let implicitTag: AnyHashable?
}

/// The factory never captures a finite descriptor-build receipt. A later row
/// visit obtains its own current construction context through this binding.
@MainActor
private final class DeferredListDescriptorReference {
    var binding: RetainedLazyListManagedLogicalDescriptorBinding?
    weak var source: RetainedLazyListDataSource<DeferredListRecord, [ViewNode]>?
}

@MainActor
private enum DeferredListRecordBuildResult {
    case built([ViewNode])
    case rejected
    case unsupportedShape
}

@MainActor
func makeDeferredListComponent(
    projection: DeferredListProjection, selectionMode: ListSelectionMode?, prefersImplicitSelectionTag: Bool,
    context sourceContext: ViewBuildContext
) -> Component {
    let context = sourceContext.withEnvironmentValue(\.isInsideGroupedForm, false)
    return Component { runtime in
        let coordinator = context.stateMountCoordinator
        let receipt = coordinator?.descriptorResolutionReceipt(in: context)
        let owner = context.viewIdentity.installedOwner
        guard projection.isCurrent,
            coordinator == nil || (owner != nil && receipt?.isCurrent == true)
        else { return rejectedRetainedViewNode() }
        let listIdentity = context.retainedViewIdentity.appending(.role(.content))
        let chrome = context.listStyle.retainedChrome(palette: context.controlPalette)
        let rowSpacing = context.listRowSpacing ?? context.listSectionSpacing(defaultSpacing: chrome.defaultSpacing)
        let separatorThickness = chrome.drawsRowSeparators ? retainedHairlineThickness(for: context) : 0
        guard rowSpacing.isFinite, rowSpacing >= 0 else { return rejectedRetainedViewNode() }
        let minimumRowHeight = max(
            context.defaultMinListRowHeight, chrome.rowMinHeight,
            selectionMode == nil ? 0 : List.defaultSelectionRowMinHeight)
        let estimate = max(20, minimumRowHeight) + rowSpacing * 2 + separatorThickness
        let viewport = context.canvasSize.height
        let finiteViewport = viewport.isFinite && viewport > 0 ? min(viewport, 16_384) : 0
        let maximumRecords = max(512, Int(finiteViewport.rounded(.up)) + 64)
        let maximumLeaves = maximumRecords * 8
        let prefetch = min(256, max(64, estimate * 3))
        let reference = DeferredListDescriptorReference()
        let navigation = ListKeyboardNavigationState(runtime: runtime)
        let records = projection.elements.enumerated().map { ordinal, element in
            DeferredListRecord(ordinal: ordinal, identity: element.identity, implicitTag: element.implicitSelectionTag)
        }
        let isEditing = context.environmentValues.editMode?.wrappedValue.isEditing == true
        guard receipt?.isCurrent != false, projection.isCurrent else { return rejectedRetainedViewNode() }

        let buildRows: @MainActor (DeferredListRecord, RetainedViewIdentity) -> [ViewNode] = {
            [weak runtime] record, prefix in
            guard let runtime, projection.isCurrent else {
                reference.source?.close()
                return [rejectedRetainedViewNode()]
            }
            var rowContext: ViewBuildContext
            if let coordinator {
                guard let binding = reference.binding, binding.isCurrent,
                    let entered = coordinator.contextForEnteredLazyRow(from: context, descriptor: binding),
                    entered.viewIdentity.lazyList?.admission.isCurrent == true
                else { return [rejectedRetainedViewNode()] }
                rowContext = entered
            } else {
                rowContext = context
            }
            // The provider's checked namespace owns this logical record. The
            // projected relative path below it preserves authored leaf slots,
            // conditional branches, explicit IDs and duplicate occurrences.
            rowContext.viewIdentity.path = prefix
            let result = materializeDeferredListRecord(
                record, prefix: prefix, projection: projection, selectionMode: selectionMode,
                prefersImplicitSelectionTag: prefersImplicitSelectionTag, chrome: chrome,
                isEditing: isEditing, rowSpacing: rowSpacing, separatorThickness: separatorThickness,
                maximumProjectedLeaves: maximumLeaves / 2,
                context: rowContext, runtime: runtime, navigation: navigation)
            if case .unsupportedShape = result {
                // An authored record exceeding the physical sibling cap is
                // terminal for this source. Later frames must not repeat its
                // factory indefinitely while calling it merely pending work.
                reference.source?.close()
                return [rejectedRetainedViewNode()]
            }
            // The helper has released temporary View values. Their cleanup
            // cannot change a reference-backed model ID after its final check.
            guard case .built(let nodes) = result, rowContext.viewIdentity.lazyList?.admission.isCurrent != false,
                projection.validateSource(for: record.ordinal, context: rowContext)
            else {
                if !projection.isCurrent { reference.source?.close() }
                return [rejectedRetainedViewNode()]
            }
            return nodes
        }

        let predecessor = runtime.lazyListPredecessor(for: listIdentity, during: receipt?.nativeScope)
        let source: RetainedLazyListDataSource<DeferredListRecord, [ViewNode]>
        if let previous = predecessor?.dataSource(for: DeferredListRecord.self) {
            guard
                let staged = previous.stagedReplacement(
                    records, id: \.identity, identityRoot: listIdentity,
                    descriptorBuildScope: receipt?.nativeScope, rowContent: buildRows)
            else { return rejectedRetainedViewNode() }
            source = staged
        } else {
            source = RetainedLazyListDataSource<DeferredListRecord, [ViewNode]>()
            guard
                source.replaceData(
                    records, id: \.identity, identityRoot: listIdentity,
                    descriptorBuildScope: receipt?.nativeScope, rowContent: buildRows)
            else { return rejectedRetainedViewNode() }
        }
        reference.source = source
        var installedSource = false
        defer { if !installedSource { source.close() } }
        guard receipt?.isCurrent != false, projection.isCurrent,
            let metadata = source.metadata, receipt?.isCurrent != false,
            let adapter = RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: estimate, prefetchExtent: prefetch,
                maximumMountedRecords: maximumRecords, maximumMountedLeaves: maximumLeaves,
                maximumProtectedRecords: 16)
        else { return rejectedRetainedViewNode() }

        let lease: any RetainedSubtreeBuildLease
        if let coordinator, let owner, let receipt {
            guard
                let proposal = coordinator.stageLazyMembership(
                    at: listIdentity, metadata: metadata, context: context, receipt: receipt), receipt.isCurrent
            else { return rejectedRetainedViewNode() }
            let binding = proposal.nativeBinding
            guard adapter.installManagedLogicalDescriptor(binding), receipt.isCurrent else {
                return rejectedRetainedViewNode()
            }
            reference.binding = binding
            let capturedLease = coordinator.subtreeLease(
                owner: owner, contentPrefix: listIdentity, lazyAttribution: context.viewIdentity.lazyList,
                descriptorAttribution: context.viewIdentity.descriptorComponent)
            guard receipt.isCurrent else { return rejectedRetainedViewNode() }
            lease = capturedLease
        } else {
            lease = StandaloneDeferredListLease(runtime: runtime, adapter: adapter)
        }
        if let predecessor, let continuation = source.predecessorContinuation {
            guard adapter.stagePredecessor(predecessor, continuation: continuation), receipt?.isCurrent != false else {
                return rejectedRetainedViewNode()
            }
        }

        let list = Controls.panel(
            layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)), isHitTestVisible: false)
        list.retainedViewIdentity = listIdentity
        list.retainedSubtreeBuildLease = lease
        list.retainedLazyListAdapter = adapter
        list.layoutFillAxes = .horizontalOnly
        list.accessibilityChildBehavior = .contain
        if let standalone = lease as? StandaloneDeferredListLease { standalone.bind(to: list) }
        coordinator?.materializeSubtreeLease(lease)
        guard receipt?.isCurrent != false, projection.isCurrent,
            DeferredListScrollSource.install(
                on: list,
                rows: records.map { (implicitID: $0.implicitTag, providerKey: RetainedViewIdentity.Key($0.identity)) },
                isCurrent: { receipt?.isCurrent != false && projection.isCurrent })
        else { return rejectedRetainedViewNode() }

        let alignment = context.defaultScrollAnchor(for: .alignment)
        let scroll = Controls.scrollPanel(
            axis: .vertical,
            backgroundColor: chrome.backgroundColor, borderColor: chrome.borderColor,
            borderWidth: chrome.borderWidth, cornerRadius: chrome.cornerRadius,
            stackLayout: .vertical(
                spacing: 0,
                padding: context.contentInsets(for: .scrollContent, defaultInsets: chrome.padding),
                alignment: .stretch,
                mainAlignment: alignment.map { stackMainAlignment(from: $0.y) } ?? .start),
            isHitTestVisible: false, children: [list])
        scroll.accessibilityChildBehavior = .contain
        navigation.installDeferredNavigation(in: list, prefersImplicitSelectionTag: prefersImplicitSelectionTag)
        List.configureScrolling(
            scroll, context: context, navigationState: navigation, includesUnrealizedRows: !records.isEmpty)
        guard receipt?.isCurrent != false, projection.isCurrent else { return rejectedRetainedViewNode() }
        installedSource = true
        return scroll
    }
}

@MainActor
@inline(never)
private func materializeDeferredListRecord(
    _ record: DeferredListRecord, prefix: RetainedViewIdentity, projection: DeferredListProjection,
    selectionMode: ListSelectionMode?, prefersImplicitSelectionTag: Bool, chrome: RetainedListChrome,
    isEditing: Bool, rowSpacing: Double, separatorThickness: Double, maximumProjectedLeaves: Int,
    context: ViewBuildContext,
    runtime: RetainedViewRuntime, navigation: ListKeyboardNavigationState
) -> DeferredListRecordBuildResult {
    func canConstruct() -> Bool {
        projection.isCurrent && context.viewIdentity.lazyList?.admission.isCurrent != false
            && context.viewIdentity.descriptorComponent?.canConstruct != false
    }
    guard canConstruct(), projection.validateSource(for: record.ordinal, context: context), canConstruct() else {
        return .rejected
    }
    let views = ViewBuildContextScope.withCurrent(context) { projection.rowViews(for: record.ordinal) }
    guard canConstruct() else { return .rejected }
    guard views.count <= maximumProjectedLeaves else { return .unsupportedShape }
    var nodes: [ViewNode] = []
    nodes.reserveCapacity(views.count * 2)
    for (leafIndex, view) in views.enumerated() {
        guard canConstruct() else { return .rejected }
        let row = ViewBuildContextScope.withCurrent(context) {
            List.materializedRow(
                view, index: leafIndex, implicitTag: record.implicitTag,
                prefersImplicitTag: prefersImplicitSelectionTag,
                selectionMode: selectionMode, listChrome: chrome, isEditing: isEditing,
                context: context, runtime: runtime, navigationState: navigation,
                logicalOrdinal: record.ordinal, logicalLeaf: leafIndex,
                validateSource: { projection.validateSource(for: record.ordinal, context: context) })
        }
        guard canConstruct(), projection.validateSource(for: record.ordinal, context: context), canConstruct() else {
            return .rejected
        }
        let gap = makeDeferredListGap(
            before: row.node, selected: row.isSelected, spacing: rowSpacing,
            separatorThickness: separatorThickness, leadingInset: chrome.separatorLeadingInset,
            context: context, identity: prefix.appending(contentsOf: [.role(.row), .slot(leafIndex)]))
        nodes.append(gap)
        nodes.append(row.node)
    }
    return .built(nodes)
}

/// Gaps are real bounded presentation leaves, never a wrapper that changes
/// authored row identity or supplies a task/selection/accessibility target.
/// Their native metadata lets layout decide separators from neighboring row
/// summaries without invoking a row factory or retaining an evicted row.
@MainActor
private func makeDeferredListGap(
    before row: ViewNode, selected: Bool, spacing: Double, separatorThickness: Double,
    leadingInset: Double, context: ViewBuildContext, identity: RetainedViewIdentity
) -> ViewNode {
    let gap = Controls.panel(
        preferredSize: Size(width: 0, height: spacing), layoutMode: .absolute,
        isHitTestVisible: false)
    gap.retainedViewIdentity = identity
    gap.layoutFillAxes = .horizontalOnly
    gap.clipsToBounds = true
    gap.isSeparatorRule = true
    gap.retainedLazyListGap = RetainedLazyListGap(
        spacing: spacing, separatorThickness: separatorThickness, nextRowIsSelected: selected,
        nextRowIsGrouped: row.sectionHeaderChildCount > 0 || row.sectionFooterChildCount > 0)
    if separatorThickness > 0 {
        let rule = Controls.panel(
            preferredSize: Size(width: 0, height: separatorThickness),
            backgroundColor: context.controlPalette.separator,
            isHitTestVisible: false)
        rule.isSeparatorRule = true
        rule.layoutFillAxes = .horizontalOnly
        let inset = Controls.panel(
            preferredSize: Size(width: 0, height: separatorThickness),
            layoutMode: .stack(
                .horizontal(
                    padding: EdgeInsets(top: 0, leading: leadingInset, bottom: 0, trailing: 0), alignment: .stretch)),
            isHitTestVisible: false, children: [rule])
        inset.frame = Rect(origin: Point(x: 0, y: spacing), size: Size(width: 0, height: separatorThickness))
        inset.layoutFillAxes = .horizontalOnly
        gap.addChild(inset)
    }
    return gap
}

/// Direct makeComponent callers have no mounted State owner, just as with
/// ordinary direct View construction. They still need a real retained lease
/// so raw row builders cannot run after this exact container has departed.
@MainActor
private final class StandaloneDeferredListLease: RetainedSubtreeBuildLease {
    private weak var runtime: RetainedViewRuntime?
    private weak var container: ViewNode?
    private weak var adapter: RetainedLazyListRuntimeAdapter?

    init(runtime: RetainedViewRuntime, adapter: RetainedLazyListRuntimeAdapter) {
        self.runtime = runtime
        self.adapter = adapter
    }

    func bind(to container: ViewNode) { if self.container == nil { self.container = container } }

    var canBuild: Bool {
        guard let runtime, let container, let adapter, adapter.ownsAttachment(container),
            container.retainedLazyListAdapter === adapter, runtime.permitsRetainedActionInvocation
        else { return false }
        var ancestor: ViewNode? = container
        var depth = 0
        while let node = ancestor, depth < ViewNode.maximumTraversalDepth {
            if node === runtime.root { return true }
            ancestor = node.parent
            depth += 1
        }
        return false
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        canBuild ? StandaloneDeferredListEpoch(lease: self) : nil
    }
}

@MainActor
private final class StandaloneDeferredListEpoch: RetainedBuildEpoch {
    private weak var lease: StandaloneDeferredListLease?
    private var didPrepare = false
    private var didFinish = false
    private var wasSuperseded = false

    init(lease: StandaloneDeferredListLease) { self.lease = lease }
    var canAdopt: Bool { !didFinish && !wasSuperseded && lease?.canBuild == true }
    var canComplete: Bool { !wasSuperseded && lease?.canBuild == true }
    func supersede() { if !didPrepare { wasSuperseded = true } }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        didPrepare = true
        return true
    }
    func commit() { didFinish = true }
    func abandon() {
        wasSuperseded = true
        didFinish = true
    }
    func finishAfterCallbacks() { didFinish = true }
}
