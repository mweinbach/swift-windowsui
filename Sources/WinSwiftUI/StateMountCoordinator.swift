import SwiftWindowsCore
import SwiftWindowsUI

/// One host's typed ownership and dependency boundary. Building a value is
/// provisional until its retained nodes are adopted; no application writes
/// are rolled back when a candidate is superseded.
@MainActor
final class StateMountCoordinator: RetainedBuildLifecycle {
    let registry: StateMountRegistry
    private let presentationActivity = PresentationActivityLedger()
    private let observeObject: @MainActor (any ObservableObject) -> Void
    private let updateObservedObjects: @MainActor (Set<ObjectIdentifier>, Set<ObjectIdentifier>, Bool) -> Void
    private let reportInstallationError: @MainActor (String) -> Void
    private var committedObservations: [RetainedViewIdentity: Set<ObjectIdentifier>] = [:]
    private var committedLazyObservations: [ObjectIdentifier: LazyListCommittedDependency] = [:]
    private var committedDescriptorObservations: [ObjectIdentifier: DescriptorCommittedDependency] = [:]
    private var currentBuild: StateMountBuild?
    private(set) var latestInstallationError: DynamicPropertyInstallationError?
    private var ownedAsyncImageService: AsyncImageService?
    private var imageServiceAdmissionsClosed = false

    var asyncImageService: AsyncImageService? {
        guard !imageServiceAdmissionsClosed, !registry.isClosed else { return nil }
        if let ownedAsyncImageService { return ownedAsyncImageService }
        let service = AsyncImageService()
        ownedAsyncImageService = service
        return service
    }

    init(
        invalidate: @escaping @MainActor () -> Void,
        observeObject: @escaping @MainActor (any ObservableObject) -> Void,
        updateObservedObjects:
            @escaping @MainActor (
                _ committed: Set<ObjectIdentifier>, _ retained: Set<ObjectIdentifier>, _ replacesRoot: Bool
            ) -> Void,
        reportInstallationError: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        registry = StateMountRegistry(invalidate: invalidate)
        self.observeObject = observeObject
        self.updateObservedObjects = updateObservedObjects
        self.reportInstallationError = reportInstallationError
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        guard currentBuild == nil, let epoch = registry.beginRootBuild() else { return nil }
        guard let activity = presentationActivity.beginBuild() else {
            epoch.abort()
            registry.finishPendingRetirements()
            return nil
        }
        latestInstallationError = nil
        let build = StateMountBuild(coordinator: self, epoch: epoch, activity: activity, replacesRoot: true)
        currentBuild = build
        return build
    }

    func captureBuildRequest() -> (any RetainedBuildRequest)? {
        StateMountRequest(registry: registry, revision: registry.mutationRevision)
    }

    func evaluateRootContent<Value>(
        in context: ViewBuildContext, while isCurrent: @MainActor () -> Bool = { true },
        _ content: @MainActor () -> Value
    ) -> RootViewContentResult<Value> {
        guard let (metadataContext, activity) = rootContentActivity(in: context) else { return .unavailable }
        return evaluateRootViewContent(
            in: metadataContext, while: { activity.isCurrent && isCurrent() }, content)
    }

    /// Keep the temporary strong build reference out of the authored callback.
    /// This component has no group or output; it supplies the original lookup
    /// fence for metadata only and is never passed to later component building.
    @inline(never)
    private func rootContentActivity(
        in context: ViewBuildContext
    ) -> (ViewBuildContext, ViewListProjectionActivity)? {
        guard context.stateMountCoordinator === self,
            context.viewIdentity.lazyList == nil, context.viewIdentity.descriptorComponent == nil,
            context.viewIdentity.installedOwner == nil, context.viewIdentity.installedEpoch == nil,
            let build = currentBuild, let descriptor = build.rootContentDescriptor()
        else { return nil }
        var metadataContext = context
        metadataContext.viewIdentity.descriptorComponent = descriptor
        let activity = ViewListProjectionActivity(context: metadataContext)
        guard activity.isCurrent else { return nil }
        return (metadataContext, activity)
    }

    func descriptorResolutionReceipt(in context: ViewBuildContext) -> LazyListDescriptorResolutionReceipt? {
        guard let build = currentBuild, context.viewIdentity.installedEpoch === build.epoch,
            let owner = context.viewIdentity.installedOwner
        else { return nil }
        if let descriptor = context.viewIdentity.descriptorComponent {
            guard context.viewIdentity.lazyList == nil, build.admitsDescriptor(descriptor),
                build.epoch.descriptorOwnerIsCurrent(owner, attribution: descriptor), build.admitsDescriptor(descriptor)
            else { return nil }
        }
        return build.descriptorResolutionReceipt(
            owner: owner, attribution: context.viewIdentity.lazyList,
            descriptorAttribution: context.viewIdentity.descriptorComponent)
    }

    func stageLazyMembership(
        at identity: RetainedViewIdentity, metadata: RetainedLazyListMetadata, context: ViewBuildContext
    ) -> LazyListMembershipProposal? {
        guard let receipt = descriptorResolutionReceipt(in: context) else { return nil }
        return stageLazyMembership(at: identity, metadata: metadata, context: context, receipt: receipt)
    }

    func stageLazyMembership(
        at identity: RetainedViewIdentity, metadata: RetainedLazyListMetadata, context: ViewBuildContext,
        receipt: LazyListDescriptorResolutionReceipt
    ) -> LazyListMembershipProposal? {
        guard let build = currentBuild, context.viewIdentity.installedEpoch === build.epoch, receipt.isCurrent else {
            return nil
        }
        let proposal = registry.stageLazyMembership(
            at: identity, metadata: metadata, parent: context.viewIdentity.lazyList?.logicalRow,
            in: build.epoch, receipt: receipt)
        guard isCurrent(build), receipt.isCurrent else { return nil }
        return proposal
    }

    func contextForEnteredLazyRow(
        from parent: ViewBuildContext, descriptor: RetainedLazyListManagedLogicalDescriptorBinding
    ) -> ViewBuildContext? {
        guard parent.stateMountCoordinator === self, let build = currentBuild,
            let attribution = build.enteredLazyRow(for: descriptor), attribution.admission.isCurrent
        else { return nil }
        var context = parent
        context.viewIdentity.lazyList = attribution
        context.viewIdentity.descriptorComponent = nil
        context.viewIdentity.candidateConstruction = nil
        context.viewIdentity.installedOwner = nil
        context.viewIdentity.installedEpoch = nil
        context.viewIdentity.currentType = nil
        return context
    }

    func stageLazyDependency(
        _ object: any ObservableObject, owner: StateMountOwner,
        attribution: LazyListViewAttribution, group: RetainedLazyListGroupID
    ) {
        guard let build = currentBuild, build.canConstructLazy, attribution.admission.isCurrent else { return }
        guard build.stageLazyDependency(object, owner: owner, attribution: attribution, group: group),
            isCurrent(build), attribution.isCurrent
        else { return }
        observeObject(object)
    }

    func childLazyAttribution(from parent: LazyListViewAttribution) -> LazyListViewAttribution? {
        guard let build = currentBuild, build.canConstructLazy, parent.isCurrent,
            let native = parent.native.registerChildComponent(), parent.isCurrent,
            let receipt = LazyListResolutionReceipt(epoch: build.epoch, native: native, parent: parent.admission)
        else { return nil }
        return LazyListViewAttribution(
            native: native, logicalRow: parent.logicalRow, component: native.component, admission: receipt)
    }

    func contextForDescriptorComponent(
        from parent: ViewBuildContext, isInstalledDelegate: Bool = false
    ) -> ViewBuildContext? {
        guard parent.viewIdentity.lazyList == nil, parent.viewIdentity.candidateConstruction?.canConstruct != false
        else { return nil }
        guard let build = currentBuild else { return parent.viewIdentity.descriptorComponent == nil ? parent : nil }
        guard build.descriptorScopeWasBound else {
            return parent.viewIdentity.descriptorComponent == nil ? parent : nil
        }
        if isInstalledDelegate, let attribution = parent.viewIdentity.descriptorComponent,
            parent.viewIdentity.installedEpoch === build.epoch, let owner = parent.viewIdentity.installedOwner
        {
            guard build.admitsDescriptor(attribution),
                build.epoch.descriptorOwnerIsCurrent(owner, attribution: attribution),
                build.admitsDescriptor(attribution)
            else { return nil }
            return parent
        }
        guard let attribution = build.descriptorComponent(from: parent.viewIdentity.descriptorComponent) else {
            return nil
        }
        var context = parent
        context.viewIdentity.descriptorComponent = attribution
        context.viewIdentity.installedOwner = nil
        context.viewIdentity.installedEpoch = nil
        return context
    }

    func contextForOwnedCandidateConstruction(from parent: ViewBuildContext) -> ViewBuildContext? {
        guard parent.stateMountCoordinator === self else { return nil }
        guard let attribution = parent.viewIdentity.descriptorComponent else {
            return parent.viewIdentity.candidateConstruction == nil ? parent : nil
        }
        guard parent.viewIdentity.lazyList == nil, let build = currentBuild,
            parent.viewIdentity.installedEpoch === build.epoch, let owner = parent.viewIdentity.installedOwner,
            build.admitsDescriptor(attribution),
            let receipt = build.epoch.currentDescriptorOwnedInstallation(
                for: owner, attribution: attribution, candidateConstruction: parent.viewIdentity.candidateConstruction),
            let construction = attribution.beginOwnedCandidateConstruction(owner: receipt),
            isCurrent(build), build.admitsDescriptor(attribution), construction.canConstruct
        else {
            attribution.rejectConstruction()
            return nil
        }
        var context = parent
        context.viewIdentity.candidateConstruction = construction
        return context
    }

    func contextForOwnedCandidateDeferredSegment(from parent: ViewBuildContext) -> ViewBuildContext? {
        guard let inherited = parent.viewIdentity.candidateConstruction else { return parent }
        guard parent.stateMountCoordinator === self, parent.viewIdentity.lazyList == nil,
            let attribution = parent.viewIdentity.descriptorComponent, let build = currentBuild,
            parent.viewIdentity.installedEpoch === build.epoch, let owner = parent.viewIdentity.installedOwner,
            build.admitsDescriptor(attribution),
            let receipt = build.epoch.currentDescriptorOwnedInstallation(
                for: owner, attribution: attribution, candidateConstruction: inherited),
            let segment = inherited.deferredSegment(owner: receipt, attribution: attribution),
            isCurrent(build), build.admitsDescriptor(attribution), segment.canConstruct
        else {
            parent.viewIdentity.descriptorComponent?.rejectConstruction()
            return nil
        }
        var context = parent
        context.viewIdentity.candidateConstruction = segment
        return context
    }

    func stageDescriptorDependency(
        _ object: any ObservableObject, owner: StateMountOwner,
        attribution: RetainedDescriptorComponentAttribution, group: RetainedDescriptorGroupID
    ) {
        guard let build = currentBuild, build.admitsDescriptor(attribution),
            build.stageDescriptorDependency(object, owner: owner, attribution: attribution, group: group),
            isCurrent(build), build.admitsDescriptor(attribution)
        else { return }
        observeObject(object)
    }

    func descriptorLookupReceipt(for attribution: RetainedDescriptorComponentAttribution) -> LazyListLookupReceipt? {
        guard let build = currentBuild, build.admitsDescriptor(attribution),
            let receipt = DescriptorResolutionReceipt(epoch: build.epoch, native: attribution),
            let lookup = receipt.beginLookup(), build.admitsDescriptor(attribution), lookup.isCurrent
        else { return nil }
        return lookup
    }

    fileprivate func beginSubtreeBuild(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity, anchor: PresentationActivityAnchor,
        lazyRow: LazyListLogicalRow? = nil, originalActivity: RetainedLazyListContributionReceipt? = nil,
        originalDescriptorActivity: RetainedDescriptorContributionReceipt? = nil
    ) -> (any RetainedBuildEpoch)? {
        guard currentBuild == nil, anchor.isActive else { return nil }
        let selectedEpoch: StateMountEpoch?
        if let lazyRow {
            guard let originalActivity, originalActivity.isActive, lazyRow.isDeclared else { return nil }
            selectedEpoch = registry.beginLazySubtreeBuild(
                owner: owner, contentPrefix: contentPrefix, originalActivity: originalActivity)
        } else if let originalDescriptorActivity {
            guard originalActivity == nil, originalDescriptorActivity.isActive else { return nil }
            selectedEpoch = registry.beginDescriptorSubtreeBuild(
                owner: owner, contentPrefix: contentPrefix, originalActivity: originalDescriptorActivity)
        } else {
            guard originalActivity == nil else { return nil }
            selectedEpoch = registry.beginSubtreeBuild(owner: owner, contentPrefix: contentPrefix)
        }
        guard let epoch = selectedEpoch else { return nil }
        guard let activity = presentationActivity.beginBuild(prefix: contentPrefix, boundary: anchor) else {
            epoch.abort()
            registry.finishPendingRetirements()
            return nil
        }
        latestInstallationError = nil
        let build = StateMountBuild(
            coordinator: self, epoch: epoch, activity: activity, replacesRoot: false, subtreePrefix: contentPrefix,
            originalLazyRow: lazyRow, originalLazyActivity: originalActivity,
            originalDescriptorActivity: originalDescriptorActivity)
        currentBuild = build
        return build
    }

    func install<Value>(
        _ source: Value, context: inout ViewBuildContext, isInstalledDelegate: Bool = false
    ) -> Value? {
        guard let build = currentBuild else { return nil }
        let owner: StateMountOwner
        if let attribution = context.viewIdentity.lazyList {
            guard build.canConstructLazy, attribution.admission.isCurrent else { return nil }
            if isInstalledDelegate, context.viewIdentity.installedEpoch === build.epoch,
                let installedOwner = context.viewIdentity.installedOwner
            {
                guard build.epoch.lazyOwnerIsCurrent(installedOwner, attribution: attribution),
                    attribution.admission.isCurrent
                else {
                    return nil
                }
                return source
            }
            guard let selected = build.epoch.lazyOwner(at: context.retainedViewIdentity, attribution: attribution),
                attribution.admission.isCurrent
            else { return nil }
            owner = selected
        } else if let attribution = context.viewIdentity.descriptorComponent {
            guard build.admitsDescriptor(attribution) else { return nil }
            if isInstalledDelegate, context.viewIdentity.installedEpoch === build.epoch,
                let installedOwner = context.viewIdentity.installedOwner
            {
                guard
                    build.epoch.descriptorOwnerIsCurrent(
                        installedOwner, attribution: attribution,
                        candidateConstruction: context.viewIdentity.candidateConstruction),
                    build.admitsDescriptor(attribution)
                else { return nil }
                return source
            }
            guard
                let selected = build.epoch.descriptorOwner(
                    at: context.retainedViewIdentity, attribution: attribution,
                    candidateConstruction: context.viewIdentity.candidateConstruction),
                build.admitsDescriptor(attribution), context.viewIdentity.candidateConstruction?.canConstruct != false
            else { return nil }
            owner = selected
        } else {
            guard build.canAdopt else { return nil }
            if isInstalledDelegate, context.viewIdentity.installedEpoch === build.epoch,
                context.viewIdentity.installedOwner?.isInstallationActive == true
            {
                // A typed delegate received the local copy that the common
                // dispatch already installed.
                return source
            }
            guard let selected = build.epoch.owner(at: context.retainedViewIdentity) else { return nil }
            owner = selected
        }
        context.viewIdentity.installedOwner = owner
        context.viewIdentity.installedEpoch = build.epoch
        return ViewBuildContextScope.withCurrent(context) {
            do {
                return try DynamicPropertyInstaller.install(
                    source, in: owner, candidateConstruction: context.viewIdentity.candidateConstruction)
            } catch let error as DynamicPropertyInstallationError {
                build.supersede()
                if error.reason != .ownerUnavailable {
                    latestInstallationError = error
                    reportInstallationError(error.description)
                }
                return nil
            } catch {
                preconditionFailure("Unexpected dynamic property installation error: \(error)")
            }
        }
    }

    func observe(_ object: any ObservableObject, at identity: RetainedViewIdentity) {
        guard let build = currentBuild, build.canAdopt,
            build.epoch.owner(at: identity) != nil
        else { return }
        build.observations[identity, default: []].insert(ObjectIdentifier(object))
        // Registration can invoke a host hook that closes or supersedes this
        // candidate. The host keeps the old committed subscriptions until an
        // adoption or abandonment publishes the retained dependency set.
        observeObject(object)
    }

    func preserveDeclaredSubtree(at prefix: RetainedViewIdentity) {
        currentBuild?.epoch.preserveDeclaredSubtree(at: prefix)
    }

    func preserveDeclaredScopes(_ scopes: [StateMountDeclarationScope]) {
        for scope in scopes { currentBuild?.epoch.preserveDeclaredScope(scope) }
    }

    func preserveDeclaredSubtree(
        at prefix: RetainedViewIdentity, lazyAttribution: LazyListViewAttribution?,
        descriptorAttribution: RetainedDescriptorComponentAttribution? = nil,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) {
        guard candidateConstruction?.canConstruct != false else { return }
        guard let attribution = lazyAttribution else {
            if let descriptorAttribution {
                guard let build = currentBuild, build.admitsDescriptor(descriptorAttribution) else { return }
                build.epoch.preserveDescriptorDeclaredScopes(
                    [StateMountDeclarationScope(prefix: prefix)], attribution: descriptorAttribution,
                    candidateConstruction: candidateConstruction)
            } else {
                guard candidateConstruction == nil else { return }
                preserveDeclaredSubtree(at: prefix)
            }
            return
        }
        guard candidateConstruction == nil, let build = currentBuild, build.canConstructLazy, attribution.isCurrent
        else { return }
        build.epoch.preserveLazyDeclaredScopes([StateMountDeclarationScope(prefix: prefix)], attribution: attribution)
    }

    func preserveDeclaredScopes(
        _ scopes: [StateMountDeclarationScope], lazyAttribution: LazyListViewAttribution?,
        descriptorAttribution: RetainedDescriptorComponentAttribution? = nil,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) {
        guard candidateConstruction?.canConstruct != false else { return }
        guard let attribution = lazyAttribution else {
            if let descriptorAttribution {
                guard let build = currentBuild, build.admitsDescriptor(descriptorAttribution) else { return }
                build.epoch.preserveDescriptorDeclaredScopes(
                    scopes, attribution: descriptorAttribution, candidateConstruction: candidateConstruction)
            } else {
                guard candidateConstruction == nil else { return }
                preserveDeclaredScopes(scopes)
            }
            return
        }
        guard candidateConstruction == nil, let build = currentBuild, build.canConstructLazy, attribution.isCurrent
        else { return }
        build.epoch.preserveLazyDeclaredScopes(scopes, attribution: attribution)
    }

    func discardUnadoptedSubtree(at prefix: RetainedViewIdentity, preserveCommitted: Bool) {
        guard let build = currentBuild else { return }
        let discard = build.beginOnChangeDiscard(at: prefix)
        defer { build.endOnChangeDiscard(discard) }
        build.activity.discardSubtree(at: prefix) { self.isCurrent(build) && build.canAdopt }
        guard isCurrent(build), build.canAdopt else { return }
        build.discardOnChangeUpdates(at: prefix) { self.isCurrent(build) && build.canAdopt }
        guard isCurrent(build), build.canAdopt else { return }
        build.epoch.discardUnadoptedSubtree(at: prefix, preserveCommitted: preserveCommitted)
        build.observations = build.observations.filter { !$0.key.segments.starts(with: prefix.segments) }
    }

    func discardUnadoptedSubtree(
        at prefix: RetainedViewIdentity, preserveCommitted: Bool, lazyAttribution: LazyListViewAttribution?,
        descriptorAttribution: RetainedDescriptorComponentAttribution? = nil,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) {
        guard candidateConstruction?.canConstruct != false else { return }
        guard let attribution = lazyAttribution else {
            if let descriptorAttribution {
                discardDescriptorSubtree(
                    at: prefix, preserveCommitted: preserveCommitted, attribution: descriptorAttribution,
                    candidateConstruction: candidateConstruction)
            } else {
                guard candidateConstruction == nil else { return }
                discardUnadoptedSubtree(at: prefix, preserveCommitted: preserveCommitted)
            }
            return
        }
        guard candidateConstruction == nil, let build = currentBuild, build.canConstructLazy, attribution.isCurrent,
            let lookup = attribution.admission.beginLookup()
        else { return }
        func isCurrentDiscard() -> Bool { self.isCurrent(build) && build.canConstructLazy && lookup.isCurrent }
        defer { if !lookup.isCurrent { attribution.admission.reject() } }
        let discard = build.beginOnChangeDiscard(at: prefix, isCurrent: isCurrentDiscard)
        defer { build.endOnChangeDiscard(discard) }
        build.rejectLazySelectionFrames(at: prefix, isCurrent: isCurrentDiscard)
        guard isCurrentDiscard() else { return }
        // The registry rejects exact component receipts before any discarded
        // cell or owner can release an application payload. Activity cleanup
        // subsequently removes only unaccepted proposals, not live siblings.
        guard
            let receipt = build.epoch.discardLazySubtree(
                at: prefix, preserveCommitted: preserveCommitted, isCurrent: isCurrentDiscard)
        else {
            return
        }
        defer { build.epoch.finishLazyDiscardScope(receipt) }
        guard isCurrentDiscard() else { return }
        build.activity.discardSubtree(at: prefix, isCurrent: isCurrentDiscard)
        guard isCurrentDiscard() else { return }
        build.discardLazyOnChangeUpdates(at: prefix, isCurrent: isCurrentDiscard)
        guard isCurrentDiscard() else { return }
        build.discardAttributedDependencies(at: prefix, isCurrent: isCurrentDiscard)
        guard isCurrentDiscard() else { return }
        publishObservations(replacesRoot: false)
    }

    private func discardDescriptorSubtree(
        at prefix: RetainedViewIdentity, preserveCommitted: Bool, attribution: RetainedDescriptorComponentAttribution,
        candidateConstruction: RetainedOwnedCandidateConstruction?
    ) {
        guard candidateConstruction?.canConstruct != false,
            let build = currentBuild, build.admitsDescriptor(attribution),
            let lookup = descriptorLookupReceipt(for: attribution)
        else { return }
        func isCurrentDiscard() -> Bool {
            self.isCurrent(build) && build.canConstructLazy && lookup.isCurrent
                && candidateConstruction?.canConstruct != false
        }
        defer {
            if !lookup.isCurrent || candidateConstruction?.canConstruct == false { attribution.rejectConstruction() }
        }
        let discard = build.beginOnChangeDiscard(at: prefix, isCurrent: isCurrentDiscard)
        defer { build.endOnChangeDiscard(discard) }
        build.rejectLazySelectionFrames(at: prefix, isCurrent: isCurrentDiscard)
        guard isCurrentDiscard(),
            let receipt = build.epoch.discardDescriptorSubtree(
                at: prefix, preserveCommitted: preserveCommitted, attribution: attribution, isCurrent: isCurrentDiscard)
        else { return }
        defer { build.epoch.finishLazyDiscardScope(receipt) }
        build.activity.discardSubtree(at: prefix, isCurrent: isCurrentDiscard)
        guard isCurrentDiscard() else { return }
        build.discardDescriptorOnChangeUpdates(at: prefix, isCurrent: isCurrentDiscard)
        guard isCurrentDiscard() else { return }
        build.discardAttributedDependencies(at: prefix, isCurrent: isCurrentDiscard)
        guard isCurrentDiscard() else { return }
        publishObservations(replacesRoot: false)
    }

    /// Materialized modifiers stage work on this build, not on a source value
    /// or a process-wide callsite. Equality and actions wait for adoption.
    func stageOnChange(
        at identity: RetainedViewIdentity, makeUpdate: (StateMountOwner) -> any MountedOnChangeUpdate
    ) {
        guard let build = currentBuild,
            let materialization = build.beginOnChangeMaterialization(at: identity)
        else { return }
        defer { build.endOnChangeMaterialization(materialization) }
        guard build.isCurrent(materialization),
            let owner = build.epoch.syntheticObservationOwner(
                at: identity, isMaterializationCurrent: { build.isCurrent(materialization) }),
            let revision = build.epoch.observationConstructionRevision,
            canStageOnChange(owner: owner, in: build, revision: revision, materialization: materialization)
        else { return }
        let update = makeUpdate(owner)
        guard let revision = build.epoch.observationConstructionRevision,
            canStageOnChange(owner: owner, in: build, revision: revision, materialization: materialization)
        else { return }
        build.stageOnChange(update)
    }

    /// Resolve the bookkeeping cell before entering a provisional adapter,
    /// such as preference reduction. Owner lookup precedes its seed, and a
    /// canceled cell resolution enters neither the adapter nor a precondition.
    func stageOnChange<Observation>(
        at identity: RetainedViewIdentity, seedObservation: () -> Observation,
        makeUpdate: (StateMountOwner, MountedStateCell<Observation>) -> (any MountedOnChangeUpdate)?
    ) {
        guard let build = currentBuild,
            let materialization = build.beginOnChangeMaterialization(at: identity)
        else { return }
        defer { build.endOnChangeMaterialization(materialization) }
        guard build.isCurrent(materialization) else { return }
        guard
            let observation = build.epoch.resolveSyntheticObservation(
                at: identity, isMaterializationCurrent: { build.isCurrent(materialization) }, seed: seedObservation),
            let revision = build.epoch.observationConstructionRevision,
            canStageOnChange(owner: observation.owner, in: build, revision: revision, materialization: materialization)
        else {
            stageOnChangePreservation(at: identity, as: Observation.self, in: build, materialization: materialization)
            return
        }
        guard let update = makeUpdate(observation.owner, observation.cell) else {
            stageOnChangePreservation(at: identity, as: Observation.self, in: build, materialization: materialization)
            return
        }
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(Observation.self)])
        guard build.isCurrent(materialization), let revision = build.epoch.observationConstructionRevision,
            build.epoch.observationCellIsInstalled(
                cell: observation.cell, owner: observation.owner, at: slot, revision: revision,
                isMaterializationCurrent: { build.isCurrent(materialization) }),
            build.epoch.observationConstructionRevision == revision, build.isCurrent(materialization)
        else {
            stageOnChangePreservation(at: identity, as: Observation.self, in: build, materialization: materialization)
            return
        }
        build.stageOnChange(update)
    }

    /// The exact physical proposal accompanies the synthetic cell from before
    /// its seed through publication. A rejected lazy route never uses the
    /// ordinary observation resolver or preserves a whole logical owner.
    func stageOnChange<Observation>(
        at identity: RetainedViewIdentity, attribution: LazyListViewAttribution,
        kind: LazyListSyntheticKind, group: RetainedLazyListGroupID,
        seedObservation: () -> Observation,
        makeUpdate: (StateMountOwner, MountedStateCell<Observation>) -> (any MountedOnChangeUpdate)?
    ) {
        guard let build = currentBuild, attribution.admission.isCurrent,
            let materialization = build.beginOnChangeMaterialization(at: identity, attribution: attribution)
        else { return }
        defer { build.endOnChangeMaterialization(materialization) }
        guard build.isCurrent(materialization),
            let observation = build.epoch.resolveLazySyntheticObservation(
                at: identity, attribution: attribution, kind: kind, group: group, seed: seedObservation),
            build.isCurrent(materialization), attribution.admission.isCurrent
        else { return }
        guard let lookup = attribution.admission.beginLookup(),
            let update = makeManagedOnChangeUpdate(
                owner: observation.owner, cell: observation.cell, makeUpdate: makeUpdate),
            lookup.isCurrent, build.isCurrent(materialization), attribution.admission.isCurrent,
            build.epoch.lazySyntheticCellIsCurrent(
                cell: observation.cell, owner: observation.owner,
                at: StatePropertySlot(concreteTypes: [ObjectIdentifier(Observation.self)]),
                attribution: attribution, group: group),
            lookup.isCurrent, build.isCurrent(materialization), attribution.admission.isCurrent
        else { return }
        build.stageLazyOnChange(update, attribution: attribution, group: group)
    }

    func stageOnChange<Observation>(
        at identity: RetainedViewIdentity, descriptorAttribution: RetainedDescriptorComponentAttribution,
        kind: LazyListSyntheticKind, group: RetainedDescriptorGroupID,
        seedObservation: () -> Observation,
        makeUpdate: (StateMountOwner, MountedStateCell<Observation>) -> (any MountedOnChangeUpdate)?
    ) {
        guard let build = currentBuild, build.admitsDescriptor(descriptorAttribution),
            let materialization = build.beginOnChangeMaterialization(at: identity, descriptor: descriptorAttribution)
        else { return }
        defer { build.endOnChangeMaterialization(materialization) }
        guard build.isCurrent(materialization),
            let observation = build.epoch.resolveDescriptorSyntheticObservation(
                at: identity, attribution: descriptorAttribution, kind: kind, group: group, seed: seedObservation),
            build.isCurrent(materialization), build.admitsDescriptor(descriptorAttribution)
        else { return }
        guard let lookup = descriptorLookupReceipt(for: descriptorAttribution),
            let update = makeManagedOnChangeUpdate(
                owner: observation.owner, cell: observation.cell, makeUpdate: makeUpdate),
            lookup.isCurrent, build.isCurrent(materialization), build.admitsDescriptor(descriptorAttribution),
            build.epoch.descriptorSyntheticCellIsCurrent(
                cell: observation.cell, owner: observation.owner,
                at: StatePropertySlot(concreteTypes: [ObjectIdentifier(Observation.self)]),
                attribution: descriptorAttribution, group: group),
            lookup.isCurrent, build.isCurrent(materialization), build.admitsDescriptor(descriptorAttribution)
        else { return }
        build.stageDescriptorOnChange(update, attribution: descriptorAttribution, group: group)
    }

    /// A reducer or adapter can release authored temporary values while its
    /// callback returns. Keep that cleanup before the caller's receipt check
    /// and publication, even when the callback body is inlined here.
    @inline(never)
    private func makeManagedOnChangeUpdate<Observation>(
        owner: StateMountOwner, cell: MountedStateCell<Observation>,
        makeUpdate: (StateMountOwner, MountedStateCell<Observation>) -> (any MountedOnChangeUpdate)?
    ) -> (any MountedOnChangeUpdate)? {
        makeUpdate(owner, cell)
    }

    private func stageOnChangePreservation<Observation>(
        at identity: RetainedViewIdentity, as type: Observation.Type, in build: StateMountBuild,
        materialization: OnChangeMaterialization
    ) {
        guard build.isCurrent(materialization), isCurrent(build), !build.constructionWasSuperseded,
            build.epoch.observationConstructionRevision != nil,
            let preservation = build.epoch.committedSyntheticObservation(
                at: identity, as: type, isMaterializationCurrent: { build.isCurrent(materialization) }),
            build.isCurrent(materialization), isCurrent(build), !build.constructionWasSuperseded,
            build.epoch.observationConstructionRevision != nil, build.isCurrent(materialization)
        else { return }
        // This marker has the same materialization and parent-discard path as
        // a normal proposal. Looking up a cell alone never preserves a mount.
        build.stageOnChange(OnChangePreservationUpdate(preservation))
    }

    private func canStageOnChange(
        owner: StateMountOwner, in build: StateMountBuild, revision: UInt64, materialization: OnChangeMaterialization
    ) -> Bool {
        build.isCurrent(materialization) && isCurrent(build)
            && build.epoch.observationOwnerIsCurrent(
                owner: owner, revision: revision, isMaterializationCurrent: { build.isCurrent(materialization) })
            && isCurrent(build) && !build.constructionWasSuperseded
            && build.epoch.observationConstructionRevision == revision && build.isCurrent(materialization)
    }

    func subtreeLease(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity
    ) -> any RetainedSubtreeBuildLease {
        let anchor: PresentationActivityAnchor
        if let build = currentBuild, build.canAdopt {
            anchor = build.activity.stageAnchor(owner: owner, contentPrefix: contentPrefix)
        } else {
            anchor = .unavailable(owner: owner, contentPrefix: contentPrefix)
        }
        return StateMountSubtreeLease(
            coordinator: self, owner: owner, contentPrefix: contentPrefix, activityAnchor: anchor)
    }

    enum SubtreeLeasePurpose {
        case geometryReader, lazyList

        var contributionKind: RetainedLazyListContributionKind {
            switch self {
            case .geometryReader: return .deferredSubtree
            case .lazyList: return .lazyList
            }
        }
    }

    func subtreeLease(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity, lazyAttribution: LazyListViewAttribution?,
        descriptorAttribution: RetainedDescriptorComponentAttribution? = nil,
        purpose: SubtreeLeasePurpose = .geometryReader
    ) -> any RetainedSubtreeBuildLease {
        guard let attribution = lazyAttribution else {
            guard let descriptorAttribution else { return subtreeLease(owner: owner, contentPrefix: contentPrefix) }
            let anchor: PresentationActivityAnchor
            if let build = currentBuild, build.admitsDescriptor(descriptorAttribution),
                let group = descriptorAttribution.registerGroup(kind: purpose.contributionKind),
                build.admitsDescriptor(descriptorAttribution)
            {
                anchor = build.activity.stageAnchor(
                    owner: owner, contentPrefix: contentPrefix, descriptorAttribution: descriptorAttribution,
                    group: group)
            } else {
                anchor = .unavailable(owner: owner, contentPrefix: contentPrefix)
            }
            return StateMountSubtreeLease(
                coordinator: self, owner: owner, contentPrefix: contentPrefix, activityAnchor: anchor,
                initialDescriptorAttribution: descriptorAttribution)
        }
        let anchor: PresentationActivityAnchor
        if let build = currentBuild, build.canConstructLazy, attribution.admission.isCurrent,
            let group = attribution.native.registerGroup(kind: purpose.contributionKind),
            attribution.admission.isCurrent
        {
            anchor = build.activity.stageAnchor(
                owner: owner, contentPrefix: contentPrefix, attribution: attribution, group: group)
        } else {
            anchor = .unavailable(owner: owner, contentPrefix: contentPrefix)
        }
        return StateMountSubtreeLease(
            coordinator: self, owner: owner, contentPrefix: contentPrefix, activityAnchor: anchor,
            lazyRow: attribution.logicalRow, initialLazyConstruction: attribution.admission)
    }

    func contextForAdmittedLazySubtree(
        from parent: ViewBuildContext, lease: (any RetainedSubtreeBuildLease)?
    ) -> ViewBuildContext? {
        guard let original = parent.viewIdentity.lazyList else {
            return parent.viewIdentity.descriptorComponent == nil ? parent : nil
        }
        guard parent.stateMountCoordinator === self, parent.viewIdentity.descriptorComponent == nil,
            let lease = lease as? StateMountSubtreeLease, let build = currentBuild,
            lease.admitsLazyBuild(build, from: original), let attribution = build.enteredLazySubtree,
            attribution.admission.isCurrent
        else { return nil }
        var context = parent
        context.viewIdentity.lazyList = attribution
        context.viewIdentity.descriptorComponent = nil
        context.viewIdentity.candidateConstruction = nil
        context.viewIdentity.installedOwner = nil
        context.viewIdentity.installedEpoch = nil
        return context
    }

    func contextForAdmittedDescriptorSubtree(
        from parent: ViewBuildContext, lease: (any RetainedSubtreeBuildLease)?
    ) -> ViewBuildContext? {
        guard parent.stateMountCoordinator === self, parent.viewIdentity.lazyList == nil,
            let original = parent.viewIdentity.descriptorComponent,
            let lease = lease as? StateMountSubtreeLease, let build = currentBuild,
            lease.admitsDescriptorBuild(build, from: original), let attribution = build.descriptorComponent(from: nil),
            build.admitsDescriptor(attribution)
        else { return nil }
        var context = parent
        context.viewIdentity.descriptorComponent = attribution
        context.viewIdentity.installedOwner = nil
        context.viewIdentity.installedEpoch = nil
        // This new scope derives its continuation from the originally admitted
        // reader anchor. A captured token is never reused as build permission.
        switch attribution.ownedCandidateContinuation() {
        case .unscoped:
            guard parent.viewIdentity.candidateConstruction == nil else {
                attribution.rejectConstruction()
                return nil
            }
            context.viewIdentity.candidateConstruction = nil
        case .admitted(let construction):
            context.viewIdentity.candidateConstruction = construction
        case .rejected:
            attribution.rejectConstruction()
            return nil
        }
        guard isCurrent(build), build.admitsDescriptor(attribution),
            context.viewIdentity.candidateConstruction?.canConstruct != false
        else { return nil }
        return context
    }

    func materializeSubtreeLease(_ lease: (any RetainedSubtreeBuildLease)?) {
        guard let lease = lease as? StateMountSubtreeLease, let build = currentBuild, build.canAdopt else { return }
        build.activity.materialize(lease.activityAnchor)
    }

    func sheetDismissal(
        at presentationIdentity: RetainedViewIdentity, configuration: PresentationDismissConfiguration
    ) -> PresentationDismissHandle {
        guard let build = currentBuild, build.canAdopt else { return .unavailable() }
        let identity = presentationIdentity.appending(.view(ObjectIdentifier(PresentationActivityOwner.self)))
        guard let owner = build.epoch.owner(at: identity), isCurrent(build), build.canAdopt else {
            return .unavailable()
        }
        return build.activity.stagePresentation(owner: owner, configuration: configuration)
    }

    func sheetDismissal(
        at presentationIdentity: RetainedViewIdentity, configuration: PresentationDismissConfiguration,
        lazyAttribution: LazyListViewAttribution?,
        descriptorAttribution: RetainedDescriptorComponentAttribution? = nil
    ) -> PresentationDismissHandle {
        guard let attribution = lazyAttribution else {
            guard let descriptorAttribution else {
                return sheetDismissal(at: presentationIdentity, configuration: configuration)
            }
            guard let build = currentBuild, build.admitsDescriptor(descriptorAttribution),
                let group = descriptorAttribution.registerGroup(kind: .presentation),
                build.admitsDescriptor(descriptorAttribution)
            else { return .unavailable() }
            let identity = presentationIdentity.appending(.view(ObjectIdentifier(PresentationActivityOwner.self)))
            guard let owner = build.epoch.descriptorOwner(at: identity, attribution: descriptorAttribution),
                build.admitsDescriptor(descriptorAttribution)
            else { return .unavailable() }
            return build.activity.stagePresentation(
                owner: owner, configuration: configuration, descriptorAttribution: descriptorAttribution, group: group)
        }
        guard let build = currentBuild, build.canConstructLazy, attribution.admission.isCurrent,
            let group = attribution.native.registerGroup(kind: .presentation), attribution.admission.isCurrent
        else { return .unavailable() }
        let identity = presentationIdentity.appending(.view(ObjectIdentifier(PresentationActivityOwner.self)))
        guard let owner = build.epoch.lazyOwner(at: identity, attribution: attribution), attribution.admission.isCurrent
        else { return .unavailable() }
        return build.activity.stagePresentation(
            owner: owner, configuration: configuration, attribution: attribution, group: group)
    }

    func alertDeclaration(
        at identity: RetainedViewIdentity, configuration: RetainedAlertConfiguration?
    ) -> RetainedAlertDeclaration {
        guard let build = currentBuild, build.canAdopt else { return .unavailable() }
        let slotIdentity = identity.appending(.view(ObjectIdentifier(AlertActivityOwner.self)))
        guard let owner = build.epoch.owner(at: slotIdentity), isCurrent(build), build.canAdopt else {
            return .unavailable()
        }
        return build.activity.alerts.stage(owner: owner, configuration: configuration) {
            self.isCurrent(build) && build.canAdopt
        }
    }

    func alertDeclaration(
        at identity: RetainedViewIdentity, configuration: RetainedAlertConfiguration?,
        lazyAttribution: LazyListViewAttribution?,
        descriptorAttribution: RetainedDescriptorComponentAttribution? = nil
    ) -> RetainedAlertDeclaration {
        guard let attribution = lazyAttribution else {
            guard let descriptorAttribution else {
                return alertDeclaration(at: identity, configuration: configuration)
            }
            guard let build = currentBuild, build.admitsDescriptor(descriptorAttribution),
                let group = descriptorAttribution.registerGroup(kind: .alert),
                build.admitsDescriptor(descriptorAttribution)
            else { return .unavailable() }
            let slotIdentity = identity.appending(.view(ObjectIdentifier(AlertActivityOwner.self)))
            guard let owner = build.epoch.descriptorOwner(at: slotIdentity, attribution: descriptorAttribution),
                build.admitsDescriptor(descriptorAttribution)
            else { return .unavailable() }
            return build.activity.alerts.stage(
                owner: owner, configuration: configuration, descriptorAttribution: descriptorAttribution, group: group,
                isCurrent: { self.isCurrent(build) && build.admitsDescriptor(descriptorAttribution) })
        }
        guard let build = currentBuild, build.canConstructLazy, attribution.admission.isCurrent,
            let group = attribution.native.registerGroup(kind: .alert), attribution.admission.isCurrent
        else { return .unavailable() }
        let slotIdentity = identity.appending(.view(ObjectIdentifier(AlertActivityOwner.self)))
        guard let owner = build.epoch.lazyOwner(at: slotIdentity, attribution: attribution),
            attribution.admission.isCurrent
        else { return .unavailable() }
        return build.activity.alerts.stage(
            owner: owner, configuration: configuration, attribution: attribution, group: group,
            isCurrent: { self.isCurrent(build) && build.canConstructLazy && attribution.admission.isCurrent })
    }

    func canEvaluateDeferredSubtree(at contentPrefix: RetainedViewIdentity) -> Bool {
        if let build = currentBuild, build.originalLazyRow != nil {
            guard build.canConstructLazy, let attribution = build.enteredLazySubtree, attribution.admission.isCurrent
            else {
                return false
            }
            let matches =
                build.subtreePrefix?.checkedEquals(
                    contentPrefix,
                    isCurrent: { self.isCurrent(build) && build.canConstructLazy && attribution.admission.isCurrent })
                == true
            return matches && isCurrent(build) && build.canConstructLazy && attribution.admission.isCurrent
        }
        if let build = currentBuild, let original = build.originalDescriptorActivity {
            guard build.canConstructLazy, original.isActive else { return false }
            let matches =
                build.subtreePrefix?.checkedEquals(
                    contentPrefix, isCurrent: { self.isCurrent(build) && build.canConstructLazy && original.isActive })
                == true
            return matches && isCurrent(build) && build.canConstructLazy && original.isActive
        }
        return currentBuild?.subtreePrefix == contentPrefix && currentBuild?.canAdopt == true
    }

    func close() {
        imageServiceAdmissionsClosed = true
        let imageService = ownedAsyncImageService
        imageService?.closeAdmissions()
        let build = currentBuild
        build?.revokeLazyDescriptorsForOwnerClose()
        presentationActivity.closeAdmissions()
        registry.close()
        ownedAsyncImageService = nil
        imageService?.close()
        presentationActivity.releaseClosedPayloads()
        committedObservations.removeAll()
        committedLazyObservations.removeAll()
        committedDescriptorObservations.removeAll()
        build?.observations.removeAll()
        build?.removeLazyDependencies()
        updateObservedObjects([], [], false)
    }

    fileprivate func didCommit(_ build: StateMountBuild, visited: Set<RetainedViewIdentity>) {
        guard currentBuild === build, build.epoch.didCommit, !registry.isClosed else { return }
        build.activity.commit()
        build.commitOnChangeUpdates()
        committedObservations = committedObservations.filter { registry.owner(at: $0.key)?.isLive == true }
        for identity in visited {
            committedObservations[identity] = build.observations[identity] ?? []
        }
        committedDescriptorObservations = committedDescriptorObservations.filter { $0.value.contribution.isActive }
        for (key, dependency) in build.descriptorDependencies where dependency.contribution.isActive {
            committedDescriptorObservations[key] = DescriptorCommittedDependency(
                contribution: dependency.contribution, objects: dependency.objects)
        }
        build.removeLazyDependencies()
        build.observations.removeAll()
        publishObservations(replacesRoot: build.replacesRoot)
    }

    fileprivate func didAbandon(_ build: StateMountBuild) {
        guard currentBuild === build else { return }
        build.observations.removeAll()
        build.removeLazyDependencies()
        publishObservations(replacesRoot: false)
    }

    fileprivate func didCommitLazy(_ build: StateMountBuild, selection: LazyListStateAdoptionSelection) {
        guard currentBuild === build, build.epoch.didCommit, !registry.isClosed else { return }
        build.activity.commitLazyActivity(selection)
        guard currentBuild === build, build.epoch.didCommit, !registry.isClosed else { return }
        build.commitLazyOnChangeUpdates(selection)
        guard currentBuild === build, build.epoch.didCommit, !registry.isClosed else { return }
        let acceptedLazy = selection.acceptedGroups.union(selection.acceptedEmptyGroups)
        let acceptedDescriptors = selection.acceptedOrdinaryGroups.union(selection.acceptedEmptyOrdinaryGroups)
        committedLazyObservations = committedLazyObservations.filter {
            $0.value.contribution.isActive && !selection.retiredGroups.contains($0.key)
        }
        for (key, dependency) in build.lazyDependencies where acceptedLazy.contains(key) {
            guard let contribution = selection.contribution(for: dependency.group), contribution.isActive,
                contribution.physical === dependency.physical
            else {
                continue
            }
            committedLazyObservations[key] = LazyListCommittedDependency(
                contribution: contribution, objects: dependency.objects)
        }
        committedDescriptorObservations = committedDescriptorObservations.filter {
            $0.value.contribution.isActive && !selection.retiredOrdinaryGroups.contains($0.key)
        }
        for (key, dependency) in build.descriptorDependencies where acceptedDescriptors.contains(key) {
            guard let contribution = selection.ordinaryContribution(for: dependency.group), contribution.isActive,
                contribution === dependency.contribution
            else { continue }
            committedDescriptorObservations[key] = DescriptorCommittedDependency(
                contribution: contribution, objects: dependency.objects)
        }
        build.removeLazyDependencies()
        publishObservations(replacesRoot: build.replacesRoot)
    }

    fileprivate func didFinish(_ build: StateMountBuild) {
        guard currentBuild === build else { return }
        build.activity.finish()
        if build.hasLazyActivity {
            registry.finishPendingRetirements()
            build.finishOnChangeUpdates()
            build.finishLazyTransport()
            currentBuild = nil
            return
        }
        currentBuild = nil
        registry.finishPendingRetirements()
        // The runtime's retained-build guard and captured transaction remain
        // active through these actions and displaced-value/callback cleanup.
        // Reentrant reloads queue; they cannot replace this batch in place.
        build.finishOnChangeUpdates()
        build.finishLazyTransport()
    }

    fileprivate func isCurrent(_ build: StateMountBuild) -> Bool {
        currentBuild === build && !registry.isClosed
    }

    fileprivate func canPrepareLazyObservations(_ build: StateMountBuild) -> Bool {
        guard isCurrent(build), build.canConstructLazy, !build.hasLegacyObservations,
            let revision = build.epoch.observationConstructionRevision
        else { return false }
        let result = legacyObservationScopesPermitComposite(build, revision: revision)
        // The local snapshot has released its keys before this check. A
        // destructor or authored prefix comparison cannot lend us a newer
        // operation or insert an unmarked candidate behind the inspection.
        return result && isCurrent(build) && build.canConstructLazy && !build.hasLegacyObservations
            && build.epoch.observationConstructionRevision == revision
    }

    @inline(never)
    private func legacyObservationScopesPermitComposite(_ build: StateMountBuild, revision: UInt64) -> Bool {
        let observations = Array(committedObservations)
        for (identity, objects) in observations where !objects.isEmpty {
            guard isCurrent(build), build.canConstructLazy,
                build.epoch.observationConstructionRevision == revision
            else { return false }
            if build.replacesRoot { return false }
            guard let prefix = build.subtreePrefix else { return false }
            let covered =
                identity.checkedHasPrefix(
                    prefix,
                    isCurrent: {
                        self.isCurrent(build) && build.canConstructLazy
                            && build.epoch.observationConstructionRevision == revision
                    }) == true
            guard isCurrent(build), build.canConstructLazy,
                build.epoch.observationConstructionRevision == revision
            else { return false }
            if covered { return false }
        }
        return true
    }

    private func publishObservations(replacesRoot: Bool) {
        let committed = Set(committedObservations.values.flatMap { $0 }).union(
            committedLazyObservations.values.filter { $0.contribution.isActive }.flatMap { $0.objects }
        ).union(committedDescriptorObservations.values.filter { $0.contribution.isActive }.flatMap { $0.objects })
        let provisional = Set((currentBuild?.observations ?? [:]).values.flatMap { $0 }).union(
            (currentBuild?.lazyDependencies ?? [:]).values.filter { $0.admission.isCurrent }.flatMap { $0.objects }
        ).union(
            (currentBuild?.descriptorDependencies ?? [:]).values.filter { $0.attribution.canConstruct }.flatMap {
                $0.objects
            })
        updateObservedObjects(committed, committed.union(provisional), replacesRoot)
    }
}

private enum PresentationActivityOwner {}
private enum AlertActivityOwner {}

@MainActor
private struct LazyListProvisionalDependency {
    let owner: StateMountOwner
    let group: RetainedLazyListGroupID
    let physical: RetainedLazyListPhysicalActivityReceipt
    let admission: LazyListResolutionReceipt
    var objects: Set<ObjectIdentifier>
}

@MainActor
private struct LazyListCommittedDependency {
    let contribution: RetainedLazyListContributionReceipt
    let objects: Set<ObjectIdentifier>
}

@MainActor
private struct DescriptorProvisionalDependency {
    let owner: StateMountOwner
    let group: RetainedDescriptorGroupID
    let attribution: RetainedDescriptorComponentAttribution
    let contribution: RetainedDescriptorContributionReceipt
    var objects: Set<ObjectIdentifier>
}

@MainActor
private struct DescriptorCommittedDependency {
    let contribution: RetainedDescriptorContributionReceipt
    let objects: Set<ObjectIdentifier>
}

@MainActor
private struct LazyListStagedUpdate {
    let group: RetainedLazyListGroupID
    let physical: RetainedLazyListPhysicalActivityReceipt
    let update: any MountedOnChangeUpdate
}

@MainActor
private struct DescriptorStagedUpdate {
    let group: RetainedDescriptorGroupID
    let contribution: RetainedDescriptorContributionReceipt
    let update: any MountedOnChangeUpdate
}

private enum MountedUpdateOrder {
    case ordinary(ObjectIdentifier)
    case lazy(ObjectIdentifier)
    case descriptor(ObjectIdentifier)
}

/// The frame exists before typed lookup can enter authored Hashable code.
/// Only this exact native preparation may fill it; nested resolutions have
/// their own frame and cannot redirect an earlier context copy.
@MainActor
private final class LazyListSelectedRowResolutionFrame {
    let preparation: RetainedLazyListSelectedRowPreparation
    let receipt: LazyListSelectionResolutionReceipt
    private(set) var reservation: LazyListSelectedRowReservation?
    private var declarationIdentity: RetainedViewIdentity?
    private var enteredAttribution: LazyListViewAttribution?
    private(set) var rejected = false
    private(set) var hasEntered = false

    init(preparation: RetainedLazyListSelectedRowPreparation, receipt: LazyListSelectionResolutionReceipt) {
        self.preparation = preparation
        self.receipt = receipt
    }

    func installDeclarationIdentity(_ identity: RetainedViewIdentity) -> Bool {
        guard !rejected, declarationIdentity == nil, receipt.isCurrent else { return false }
        declarationIdentity = identity
        return true
    }

    func isWithin(_ prefix: RetainedViewIdentity, isCurrent: () -> Bool) -> Bool? {
        guard !rejected, receipt.isCurrent, isCurrent(), let declarationIdentity else { return nil }
        let matches =
            declarationIdentity.checkedHasPrefix(
                prefix, isCurrent: { !self.rejected && self.receipt.isCurrent && isCurrent() }) == true
        guard !rejected, receipt.isCurrent, isCurrent() else { return nil }
        return matches
    }

    func installReservation(_ reservation: LazyListSelectedRowReservation) -> Bool {
        guard !rejected, self.reservation == nil, receipt.isCurrent,
            reservation.preparation === preparation, reservation.resolutionID === preparation.resolutionID
        else { return false }
        self.reservation = reservation
        return true
    }

    func enter(_ attribution: RetainedLazyListBuildAttribution) -> LazyListViewAttribution? {
        guard !rejected, !hasEntered, attribution.resolutionID === preparation.resolutionID,
            preparation.admits(attribution),
            let reservation, let entered = reservation.bindEnteredAttribution(attribution)
        else { return nil }
        hasEntered = true
        enteredAttribution = entered
        return entered
    }

    func reject() {
        guard !rejected else { return }
        rejected = true
        receipt.reject()
        reservation?.reject()
        enteredAttribution?.admission.reject()
    }
}

@MainActor
private final class OnChangeMaterialization {
    let identity: RetainedViewIdentity
    let lazyAttribution: LazyListViewAttribution?
    let descriptorAttribution: RetainedDescriptorComponentAttribution?
    var isDiscarded = false

    init(
        identity: RetainedViewIdentity, lazyAttribution: LazyListViewAttribution? = nil,
        descriptorAttribution: RetainedDescriptorComponentAttribution? = nil
    ) {
        self.identity = identity
        self.lazyAttribution = lazyAttribution
        self.descriptorAttribution = descriptorAttribution
    }
}

@MainActor
private final class OnChangeDiscardScope {
    let prefix: RetainedViewIdentity

    init(prefix: RetainedViewIdentity) { self.prefix = prefix }
}

@MainActor
private protocol MountedOnChangePreservationUpdate: MountedOnChangeUpdate {
    func prepare(in epoch: StateMountEpoch) -> Bool
}

@MainActor
private final class OnChangePreservationUpdate<Observation>: MountedOnChangePreservationUpdate {
    private let preservation: MountedObservationPreservation<Observation>
    var owner: StateMountOwner { preservation.owner }

    init(_ preservation: MountedObservationPreservation<Observation>) {
        self.preservation = preservation
    }

    func prepare(in epoch: StateMountEpoch) -> Bool { preservation.prepare(in: epoch) }
    func commit() {}
    func deliver() {}
}

// These existing leaves have a no-op DynamicProperty.update and manage their
// own legacy mechanisms. They are not mount-owned by State/StateObject installation;
// inspecting their private implementation boxes would invent ownership.
extension SwiftWindowsCore.Binding: NonOwningDynamicProperty {}
extension ObservedObject: NonOwningDynamicProperty {}
extension Environment: NonOwningDynamicProperty {}
extension EnvironmentObject: NonOwningDynamicProperty {}
extension FocusedValue: NonOwningDynamicProperty {}
extension FocusedBinding: NonOwningDynamicProperty {}
extension FocusedObject: NonOwningDynamicProperty {}
extension Bindable: NonOwningDynamicProperty {}
extension AppStorage: NonOwningDynamicProperty {}
extension SceneStorage: NonOwningDynamicProperty {}
extension ScaledMetric: NonOwningDynamicProperty {}
extension FocusState: NonOwningDynamicProperty {}
extension GestureState: NonOwningDynamicProperty {}
extension AccessibilityFocusState: NonOwningDynamicProperty {}
extension Namespace: NonOwningDynamicProperty {}
extension Query: NonOwningDynamicProperty {}
extension FetchRequest: NonOwningDynamicProperty {}
extension SectionedFetchRequest: NonOwningDynamicProperty {}
extension FileDocumentConfiguration: NonOwningDynamicProperty {}
extension ReferenceFileDocumentConfiguration: NonOwningDynamicProperty {}

@MainActor
private final class StateMountBuild: RetainedBuildEpoch, RetainedLazyListBuildActivity {
    private weak var coordinator: StateMountCoordinator?
    let epoch: StateMountEpoch
    let activity: PresentationActivityBuild
    let replacesRoot: Bool
    let subtreePrefix: RetainedViewIdentity?
    var observations: [RetainedViewIdentity: Set<ObjectIdentifier>] = [:]
    private var onChangeUpdates: [ObjectIdentifier: any MountedOnChangeUpdate] = [:]
    private var onChangeOrder: [ObjectIdentifier] = []
    private var discardedOnChangeUpdates: [any MountedOnChangeUpdate] = []
    private var onChangeMaterializations: [ObjectIdentifier: OnChangeMaterialization] = [:]
    private var onChangeDiscardScopes: [OnChangeDiscardScope] = []
    private var descriptorScope: RetainedLazyListDescriptorBuildScope?
    private var lazyConstructionStack: [LazyListViewAttribution] = []
    private var lazySelectionFrames: [ObjectIdentifier: LazyListSelectedRowResolutionFrame] = [:]
    private var lazyUpdates: [ObjectIdentifier: LazyListStagedUpdate] = [:]
    private var descriptorUpdates: [ObjectIdentifier: DescriptorStagedUpdate] = [:]
    private var updateOrder: [MountedUpdateOrder] = []
    private var lazyPreparation: RetainedLazyListAdoptionPreparation?
    private var lazySelection: LazyListStateAdoptionSelection?
    private var committedLazyUpdates: [ObjectIdentifier: RetainedLazyListContributionReceipt] = [:]
    private var committedDescriptorUpdates: [ObjectIdentifier: RetainedDescriptorContributionReceipt] = [:]
    private var didFinishLazyTransport = false
    private(set) var lazyDependencies: [ObjectIdentifier: LazyListProvisionalDependency] = [:]
    private(set) var descriptorDependencies: [ObjectIdentifier: DescriptorProvisionalDependency] = [:]
    private(set) var hasLazyActivity = false
    private(set) var originalLazyRow: LazyListLogicalRow?
    let originalLazyActivity: RetainedLazyListContributionReceipt?
    let originalDescriptorActivity: RetainedDescriptorContributionReceipt?
    private(set) var constructionWasSuperseded = false
    private var hasFinished = false

    init(
        coordinator: StateMountCoordinator, epoch: StateMountEpoch, activity: PresentationActivityBuild,
        replacesRoot: Bool,
        subtreePrefix: RetainedViewIdentity? = nil,
        originalLazyRow: LazyListLogicalRow? = nil,
        originalLazyActivity: RetainedLazyListContributionReceipt? = nil,
        originalDescriptorActivity: RetainedDescriptorContributionReceipt? = nil
    ) {
        self.coordinator = coordinator
        self.epoch = epoch
        self.activity = activity
        self.replacesRoot = replacesRoot
        self.subtreePrefix = subtreePrefix
        self.originalLazyRow = originalLazyRow
        self.originalLazyActivity = originalLazyActivity
        self.originalDescriptorActivity = originalDescriptorActivity
        hasLazyActivity = originalLazyRow != nil
    }

    var canAdopt: Bool {
        if hasLazyActivity { return canConstructLazy }
        return epoch.canAdopt && activity.canConstruct
    }
    var canComplete: Bool { epoch.didCommit && coordinator?.registry.isClosed == false }
    var hasLegacyObservations: Bool { observations.values.contains { !$0.isEmpty } }

    var canConstructLazy: Bool {
        !hasFinished && !constructionWasSuperseded && coordinator?.isCurrent(self) == true
            && activity.canConstruct && epoch.observationConstructionRevision != nil
    }

    private var canFinishLazyPreparation: Bool {
        guard !hasFinished, !constructionWasSuperseded, coordinator?.isCurrent(self) == true,
            let descriptorScope
        else { return false }
        // Native beginAdoption consumes our prepared response before it can
        // advance this scope from construction to descriptor publication.
        return (descriptorScope.canConstructDescriptors || descriptorScope.canPublishDescriptors)
            && (epoch.observationConstructionRevision != nil || epoch.isAdopting)
    }

    var descriptorScopeWasBound: Bool { descriptorScope != nil }

    func rootContentDescriptor() -> RetainedDescriptorComponentAttribution? {
        guard replacesRoot, descriptorScope?.origin == .componentHostRoot else { return nil }
        return descriptorComponent(from: nil)
    }

    func admitsDescriptor(_ attribution: RetainedDescriptorComponentAttribution) -> Bool {
        canConstructLazy && descriptorScope?.attempt === attribution.attempt && attribution.canConstruct
    }

    func descriptorComponent(
        from parent: RetainedDescriptorComponentAttribution?
    ) -> RetainedDescriptorComponentAttribution? {
        guard canConstructLazy, let descriptorScope, descriptorScope.canConstructDescriptors else { return nil }
        if let parent {
            guard admitsDescriptor(parent), let child = parent.registerChildComponent(), admitsDescriptor(child) else {
                return nil
            }
            return child
        }
        guard let component = descriptorScope.registerOrdinaryComponent(), admitsDescriptor(component) else {
            return nil
        }
        return component
    }

    func descriptorResolutionReceipt(
        owner: StateMountOwner, attribution: LazyListViewAttribution?,
        descriptorAttribution: RetainedDescriptorComponentAttribution?
    ) -> LazyListDescriptorResolutionReceipt? {
        guard canConstructLazy, let descriptorScope, descriptorScope.canConstructDescriptors else { return nil }
        if let descriptorAttribution {
            guard attribution == nil, admitsDescriptor(descriptorAttribution) else { return nil }
        }
        let scope: RetainedLazyListDescriptorBuildScope
        if let attribution {
            guard attribution.admission.isCurrent,
                let containing = descriptorScope.withContainingRow(attribution.native), attribution.admission.isCurrent
            else { return nil }
            scope = containing
        } else {
            scope = descriptorScope
        }
        return LazyListDescriptorResolutionReceipt(
            epoch: epoch, owner: owner, nativeScope: scope, containingAttribution: attribution,
            containingDescriptor: descriptorAttribution)
    }

    func bindLazyListDescriptorScope(_ scope: RetainedLazyListDescriptorBuildScope) -> Bool {
        guard canConstructLazy, scope.canConstructDescriptors else { return false }
        if let descriptorScope { return descriptorScope === scope }
        guard epoch.bindNativeDescriptorScope(scope) else { return false }
        descriptorScope = scope
        return true
    }

    func resolveSelectedLazyListRow(
        _ preparation: RetainedLazyListSelectedRowPreparation
    ) -> RetainedLazyListSelectedRowResolution? {
        guard canConstructLazy, preparation.isCurrent,
            let receipt = LazyListSelectionResolutionReceipt(epoch: epoch, nativePreparation: preparation),
            receipt.isCurrent, let lookup = receipt.beginLookup()
        else { return nil }
        let key = ObjectIdentifier(preparation.resolutionID)
        guard lazySelectionFrames[key] == nil else { return nil }
        let frame = LazyListSelectedRowResolutionFrame(preparation: preparation, receipt: receipt)
        // ObjectIdentifier has no authored hashing. Publish the unkeyed frame
        // before the registry enters typed key/occurrence resolution.
        lazySelectionFrames[key] = frame
        hasLazyActivity = true
        guard let identity = epoch.lazySelectionDeclarationIdentity(for: preparation),
            canConstructLazy, receipt.isCurrent, lookup.isCurrent, frame.installDeclarationIdentity(identity)
        else {
            frame.reject()
            return nil
        }
        let discards = onChangeDiscardScopes
        for discard in discards {
            guard let matches = frame.isWithin(discard.prefix, isCurrent: { lookup.isCurrent }),
                canConstructLazy, lookup.isCurrent
            else {
                frame.reject()
                return nil
            }
            if matches {
                frame.reject()
                return nil
            }
        }
        guard lookup.isCurrent, let coordinator,
            let reservation = coordinator.registry.resolveSelectedLazyRow(
                preparation, in: epoch, receipt: receipt, lookup: lookup),
            canConstructLazy, receipt.isCurrent, lookup.isCurrent, lazySelectionFrames[key] === frame,
            frame.installReservation(reservation)
        else {
            frame.reject()
            return nil
        }
        return reservation.nativeResolution
    }

    func enterLazyListMaterialization(_ attribution: RetainedLazyListBuildAttribution) -> Bool {
        guard canConstructLazy, attribution.constructionState == .admittedForConstruction else { return false }
        let entered: LazyListViewAttribution
        switch attribution.origin {
        case .selectedRow:
            guard let frame = lazySelectionFrames[ObjectIdentifier(attribution.resolutionID)],
                let selected = frame.enter(attribution)
            else { return false }
            entered = selected
        case .deferredSubtree(let originalContribution):
            guard originalContribution === originalLazyActivity, originalContribution.isActive,
                let originalLazyRow, originalLazyRow.logicalReceipt === attribution.logicalMembership,
                originalContribution.physical === attribution.physical, originalLazyRow.isDeclared,
                let receipt = LazyListResolutionReceipt(epoch: epoch, native: attribution), receipt.isCurrent
            else { return false }
            entered = LazyListViewAttribution(
                native: attribution, logicalRow: originalLazyRow, component: attribution.component, admission: receipt)
        }
        guard entered.admission.isCurrent, canConstructLazy else { return false }
        lazyConstructionStack.append(entered)
        hasLazyActivity = true
        return true
    }

    func leaveLazyListMaterialization(_ attribution: RetainedLazyListBuildAttribution) {
        guard lazyConstructionStack.last?.native === attribution else {
            rejectLazyConstruction()
            return
        }
        lazyConstructionStack.removeLast()
    }

    func enteredLazyRow(
        for descriptor: RetainedLazyListManagedLogicalDescriptorBinding
    ) -> LazyListViewAttribution? {
        guard canConstructLazy, let entered = lazyConstructionStack.last, entered.admission.isCurrent,
            let frame = lazySelectionFrames[ObjectIdentifier(entered.native.resolutionID)],
            !frame.rejected, frame.preparation.descriptor === descriptor, frame.hasEntered
        else { return nil }
        return entered
    }

    var enteredLazySubtree: LazyListViewAttribution? {
        guard canConstructLazy, let entered = lazyConstructionStack.last, entered.admission.isCurrent,
            case .deferredSubtree(let activity) = entered.native.origin,
            activity === originalLazyActivity, activity.isActive
        else { return nil }
        return entered
    }

    func willAdoptLazyList(
        _ preparation: RetainedLazyListAdoptionPreparation
    ) -> RetainedLazyListPreparedActivity? {
        guard canConstructLazy, lazyPreparation == nil, lazyConstructionStack.isEmpty,
            onChangeUpdates.isEmpty, let coordinator, coordinator.canPrepareLazyObservations(self),
            let plans = epoch.prepareLazyMembershipPlans(preparation), canConstructLazy,
            activity.prepareLazyActivity(preparation, isCurrent: { self.canConstructLazy })
        else { return nil }
        // Each successful prepare closes its construction phase. Check the
        // original publication authority across this handoff, not the now
        // intentionally closed activity/epoch construction predicates.
        guard canFinishLazyPreparation, onChangeUpdates.isEmpty, !hasLegacyObservations,
            epoch.prepareLazyAdoption(preparation, isCurrent: { self.canFinishLazyPreparation }),
            canFinishLazyPreparation,
            onChangeUpdates.isEmpty, !hasLegacyObservations
        else { return nil }
        // Raw manual observation records have no native contribution proof.
        // They must reject before mutation, while the ordinary full-adoption
        // route continues to support its existing preservation markers.
        hasLazyActivity = true
        lazyPreparation = preparation
        return RetainedLazyListPreparedActivity(
            preparation: preparation, logicalMembershipPlans: plans,
            ownedComponentPlans: preparation.ownedComponentDeclarations)
    }

    func commitLazyList(_ disposition: RetainedLazyListAdoptionDisposition) {
        guard !hasFinished, lazySelection == nil, lazyPreparation?.attempt === disposition.attempt,
            let selection = epoch.commitLazyAdoption(disposition)
        else { return }
        lazySelection = selection
        if let coordinator {
            for frame in lazySelectionFrames.values {
                guard !hasFinished, coordinator.isCurrent(self) else { break }
                if let reservation = frame.reservation {
                    _ = coordinator.registry.commitLazySparseRow(reservation, selection: selection)
                }
            }
            coordinator.didCommitLazy(self, selection: selection)
        }
    }

    func revokeLazyDescriptorsForOwnerClose() {
        // Native scalar transport precedes registry and captured payload cleanup.
        // Owner close revokes every phase; normal request supersession does not.
        descriptorScope?.revokeForOwnerClose()
        rejectLazyConstruction()
    }

    private func rejectLazyConstruction() {
        for frame in lazySelectionFrames.values { frame.reject() }
        for attribution in lazyConstructionStack { attribution.admission.reject() }
    }

    func rejectLazySelectionFrames(at prefix: RetainedViewIdentity, isCurrent: () -> Bool = { true }) {
        let frames = Array(lazySelectionFrames.values)
        for frame in frames where !frame.rejected {
            guard canConstructLazy, isCurrent() else { return }
            guard let matches = frame.isWithin(prefix, isCurrent: isCurrent), canConstructLazy, isCurrent() else {
                frame.reject()
                continue
            }
            if matches { frame.reject() }
        }
        withExtendedLifetime(frames) {}
    }

    private var canConstructOnChange: Bool {
        coordinator?.isCurrent(self) == true && !constructionWasSuperseded
            && activity.canConstruct && epoch.observationConstructionRevision != nil
    }

    func isCurrent(_ materialization: OnChangeMaterialization) -> Bool {
        guard !materialization.isDiscarded, canConstructOnChange else { return false }
        if let attribution = materialization.lazyAttribution, !attribution.isCurrent { return false }
        if let attribution = materialization.descriptorAttribution, !admitsDescriptor(attribution) { return false }
        return true
    }

    func beginOnChangeMaterialization(
        at identity: RetainedViewIdentity, attribution: LazyListViewAttribution? = nil,
        descriptor: RetainedDescriptorComponentAttribution? = nil
    ) -> OnChangeMaterialization? {
        guard canConstructOnChange, let revision = epoch.observationConstructionRevision else { return nil }
        let lookup: LazyListLookupReceipt?
        if let attribution {
            guard descriptor == nil, let original = attribution.admission.beginLookup() else { return nil }
            lookup = original
        } else if let descriptor {
            guard admitsDescriptor(descriptor),
                let receipt = DescriptorResolutionReceipt(epoch: epoch, native: descriptor),
                let original = receipt.beginLookup()
            else { return nil }
            lookup = original
        } else {
            lookup = nil
        }
        let materialization = OnChangeMaterialization(
            identity: identity, lazyAttribution: attribution, descriptorAttribution: descriptor)
        let isCurrentLookup = {
            self.isCurrent(materialization) && self.epoch.observationConstructionRevision == revision
                && lookup?.isCurrent != false
        }
        let admitted = registerOnChangeMaterialization(materialization, isCurrent: isCurrentLookup)
        // The comparison scope has released its snapshots before an owner
        // lookup may start. Reentrant equality or cleanup cannot lend that
        // next lookup a newer map revision for this older materialization.
        guard admitted, isCurrentLookup() else {
            materialization.isDiscarded = true
            endOnChangeMaterialization(materialization)
            return nil
        }
        return materialization
    }

    @inline(never)
    private func registerOnChangeMaterialization(
        _ materialization: OnChangeMaterialization, isCurrent: () -> Bool
    ) -> Bool {
        guard isCurrent() else { return false }
        onChangeMaterializations[ObjectIdentifier(materialization)] = materialization
        // Register before comparing prefixes: authored equality can reenter
        // another discard, which must be able to revoke this same attempt.
        let scopes = onChangeDiscardScopes
        for scope in scopes {
            guard let matches = materialization.identity.checkedHasPrefix(scope.prefix, isCurrent: isCurrent),
                isCurrent()
            else { return false }
            if matches {
                materialization.isDiscarded = true
                return false
            }
        }
        return isCurrent()
    }

    func endOnChangeMaterialization(_ materialization: OnChangeMaterialization) {
        onChangeMaterializations.removeValue(forKey: ObjectIdentifier(materialization))
    }

    func beginOnChangeDiscard(
        at prefix: RetainedViewIdentity, isCurrent: () -> Bool = { true }
    ) -> OnChangeDiscardScope {
        let scope = OnChangeDiscardScope(prefix: prefix)
        onChangeDiscardScopes.append(scope)
        let materializations = Array(onChangeMaterializations.values)
        for materialization in materializations where !materialization.isDiscarded {
            guard canConstructOnChange, isCurrent() else { return scope }
            let matches =
                materialization.identity.checkedHasPrefix(
                    prefix, isCurrent: { self.canConstructOnChange && isCurrent() }) == true
            guard canConstructOnChange, isCurrent() else { return scope }
            if matches { materialization.isDiscarded = true }
        }
        return scope
    }

    func endOnChangeDiscard(_ scope: OnChangeDiscardScope) {
        onChangeDiscardScopes.removeAll { $0 === scope }
    }

    func stageOnChange(_ update: any MountedOnChangeUpdate) {
        let key = ObjectIdentifier(update.owner)
        if let previous = onChangeUpdates.updateValue(update, forKey: key) {
            // A measured or repeated materialization can be replaced. Keep its
            // application captures until the guarded build finish, without an
            // action or baseline change from the discarded proposal.
            discardedOnChangeUpdates.append(previous)
        } else {
            onChangeOrder.append(key)
            updateOrder.append(.ordinary(key))
        }
    }

    func stageLazyOnChange(
        _ update: any MountedOnChangeUpdate, attribution: LazyListViewAttribution, group: RetainedLazyListGroupID
    ) {
        guard canConstructLazy, attribution.admission.isCurrent else { return }
        let key = ObjectIdentifier(group)
        if let previous = lazyUpdates[key] {
            discardedOnChangeUpdates.append(previous.update)
        } else {
            updateOrder.append(.lazy(key))
        }
        lazyUpdates[key] = LazyListStagedUpdate(group: group, physical: attribution.native.physical, update: update)
        hasLazyActivity = true
    }

    func stageDescriptorOnChange(
        _ update: any MountedOnChangeUpdate, attribution: RetainedDescriptorComponentAttribution,
        group: RetainedDescriptorGroupID
    ) {
        guard admitsDescriptor(attribution), let contribution = attribution.contribution(for: group) else { return }
        let key = ObjectIdentifier(group)
        if let previous = descriptorUpdates[key] {
            discardedOnChangeUpdates.append(previous.update)
        } else {
            updateOrder.append(.descriptor(key))
        }
        descriptorUpdates[key] = DescriptorStagedUpdate(group: group, contribution: contribution, update: update)
    }

    func stageLazyDependency(
        _ object: any ObservableObject, owner: StateMountOwner,
        attribution: LazyListViewAttribution, group: RetainedLazyListGroupID
    ) -> Bool {
        guard canConstructLazy, attribution.admission.isCurrent,
            epoch.lazyOwnerIsCurrent(owner, attribution: attribution), attribution.admission.isCurrent
        else { return false }
        let key = ObjectIdentifier(group)
        if var existing = lazyDependencies[key] {
            guard existing.owner === owner, existing.physical === attribution.native.physical,
                existing.admission === attribution.admission
            else { return false }
            existing.objects.insert(ObjectIdentifier(object))
            lazyDependencies[key] = existing
        } else {
            lazyDependencies[key] = LazyListProvisionalDependency(
                owner: owner, group: group, physical: attribution.native.physical,
                admission: attribution.admission, objects: [ObjectIdentifier(object)])
        }
        hasLazyActivity = true
        return true
    }

    func removeLazyDependencies() {
        lazyDependencies.removeAll()
        descriptorDependencies.removeAll()
    }

    func stageDescriptorDependency(
        _ object: any ObservableObject, owner: StateMountOwner,
        attribution: RetainedDescriptorComponentAttribution, group: RetainedDescriptorGroupID
    ) -> Bool {
        guard admitsDescriptor(attribution), epoch.descriptorOwnerIsCurrent(owner, attribution: attribution),
            admitsDescriptor(attribution), let contribution = attribution.contribution(for: group)
        else { return false }
        let key = ObjectIdentifier(group)
        if var existing = descriptorDependencies[key] {
            guard existing.owner === owner, existing.contribution === contribution, existing.attribution === attribution
            else { return false }
            existing.objects.insert(ObjectIdentifier(object))
            descriptorDependencies[key] = existing
        } else {
            descriptorDependencies[key] = DescriptorProvisionalDependency(
                owner: owner, group: group, attribution: attribution,
                contribution: contribution, objects: [ObjectIdentifier(object)])
        }
        return true
    }

    func discardOnChangeUpdates(at prefix: RetainedViewIdentity, isCurrent: () -> Bool) {
        let updates = Array(onChangeUpdates.values)
        var removed: Set<ObjectIdentifier> = []
        for update in updates {
            let matches = update.owner.identity.checkedHasPrefix(prefix, isCurrent: isCurrent) == true
            // Explicit identity equality can run application code.
            guard isCurrent() else { return }
            if matches { removed.insert(ObjectIdentifier(update.owner)) }
        }
        for key in removed {
            if let update = onChangeUpdates.removeValue(forKey: key) {
                discardedOnChangeUpdates.append(update)
            }
        }
        onChangeOrder.removeAll { removed.contains($0) }
        updateOrder.removeAll {
            if case .ordinary(let key) = $0 { return removed.contains(key) }
            return false
        }
    }

    func discardLazyOnChangeUpdates(at prefix: RetainedViewIdentity, isCurrent: () -> Bool) {
        let staged = Array(lazyUpdates)
        var removed: Set<ObjectIdentifier> = []
        for (key, entry) in staged {
            guard isCurrent() else { return }
            let matches = entry.update.owner.identity.checkedHasPrefix(prefix, isCurrent: isCurrent) == true
            guard isCurrent() else { return }
            if matches { removed.insert(key) }
        }
        for key in removed {
            if let entry = lazyUpdates.removeValue(forKey: key) { discardedOnChangeUpdates.append(entry.update) }
        }
        updateOrder.removeAll {
            if case .lazy(let key) = $0 { return removed.contains(key) }
            return false
        }
        withExtendedLifetime(staged) {}
    }

    func discardDescriptorOnChangeUpdates(at prefix: RetainedViewIdentity, isCurrent: () -> Bool) {
        let staged = Array(descriptorUpdates)
        var removed: Set<ObjectIdentifier> = []
        for (key, entry) in staged {
            guard isCurrent() else { return }
            let matches = entry.update.owner.identity.checkedHasPrefix(prefix, isCurrent: isCurrent) == true
            guard isCurrent() else { return }
            if matches { removed.insert(key) }
        }
        for key in removed {
            if let entry = descriptorUpdates.removeValue(forKey: key) { discardedOnChangeUpdates.append(entry.update) }
        }
        updateOrder.removeAll {
            if case .descriptor(let key) = $0 { return removed.contains(key) }
            return false
        }
        withExtendedLifetime(staged) {}
    }

    func discardAttributedDependencies(at prefix: RetainedViewIdentity, isCurrent: () -> Bool) {
        let lazy = Array(lazyDependencies)
        let descriptors = Array(descriptorDependencies)
        var removedLazy: Set<ObjectIdentifier> = []
        var removedDescriptors: Set<ObjectIdentifier> = []
        for (key, entry) in lazy {
            guard isCurrent() else { return }
            let matches = entry.owner.identity.checkedHasPrefix(prefix, isCurrent: isCurrent) == true
            guard isCurrent() else { return }
            if matches { removedLazy.insert(key) }
        }
        for (key, entry) in descriptors {
            guard isCurrent() else { return }
            let matches = entry.owner.identity.checkedHasPrefix(prefix, isCurrent: isCurrent) == true
            guard isCurrent() else { return }
            if matches { removedDescriptors.insert(key) }
        }
        for key in removedLazy { lazyDependencies.removeValue(forKey: key) }
        for key in removedDescriptors { descriptorDependencies.removeValue(forKey: key) }
        withExtendedLifetime((lazy, descriptors)) {}
    }

    func commitOnChangeUpdates() {
        guard canComplete else { return }
        // Every adopted value is published before the first comparator or
        // action. These commits retain displaced values and run no app code.
        for entry in updateOrder {
            switch entry {
            case .ordinary(let key): onChangeUpdates[key]?.commit()
            case .descriptor(let key):
                guard let staged = descriptorUpdates[key], staged.contribution.isActive else { continue }
                committedDescriptorUpdates[key] = staged.contribution
                staged.update.commit()
            case .lazy: continue
            }
        }
    }

    func commitLazyOnChangeUpdates(_ selection: LazyListStateAdoptionSelection) {
        guard canComplete else { return }
        let accepted = selection.acceptedGroups.union(selection.acceptedEmptyGroups)
        let acceptedOrdinary = selection.acceptedOrdinaryGroups.union(selection.acceptedEmptyOrdinaryGroups)
        for entry in updateOrder {
            switch entry {
            case .lazy(let key):
                guard accepted.contains(key), let staged = lazyUpdates[key],
                    let contribution = selection.contribution(for: staged.group), contribution.isActive,
                    contribution.physical === staged.physical
                else { continue }
                committedLazyUpdates[key] = contribution
                staged.update.commit()
            case .descriptor(let key):
                guard acceptedOrdinary.contains(key), let staged = descriptorUpdates[key],
                    let contribution = selection.ordinaryContribution(for: staged.group), contribution.isActive,
                    contribution === staged.contribution
                else { continue }
                committedDescriptorUpdates[key] = contribution
                staged.update.commit()
            case .ordinary: continue
            }
        }
    }

    func finishOnChangeUpdates() {
        if lazySelection != nil {
            finishSelectedLazyUpdates()
            return
        }
        let updates: [(update: any MountedOnChangeUpdate, descriptor: RetainedDescriptorContributionReceipt?)] =
            updateOrder.compactMap { entry in
                switch entry {
                case .ordinary(let key): return onChangeUpdates[key].map { ($0, nil) }
                case .descriptor(let key):
                    guard let staged = descriptorUpdates[key], let receipt = committedDescriptorUpdates[key] else {
                        return nil
                    }
                    return (staged.update, receipt)
                case .lazy: return nil
                }
            }
        let original = onChangeUpdates
        let described = descriptorUpdates
        let discarded = discardedOnChangeUpdates
        onChangeUpdates = [:]
        onChangeOrder = []
        descriptorUpdates = [:]
        committedDescriptorUpdates = [:]
        discardedOnChangeUpdates = []
        updateOrder = []
        if canComplete {
            for record in updates where record.descriptor?.isActive != false { record.update.deliver() }
        }
        // Release both accepted and abandoned captures outside property
        // mutation, while the enclosing retained build still serializes work.
        withExtendedLifetime((updates, original, described, discarded)) {}
    }

    private func finishSelectedLazyUpdates() {
        let ordered = updateOrder
        let ordinary = onChangeUpdates
        let lazy = lazyUpdates
        let described = descriptorUpdates
        let accepted = committedLazyUpdates
        let acceptedDescriptors = committedDescriptorUpdates
        let discarded = discardedOnChangeUpdates
        updateOrder = []
        onChangeUpdates = [:]
        onChangeOrder = []
        lazyUpdates = [:]
        descriptorUpdates = [:]
        committedLazyUpdates = [:]
        committedDescriptorUpdates = [:]
        discardedOnChangeUpdates = []
        if canComplete {
            for entry in ordered {
                switch entry {
                case .lazy(let key):
                    guard let contribution = accepted[key], contribution.isActive else { continue }
                    lazy[key]?.update.deliver()
                case .descriptor(let key):
                    guard let contribution = acceptedDescriptors[key], contribution.isActive else { continue }
                    described[key]?.update.deliver()
                case .ordinary: continue
                }
            }
        }
        // Rejected proposals still retain their entire captured values until
        // this guarded finish. They neither compare nor advance a baseline.
        withExtendedLifetime((ordinary, lazy, described, accepted, acceptedDescriptors, discarded)) {}
    }

    func finishLazyTransport() {
        guard !didFinishLazyTransport else { return }
        didFinishLazyTransport = true
        let retained = (
            frames: lazySelectionFrames, stack: lazyConstructionStack, updates: lazyUpdates,
            describedUpdates: descriptorUpdates, selection: lazySelection, preparation: lazyPreparation,
            scope: descriptorScope, originalRow: originalLazyRow
        )
        lazySelectionFrames = [:]
        lazyConstructionStack = []
        lazyUpdates = [:]
        descriptorUpdates = [:]
        lazySelection = nil
        lazyPreparation = nil
        descriptorScope = nil
        lazyDependencies = [:]
        descriptorDependencies = [:]
        committedLazyUpdates = [:]
        committedDescriptorUpdates = [:]
        originalLazyRow = nil
        epoch.finishManagedTransport()
        withExtendedLifetime(retained) {}
    }

    func supersede() {
        // The final staging check must not invoke user Hashable code again.
        // This local receipt mirrors the existing construction cancellation;
        // it does not revoke a build's already-adopted completion.
        constructionWasSuperseded = true
        descriptorScope?.stopConstruction()
        rejectLazyConstruction()
        epoch.supersede()
    }
    func willAdopt() -> Bool {
        guard let coordinator,
            activity.prepare(isCurrent: { coordinator.isCurrent(self) && self.epoch.canAdopt }),
            prepareOnChangePreservations()
        else { return false }
        return epoch.prepareForAdoption()
    }

    private func prepareOnChangePreservations() -> Bool {
        for key in onChangeOrder {
            if let marker = onChangeUpdates[key] as? any MountedOnChangePreservationUpdate,
                !marker.prepare(in: epoch)
            {
                return false
            }
        }
        return true
    }

    func commit() {
        let visited = epoch.visitedOwnerIdentities
        epoch.commitAdoption()
        coordinator?.didCommit(self, visited: visited)
    }

    func abandon() {
        descriptorScope?.stopConstruction()
        rejectLazyConstruction()
        activity.abandon()
        epoch.abort()
        coordinator?.didAbandon(self)
    }

    func finishAfterCallbacks() {
        guard !hasFinished else { return }
        descriptorScope?.stopConstruction()
        hasFinished = true
        if let coordinator {
            coordinator.didFinish(self)
        } else {
            activity.finish()
            finishOnChangeUpdates()
            finishLazyTransport()
        }
    }
}

@MainActor
private final class StateMountRequest: RetainedBuildRequest {
    private weak var registry: StateMountRegistry?
    private let revision: UInt64

    init(registry: StateMountRegistry, revision: UInt64) {
        self.registry = registry
        self.revision = revision
    }

    var isCurrent: Bool {
        guard let registry, !registry.isClosed else { return false }
        return registry.mutationRevision == revision
    }
}

@MainActor
private final class StateMountSubtreeLease: RetainedSubtreeBuildLease {
    private weak var coordinator: StateMountCoordinator?
    private let owner: StateMountOwner
    private let contentPrefix: RetainedViewIdentity
    let activityAnchor: PresentationActivityAnchor
    private let lazyRow: LazyListLogicalRow?
    private let initialLazyConstruction: LazyListResolutionReceipt?
    private let initialDescriptorAttribution: RetainedDescriptorComponentAttribution?

    init(
        coordinator: StateMountCoordinator, owner: StateMountOwner, contentPrefix: RetainedViewIdentity,
        activityAnchor: PresentationActivityAnchor,
        lazyRow: LazyListLogicalRow? = nil, initialLazyConstruction: LazyListResolutionReceipt? = nil,
        initialDescriptorAttribution: RetainedDescriptorComponentAttribution? = nil
    ) {
        self.coordinator = coordinator
        self.owner = owner
        self.contentPrefix = contentPrefix
        self.activityAnchor = activityAnchor
        self.lazyRow = lazyRow
        self.initialLazyConstruction = initialLazyConstruction
        self.initialDescriptorAttribution = initialDescriptorAttribution
    }

    var canBuild: Bool {
        if let lazyRow {
            // Logical membership alone permits State storage, never deferred
            // authored work. This lease stays bound to its original physical
            // contribution even when another generation occupies the same path.
            guard initialLazyConstruction != nil, let contribution = activityAnchor.lazyContribution,
                contribution.isActive, activityAnchor.isActive, let coordinator, !coordinator.registry.isClosed,
                lazyRow.isDeclared, owner.isLive
            else { return false }
            return contribution.isActive && activityAnchor.isActive && !coordinator.registry.isClosed
        }
        if initialDescriptorAttribution != nil {
            guard let contribution = activityAnchor.descriptorContribution, contribution.isActive,
                activityAnchor.isActive, let coordinator, !coordinator.registry.isClosed, owner.isLive
            else { return false }
            return contribution.isActive && activityAnchor.isActive && !coordinator.registry.isClosed
        }
        guard let coordinator, activityAnchor.isActive, !coordinator.registry.isClosed,
            owner.isLive, coordinator.registry.owner(at: owner.identity) === owner
        else { return false }
        // Typed identity lookup may run application Hashable code.
        return activityAnchor.isActive && owner.isLive && !coordinator.registry.isClosed
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        guard canBuild else { return nil }
        return coordinator?.beginSubtreeBuild(
            owner: owner, contentPrefix: contentPrefix, anchor: activityAnchor,
            lazyRow: lazyRow, originalActivity: lazyRow == nil ? nil : activityAnchor.lazyContribution,
            originalDescriptorActivity: initialDescriptorAttribution == nil
                ? nil : activityAnchor.descriptorContribution)
    }

    func admitsLazyBuild(_ build: StateMountBuild, from original: LazyListViewAttribution) -> Bool {
        guard let lazyRow, lazyRow === build.originalLazyRow,
            original.logicalRow === lazyRow, original.admission === initialLazyConstruction,
            let contribution = activityAnchor.lazyContribution,
            contribution === build.originalLazyActivity, contribution.isActive,
            activityAnchor.isActive, build.canConstructLazy
        else { return false }
        return true
    }

    func admitsDescriptorBuild(
        _ build: StateMountBuild, from original: RetainedDescriptorComponentAttribution
    ) -> Bool {
        guard lazyRow == nil, initialDescriptorAttribution === original,
            let contribution = activityAnchor.descriptorContribution,
            contribution === build.originalDescriptorActivity, contribution.isActive,
            activityAnchor.isActive, build.canConstructLazy
        else { return false }
        return true
    }
}
