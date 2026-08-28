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
        guard let build = currentBuild, build.canAdopt,
            let owner = build.epoch.owner(at: identity), isCurrent(build), build.canAdopt,
            owner.isInstallationActive, build.canAdopt,
            isCurrent(build), !build.constructionWasSuperseded
        else { return }
        let update = makeUpdate(owner)
        guard isCurrent(build), build.canAdopt, owner.isInstallationActive, build.canAdopt,
            isCurrent(build), !build.constructionWasSuperseded
        else { return }
        build.stageOnChange(update)
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
            activity.prepare(isCurrent: { coordinator.isCurrent(self) && self.epoch.canAdopt })
        else { return false }
        return epoch.prepareForAdoption()
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
