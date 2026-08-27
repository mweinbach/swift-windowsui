import SwiftWindowsCore
import SwiftWindowsUI

/// One host's typed ownership and dependency boundary. Building a value is
/// provisional until its retained nodes are adopted; no application writes
/// are rolled back when a candidate is superseded.
@MainActor
final class StateMountCoordinator: RetainedBuildLifecycle {
    let registry: StateMountRegistry
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
        latestInstallationError = nil
        let build = StateMountBuild(coordinator: self, epoch: epoch, replacesRoot: true)
        currentBuild = build
        return build
    }

    func captureBuildRequest() -> (any RetainedBuildRequest)? {
        StateMountRequest(registry: registry, revision: registry.mutationRevision)
    }

    fileprivate func beginSubtreeBuild(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity
    ) -> (any RetainedBuildEpoch)? {
        guard currentBuild == nil,
            let epoch = registry.beginSubtreeBuild(owner: owner, contentPrefix: contentPrefix)
        else { return nil }
        latestInstallationError = nil
        let build = StateMountBuild(
            coordinator: self, epoch: epoch, replacesRoot: false, subtreePrefix: contentPrefix)
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
        build.epoch.discardUnadoptedSubtree(at: prefix, preserveCommitted: preserveCommitted)
        build.observations = build.observations.filter { !$0.key.segments.starts(with: prefix.segments) }
    }

    func subtreeLease(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity
    ) -> any RetainedSubtreeBuildLease {
        StateMountSubtreeLease(coordinator: self, owner: owner, contentPrefix: contentPrefix)
    }

    func canEvaluateDeferredSubtree(at contentPrefix: RetainedViewIdentity) -> Bool {
        currentBuild?.subtreePrefix == contentPrefix && currentBuild?.canAdopt == true
    }

    func close() {
        registry.close()
        committedObservations.removeAll()
        currentBuild?.observations.removeAll()
        updateObservedObjects([], [], false)
    }

    fileprivate func didCommit(_ build: StateMountBuild, visited: Set<RetainedViewIdentity>) {
        guard currentBuild === build, build.epoch.didCommit, !registry.isClosed else { return }
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
        currentBuild = nil
        registry.finishPendingRetirements()
    }

    private func publishObservations(replacesRoot: Bool) {
        let committed = Set(committedObservations.values.flatMap { $0 })
        let provisional = Set((currentBuild?.observations ?? [:]).values.flatMap { $0 })
        updateObservedObjects(committed, committed.union(provisional), replacesRoot)
    }
}

// These existing leaves have a no-op DynamicProperty.update and manage their
// own legacy mechanisms. They are not mount-owned by this State-only slice;
// inspecting their private implementation boxes would invent ownership.
extension SwiftWindowsCore.Binding: NonOwningDynamicProperty {}
extension ObservedObject: NonOwningDynamicProperty {}
extension StateObject: NonOwningDynamicProperty {}
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
    let replacesRoot: Bool
    let subtreePrefix: RetainedViewIdentity?
    var observations: [RetainedViewIdentity: Set<ObjectIdentifier>] = [:]
    private var hasFinished = false

    init(
        coordinator: StateMountCoordinator, epoch: StateMountEpoch, replacesRoot: Bool,
        subtreePrefix: RetainedViewIdentity? = nil
    ) {
        self.coordinator = coordinator
        self.epoch = epoch
        self.replacesRoot = replacesRoot
        self.subtreePrefix = subtreePrefix
    }

    var canAdopt: Bool { epoch.canAdopt }
    var canComplete: Bool { epoch.didCommit && coordinator?.registry.isClosed == false }

    func supersede() { epoch.supersede() }
    func willAdopt() -> Bool { epoch.prepareForAdoption() }

    func commit() {
        let visited = epoch.visitedOwnerIdentities
        epoch.commitAdoption()
        coordinator?.didCommit(self, visited: visited)
    }

    func abandon() {
        epoch.abort()
        coordinator?.didAbandon(self)
    }

    func finishAfterCallbacks() {
        guard !hasFinished else { return }
        hasFinished = true
        coordinator?.didFinish(self)
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

    init(coordinator: StateMountCoordinator, owner: StateMountOwner, contentPrefix: RetainedViewIdentity) {
        self.coordinator = coordinator
        self.owner = owner
        self.contentPrefix = contentPrefix
    }

    var canBuild: Bool {
        guard let coordinator, !coordinator.registry.isClosed else { return false }
        return owner.isLive && coordinator.registry.owner(at: owner.identity) === owner
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        guard canBuild else { return nil }
        return coordinator?.beginSubtreeBuild(owner: owner, contentPrefix: contentPrefix)
    }
}
