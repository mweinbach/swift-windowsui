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
    private var currentBuild: StateMountBuild?
    private(set) var latestInstallationError: DynamicPropertyInstallationError?

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

    fileprivate func beginSubtreeBuild(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity, anchor: PresentationActivityAnchor
    ) -> (any RetainedBuildEpoch)? {
        guard currentBuild == nil, anchor.isActive,
            let epoch = registry.beginSubtreeBuild(owner: owner, contentPrefix: contentPrefix)
        else { return nil }
        guard let activity = presentationActivity.beginBuild(prefix: contentPrefix, boundary: anchor) else {
            epoch.abort()
            registry.finishPendingRetirements()
            return nil
        }
        latestInstallationError = nil
        let build = StateMountBuild(
            coordinator: self, epoch: epoch, activity: activity, replacesRoot: false, subtreePrefix: contentPrefix)
        currentBuild = build
        return build
    }

    func install<Value>(
        _ source: Value, context: inout ViewBuildContext, isInstalledDelegate: Bool = false
    ) -> Value? {
        guard let build = currentBuild, build.canAdopt else { return nil }
        if isInstalledDelegate, context.viewIdentity.installedEpoch === build.epoch,
            context.viewIdentity.installedOwner?.isInstallationActive == true
        {
            // A typed delegate, such as the default View.body implementation,
            // received the local copy that the common dispatch already installed.
            return source
        }
        guard let owner = build.epoch.owner(at: context.retainedViewIdentity) else { return nil }
        context.viewIdentity.installedOwner = owner
        context.viewIdentity.installedEpoch = build.epoch
        return ViewBuildContextScope.withCurrent(context) {
            do {
                return try DynamicPropertyInstaller.install(source, in: owner)
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

    func canEvaluateDeferredSubtree(at contentPrefix: RetainedViewIdentity) -> Bool {
        currentBuild?.subtreePrefix == contentPrefix && currentBuild?.canAdopt == true
    }

    func close() {
        presentationActivity.closeAdmissions()
        registry.close()
        presentationActivity.releaseClosedPayloads()
        committedObservations.removeAll()
        currentBuild?.observations.removeAll()
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
        build.observations.removeAll()
        publishObservations(replacesRoot: build.replacesRoot)
    }

    fileprivate func didAbandon(_ build: StateMountBuild) {
        guard currentBuild === build else { return }
        build.observations.removeAll()
        publishObservations(replacesRoot: false)
    }

    fileprivate func didFinish(_ build: StateMountBuild) {
        guard currentBuild === build else { return }
        build.activity.finish()
        currentBuild = nil
        registry.finishPendingRetirements()
        // The runtime's retained-build guard and captured transaction remain
        // active through these actions and displaced-value/callback cleanup.
        // Reentrant reloads queue; they cannot replace this batch in place.
        build.finishOnChangeUpdates()
    }

    fileprivate func isCurrent(_ build: StateMountBuild) -> Bool {
        currentBuild === build && !registry.isClosed
    }

    private func publishObservations(replacesRoot: Bool) {
        let committed = Set(committedObservations.values.flatMap { $0 })
        let provisional = Set((currentBuild?.observations ?? [:]).values.flatMap { $0 })
        updateObservedObjects(committed, committed.union(provisional), replacesRoot)
    }
}

private enum PresentationActivityOwner {}
private enum AlertActivityOwner {}

@MainActor
private final class OnChangeMaterialization {
    let identity: RetainedViewIdentity
    var isDiscarded = false

    init(identity: RetainedViewIdentity) { self.identity = identity }
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
private final class StateMountBuild: RetainedBuildEpoch {
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
    private(set) var constructionWasSuperseded = false
    private var hasFinished = false

    init(
        coordinator: StateMountCoordinator, epoch: StateMountEpoch, activity: PresentationActivityBuild,
        replacesRoot: Bool,
        subtreePrefix: RetainedViewIdentity? = nil
    ) {
        self.coordinator = coordinator
        self.epoch = epoch
        self.activity = activity
        self.replacesRoot = replacesRoot
        self.subtreePrefix = subtreePrefix
    }

    var canAdopt: Bool { epoch.canAdopt && activity.canConstruct }
    var canComplete: Bool { epoch.didCommit && coordinator?.registry.isClosed == false }

    private var canConstructOnChange: Bool {
        coordinator?.isCurrent(self) == true && !constructionWasSuperseded
            && activity.canConstruct && epoch.observationConstructionRevision != nil
    }

    func isCurrent(_ materialization: OnChangeMaterialization) -> Bool {
        !materialization.isDiscarded && canConstructOnChange
    }

    func beginOnChangeMaterialization(at identity: RetainedViewIdentity) -> OnChangeMaterialization? {
        guard canConstructOnChange else { return nil }
        let materialization = OnChangeMaterialization(identity: identity)
        onChangeMaterializations[ObjectIdentifier(materialization)] = materialization
        // Register before comparing prefixes: authored equality can reenter
        // another discard, which must be able to revoke this same attempt.
        let scopes = onChangeDiscardScopes
        for scope in scopes {
            let matches = identity.segments.starts(with: scope.prefix.segments)
            guard isCurrent(materialization) else {
                endOnChangeMaterialization(materialization)
                return nil
            }
            if matches {
                materialization.isDiscarded = true
                endOnChangeMaterialization(materialization)
                return nil
            }
        }
        return materialization
    }

    func endOnChangeMaterialization(_ materialization: OnChangeMaterialization) {
        onChangeMaterializations.removeValue(forKey: ObjectIdentifier(materialization))
    }

    func beginOnChangeDiscard(at prefix: RetainedViewIdentity) -> OnChangeDiscardScope {
        let scope = OnChangeDiscardScope(prefix: prefix)
        onChangeDiscardScopes.append(scope)
        let materializations = Array(onChangeMaterializations.values)
        for materialization in materializations where !materialization.isDiscarded {
            guard canConstructOnChange else { return scope }
            let matches = materialization.identity.segments.starts(with: prefix.segments)
            guard canConstructOnChange else { return scope }
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
        }
    }

    func discardOnChangeUpdates(at prefix: RetainedViewIdentity, isCurrent: () -> Bool) {
        let updates = Array(onChangeUpdates.values)
        var removed: Set<ObjectIdentifier> = []
        for update in updates {
            let matches = update.owner.identity.segments.starts(with: prefix.segments)
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
    }

    func commitOnChangeUpdates() {
        guard canComplete else { return }
        // Every adopted value is published before the first comparator or
        // action. These commits retain displaced values and run no app code.
        for key in onChangeOrder { onChangeUpdates[key]?.commit() }
    }

    func finishOnChangeUpdates() {
        let updates = onChangeOrder.compactMap { onChangeUpdates[$0] }
        let discarded = discardedOnChangeUpdates
        onChangeUpdates = [:]
        onChangeOrder = []
        discardedOnChangeUpdates = []
        if canComplete {
            for update in updates { update.deliver() }
        }
        // Release both accepted and abandoned captures outside property
        // mutation, while the enclosing retained build still serializes work.
        withExtendedLifetime((updates, discarded)) {}
    }

    func supersede() {
        // The final staging check must not invoke user Hashable code again.
        // This local receipt mirrors the existing construction cancellation;
        // it does not revoke a build's already-adopted completion.
        constructionWasSuperseded = true
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
        activity.abandon()
        epoch.abort()
        coordinator?.didAbandon(self)
    }

    func finishAfterCallbacks() {
        guard !hasFinished else { return }
        hasFinished = true
        if let coordinator {
            coordinator.didFinish(self)
        } else {
            activity.finish()
            finishOnChangeUpdates()
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

    init(
        coordinator: StateMountCoordinator, owner: StateMountOwner, contentPrefix: RetainedViewIdentity,
        activityAnchor: PresentationActivityAnchor
    ) {
        self.coordinator = coordinator
        self.owner = owner
        self.contentPrefix = contentPrefix
        self.activityAnchor = activityAnchor
    }

    var canBuild: Bool {
        guard let coordinator, activityAnchor.isActive, !coordinator.registry.isClosed,
            owner.isLive, coordinator.registry.owner(at: owner.identity) === owner
        else { return false }
        // Typed identity lookup may run application Hashable code.
        return activityAnchor.isActive && owner.isLive && !coordinator.registry.isClosed
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        guard canBuild else { return nil }
        return coordinator?.beginSubtreeBuild(owner: owner, contentPrefix: contentPrefix, anchor: activityAnchor)
    }
}
