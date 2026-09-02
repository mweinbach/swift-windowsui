import Foundation
import SwiftWindowsCore
import SwiftWindowsPlatform

/// A checked reconciliation can stop after an admitted callback changes its
/// owner. The observed children describe the resulting tree, not permission
/// to publish an obsolete candidate or evidence that layout has settled.
@MainActor
struct RetainedLazyListAdoptionResult {
    let completed: Bool
    let didMutate: Bool
    let children: [ViewNode]
    let completion: RetainedLazyListAdoptionCompletion?

    init(
        completed: Bool, didMutate: Bool, children: [ViewNode],
        completion: RetainedLazyListAdoptionCompletion? = nil
    ) {
        self.completed = completed
        self.didMutate = didMutate
        self.children = children
        self.completion = completion
    }
}

/// Scalar evidence from one ordered native witness walk, never stored authority.
struct RetainedLazyListCompletionValidation {
    let isCurrent: Bool
    let nodeVisits: Int
}

/// A successful call is not a lasting permit: enclosing runtime scopes may
/// still drain application cleanup. This weak native snapshot lets the caller
/// check the actual adopted subtree again after those scopes have unwound.
@MainActor
final class RetainedLazyListAdoptionCompletion {
    @MainActor
    private struct NodeSnapshot {
        weak var node: ViewNode?
        weak var controller: (any RetainedTextInputController)?
        weak var observers: RetainedScrollObserverStorage?
        weak var adapter: RetainedLazyListRuntimeAdapter?
        // Later clocks can replace an action without changing the attachment.
        // Keep only native metadata after the adoption batch has closed.
        weak var buttonOwner: RetainedButtonActionOwner?
        let hadController: Bool
        let hadObservers: Bool
        let hadAdapter: Bool
        let hadButtonOwner: Bool
        let buttonOwnerWasRetired: Bool
        let attachment: RetainedLazyListAttachmentProof
        let identity: RetainedLazyListViewIdentityProof
        let children: [ObjectIdentifier]

        init(of node: ViewNode) {
            self.node = node
            controller = node.textInputController
            observers = node.scrollObserverStorage
            adapter = node.retainedLazyListAdapter
            buttonOwner = node.buttonActionOwner
            hadController = node.textInputController != nil
            hadObservers = node.scrollObserverStorage != nil
            hadAdapter = node.retainedLazyListAdapter != nil
            hadButtonOwner = node.buttonActionOwner != nil
            buttonOwnerWasRetired = node.buttonActionOwner?.isRetired == true
            attachment = node.captureLazyListAttachmentProof()
            identity = node.captureLazyListIdentityProof()
            children = node.children.map(ObjectIdentifier.init)
        }

        var isCurrent: Bool {
            guard let node, attachment.isCurrent, identity.isCurrent, node.children.count == children.count else {
                return false
            }
            if hadController {
                guard let controller, node.textInputController === controller else { return false }
            } else if node.textInputController != nil {
                return false
            }
            if hadObservers {
                guard let observers, node.scrollObserverStorage === observers else { return false }
            } else if node.scrollObserverStorage != nil {
                return false
            }
            if hadAdapter {
                guard let adapter, node.retainedLazyListAdapter === adapter else { return false }
            } else if node.retainedLazyListAdapter != nil {
                return false
            }
            if hadButtonOwner {
                guard let buttonOwner, node.buttonActionOwner === buttonOwner,
                    buttonOwner.isRetired == buttonOwnerWasRetired
                else { return false }
            } else if node.buttonActionOwner != nil {
                return false
            }
            return zip(node.children, children).allSatisfy { pair in ObjectIdentifier(pair.0) == pair.1 }
        }

        /// Exact captured obligations, including ordered children and absence
        /// of optional owners. Simultaneous currentness alone is not used as a
        /// substitute for comparing the snapshots that will remain retained.
        func hasSameWitness(as other: NodeSnapshot) -> Bool {
            guard let node, let otherNode = other.node, node === otherNode,
                attachment.hasSameCapture(as: other.attachment), identity.hasSameCapture(as: other.identity),
                hadController == other.hadController, hadObservers == other.hadObservers,
                hadAdapter == other.hadAdapter, hadButtonOwner == other.hadButtonOwner,
                buttonOwnerWasRetired == other.buttonOwnerWasRetired, children == other.children
            else { return false }
            if hadController {
                guard let controller, let otherController = other.controller, controller === otherController else {
                    return false
                }
            }
            if hadObservers {
                guard let observers, let otherObservers = other.observers, observers === otherObservers else {
                    return false
                }
            }
            if hadAdapter {
                guard let adapter, let otherAdapter = other.adapter, adapter === otherAdapter else { return false }
            }
            if hadButtonOwner {
                guard let buttonOwner, let otherButtonOwner = other.buttonOwner, buttonOwner === otherButtonOwner else {
                    return false
                }
            }
            return true
        }
    }

    private let nodes: [NodeSnapshot]
    private let nodeIndices: [ObjectIdentifier: Int]

    init?(of root: ViewNode) {
        var pending = [(node: root, depth: 0)]
        var visited: Set<ObjectIdentifier> = []
        var snapshots: [NodeSnapshot] = []
        var indices: [ObjectIdentifier: Int] = [:]
        while let entry = pending.popLast() {
            guard entry.depth <= ViewNode.maximumTraversalDepth,
                visited.insert(ObjectIdentifier(entry.node)).inserted
            else { return nil }
            indices[ObjectIdentifier(entry.node)] = snapshots.count
            snapshots.append(NodeSnapshot(of: entry.node))
            for child in entry.node.children {
                guard child.parent === entry.node, child.hasSameLazyListRuntime(as: entry.node) else { return nil }
                pending.append((node: child, depth: entry.depth + 1))
            }
        }
        nodes = snapshots
        nodeIndices = indices
    }

    var isCurrent: Bool { validation().isCurrent }
    var retainedNodeWitnessCount: Int { nodes.count }

    func validation() -> RetainedLazyListCompletionValidation {
        var nodeVisits = 0
        for snapshot in nodes {
            nodeVisits += 1
            guard snapshot.isCurrent else {
                return RetainedLazyListCompletionValidation(isCurrent: false, nodeVisits: nodeVisits)
            }
        }
        return RetainedLazyListCompletionValidation(isCurrent: true, nodeVisits: nodeVisits)
    }

    /// Only for a native section that has already rejected every stale old
    /// completion and checked the incoming one. No currentness is cached here.
    /// The native index selects a candidate; every old witness must still match.
    func containsEquivalentWitnesses(of other: RetainedLazyListAdoptionCompletion) -> Bool {
        guard nodes.count >= other.nodes.count else { return false }
        for previous in other.nodes {
            guard let node = previous.node, let index = nodeIndices[ObjectIdentifier(node)],
                nodes[index].hasSameWitness(as: previous)
            else { return false }
        }
        return true
    }
}

/// One diagnostic request's scalar observations, never admission or UI ownership.
/// Returned flags describe the named synchronous frame, not later cleanup.
@MainActor
final class ComponentHostConstructionDiagnostic {
    /// The first refusing predicate at the post-composition check only.
    /// A passed check is not adoption or later completion.
    enum PostCompositionCheck: String {
        case notReached
        case epochRefused
        case requestRefused
        case sequenceRefused
        case checkPassed
    }

    fileprivate(set) var postCompositionCheck = PostCompositionCheck.notReached
    fileprivate(set) var requestBound = false
    fileprivate(set) var replacedBeforeRequest = false
    fileprivate(set) var unmanagedRequest = false
    fileprivate(set) var attemptEntered = false
    fileprivate(set) var attemptReturned = false
    fileprivate(set) var compositionReturned = false
    fileprivate(set) var nodesReturned = false
    fileprivate(set) var newNodeCount = 0
    fileprivate(set) var descriptorRegistrationReturned = false
    fileprivate(set) var registeredDescriptors = false
    fileprivate(set) var reconciliationEntered = false
    fileprivate(set) var reconciliationReturned = false
    fileprivate(set) var completed = false
    fileprivate(set) var didMutate = false
    fileprivate(set) var childrenCount = 0
}

@MainActor
public final class ComponentHost {
    public let runtime: RetainedViewRuntime

    private var buildComponents: (() -> [Component])?
    private var isProcessingFileDialog = false
    private var needsFileDialogProcessing = false
    private var fileDialogLifetimeIsValid = true
    private var fileDialogOwnerGeneration: UInt64 = 0
    private var activeFileDialogOperation: FileDialogOperation?

    /// The retained window supplies its own current HWND. Raw ComponentHost
    /// callers retain the standalone provider behavior without global ownership.
    package var fileDialogOwner: @MainActor () -> FileDialogOwner = { .standalone }
    package var nativeDialogSession: NativeDialogSession?
    /// Production chooses native ownership before its first retained build.
    /// A task can present a modifier while window creation is still pending.
    package var expectsNativeDialogOwner = false

    @MainActor
    private final class FileDialogOperation {
        enum Phase: Equatable {
            case inspecting, selecting, accessingFile, resetting, completing, finished, revoked
        }

        enum Outcome {
            case completed, cancelled, failed, revoked
        }

        let ownerGeneration: UInt64
        let node: ViewNode
        let presenterLease: RetainedFileDialogPresenterLease
        let invocationScope: (any RetainedFileDialogInvocationScope)?
        var phase = Phase.inspecting
        var outcome: Outcome?
        var didRequestSelection = false
        var isInitiatingSelection = false
        var isAwaitingSelection = false

        init(
            ownerGeneration: UInt64, node: ViewNode, kind: RetainedFileDialogKind,
            invocationScope: (any RetainedFileDialogInvocationScope)?
        ) {
            self.ownerGeneration = ownerGeneration
            self.node = node
            self.presenterLease = node.beginFileDialogPresentation(kind: kind)
            self.invocationScope = invocationScope
        }

        func revoke() {
            phase = .revoked
            outcome = .revoked
            presenterLease.invalidate()
        }
    }

    private enum FileDialogOperationError: Error {
        case revoked
    }
    private struct ReloadRequest {
        let transaction: RetainedBuildTransaction
        let validity: (any RetainedBuildRequest)?
        let onCompleted: (() -> Void)?
        let constructionDiagnostic: ComponentHostConstructionDiagnostic?
    }

    private final class BuildLifecycleInstallation {}
    private var buildLifecycleInstallation = BuildLifecycleInstallation()
    private var pendingConstructionDiagnostic: ComponentHostConstructionDiagnostic?

    /// Arms the next call to reload on this host, not a nested or future request.
    /// Nil by default. The next reload removes this slot before any existing
    /// lifecycle callback and carries the scalar capture in its own request.
    func requestConstructionDiagnostic() -> ComponentHostConstructionDiagnostic {
        let diagnostic = ComponentHostConstructionDiagnostic()
        pendingConstructionDiagnostic?.replacedBeforeRequest = true
        pendingConstructionDiagnostic = diagnostic
        return diagnostic
    }

    /// Optional state ownership supplied by the composition layer. Raw
    /// ComponentHost clients keep their existing path when this is absent.
    public var buildLifecycle: (any RetainedBuildLifecycle)? {
        didSet {
            if oldValue !== buildLifecycle {
                buildLifecycleInstallation = BuildLifecycleInstallation()
            }
        }
    }

    /// True while an installed lifecycle builds a root or deferred subtree,
    /// including terminal callbacks and request completion. Reentry queues.
    public var isBuilding: Bool { runtime.hasActiveRetainedBuild }

    /// True after coordinated root/subtree builds, terminal callbacks, and
    /// queued rebuilds have finished, including the coordinator's drain scope.
    /// This does not mean layout is resolved: dirty geometry may build during
    /// a later render. Manually inserted, lease-less geometry is not tracked.
    /// False means unavailable for raw hosts without an installed lifecycle;
    /// their existing unmanaged rebuild path does not expose this capability.
    package var isBuildSettled: Bool {
        buildLifecycle != nil && runtime.retainedBuildCoordinator.isBuildSettled
    }

    /// Schedule a native wake after coordinated builds settle, never a prompt
    /// or close inline. An idle coordinator delivers synchronously. The owner
    /// is a retained registration token; capture the host weakly and revalidate
    /// the intent before submitting work. Removing or replacing the lifecycle
    /// drops an old continuation, even if that lifecycle is later reinstalled.
    /// False rejects unavailable raw hosts without invoking the action. True
    /// accepts a continuation, not its eventual delivery or a lasting permit.
    /// Records appended during notification delivery wait for a later independent
    /// drain opportunity; this observer does not create a wakeup or follow-up pass.
    @discardableResult
    package func scheduleAfterBuildsSettled(owner: AnyObject, action: @escaping @MainActor () -> Void) -> Bool {
        guard let lifecycle = buildLifecycle else { return false }
        let installation = buildLifecycleInstallation
        runtime.retainedBuildCoordinator.scheduleAfterBuildsSettled(owner: owner) { [weak self, weak lifecycle] in
            guard let self, let lifecycle, self.buildLifecycle === lifecycle,
                self.buildLifecycleInstallation === installation
            else { return }
            action()
        }
        return true
    }

    /// Invoked only after a root was adopted and its terminal callbacks have
    /// drained. A rejected or obsolete request does not complete.
    public var onReloadCompleted: (() -> Void)?

    /// Measures one synchronous construction/adoption attempt. Waiting for
    /// an enclosing callback scope, deferred epoch cleanup, and completion
    /// callbacks are outside this boundary and must not become extra builds.
    /// The hook must invoke its supplied body exactly once, synchronously.
    public var measureBuild: ((() -> Void) -> Void)?

    /// Measures deferred epoch cleanup without adding another build attempt
    /// or changing the completed attempt's compose/node/reconcile timings.
    /// The hook must invoke its supplied body exactly once, synchronously.
    public var measureBuildCleanup: ((() -> Void) -> Void)?

    /// False until this host has produced a tree. The first tree is the
    /// window's initial state, not an insertion into it, so nothing in it
    /// transitions — see `isInitialBuildNode`.
    private(set) var hasPerformedInitialBuild = false

    /// Optional predicate that can skip rebuilds when it returns false.
    public var shouldUpdate: (() -> Bool)?

    /// Set of observed object identifiers that were accessed during the last rebuild.
    /// Used for dependency tracking so that only hosts that depend on a changed
    /// observable are rebuilt.
    public var observedObjects: Set<ObjectIdentifier> = []

    /// The wall-clock split of the last `reload()`, in the three parts that
    /// have three different fixes: evaluating `View` bodies into a
    /// `Component` tree, turning that tree into `ViewNode`s, and reconciling
    /// the new nodes onto the retained ones.
    ///
    /// Collected only while `runtime.collectsPhaseTimings` is on, which a
    /// live diagnostics run turns on and nothing else does — a rebuild runs
    /// on every state change and three QPC round-trips per rebuild is not a
    /// cost a shipping window should carry for a number nobody reads.
    public private(set) var lastComposeSeconds: Double = 0
    public private(set) var lastNodeConstructionSeconds: Double = 0
    public private(set) var lastReconcileSeconds: Double = 0

    public init(runtime: RetainedViewRuntime) {
        self.runtime = runtime
    }

    public func setContent(_ component: Component) {
        buildComponents = { [component] }
        reload()
    }

    public func setComponents(_ content: @escaping () -> [Component]) {
        let trace = runtime.constructionTrace
        let span = trace?.record("components.set.enter", host: UInt(bitPattern: ObjectIdentifier(self)))
        buildComponents = content
        reload()
        trace?.record("components.set.returnBoundary", span: span, host: UInt(bitPattern: ObjectIdentifier(self)))
    }

    public func setContent(@ComponentBuilder _ content: @escaping () -> [Component]) {
        setComponents(content)
    }

    public func reload() {
        reload(onCompleted: nil)
    }

    /// A completion belongs to this request and its captured transaction,
    /// including when a callback queues it behind a root or geometry build.
    /// Requests whose captured revision becomes obsolete are skipped. Other
    /// requests keep their order, even when a fallback rebuild is unchanged.
    public func reload(onCompleted: (() -> Void)?) {
        let constructionDiagnostic = pendingConstructionDiagnostic
        pendingConstructionDiagnostic = nil
        constructionDiagnostic?.requestBound = true
        if buildLifecycle == nil, !runtime.hasActiveRetainedBuild {
            constructionDiagnostic?.unmanagedRequest = true
            performUnmanagedReload(onCompleted: onCompleted)
            return
        }
        let request = ReloadRequest(
            transaction: RetainedBuildTransaction(), validity: buildLifecycle?.captureBuildRequest(),
            onCompleted: onCompleted, constructionDiagnostic: constructionDiagnostic)
        runtime.retainedBuildCoordinator.scheduleReload { [weak self] in
            self?.performReload(request)
        }
    }

    private func performUnmanagedReload(onCompleted: (() -> Void)?) {
        if let shouldUpdate, !shouldUpdate() {
            return
        }
        let transaction = RetainedBuildTransaction()
        runtime.beginLongPressReconciliation()
        measureBuildAttempt {
            _ = buildAndAdopt(epoch: nil, sequence: nil, validity: nil)
            runtime.endLongPressReconciliation()
        }
        guard onReloadCompleted != nil || onCompleted != nil else { return }
        runtime.afterRetainedCallbacks { [self] in
            transaction.perform {
                onReloadCompleted?()
                onCompleted?()
            }
        }
    }

    private func performReload(_ request: ReloadRequest) {
        let constructionDiagnostic = request.constructionDiagnostic
        constructionDiagnostic?.attemptEntered = true
        defer { constructionDiagnostic?.attemptReturned = true }
        guard request.validity?.isCurrent != false else {
            resetBuildTimings()
            return
        }
        request.transaction.perform {
            let coordinator = runtime.retainedBuildCoordinator
            guard let sequence = coordinator.beginBuild() else { return }
            if let shouldUpdate, !shouldUpdate() {
                coordinator.finishBuild()
                return
            }
            guard request.validity?.isCurrent != false else {
                resetBuildTimings()
                coordinator.finishBuild()
                return
            }
            let lifecycle = buildLifecycle
            var epoch: (any RetainedBuildEpoch)?
            var didAdopt = false
            let lazyBuild = RootLazyBuild()
            measureBuildAttempt {
                epoch = lifecycle?.beginBuild()
                coordinator.install(epoch, startedAt: sequence)
                runtime.beginLongPressReconciliation()
                didAdopt =
                    (lifecycle == nil || epoch != nil)
                    && buildAndAdopt(
                        epoch: epoch, sequence: sequence, validity: request.validity, lazyBuild: lazyBuild,
                        constructionDiagnostic: constructionDiagnostic)
                if lazyBuild.usesManagedPublication, let journal = lazyBuild.journal,
                    let activity = epoch as? any RetainedLazyListBuildActivity
                {
                    // Source-node destruction occurs after buildAndAdopt
                    // returns. It may invalidate an otherwise completed tree.
                    didAdopt = didAdopt && lazyBuild.completion?.isCurrent == true && journal.canContinueAdoption
                    let disposition = journal.seal(completedCheckedAdoption: didAdopt)
                    if disposition.stop != .noAcceptance || didAdopt {
                        activity.commitLazyList(disposition)
                    } else {
                        journal.revokeBeforeAbandon()
                        epoch?.abandon()
                    }
                } else if didAdopt {
                    _ = lazyBuild.journal?.seal(completedCheckedAdoption: lazyBuild.completion?.isCurrent == true)
                    epoch?.commit()
                } else {
                    lazyBuild.journal?.revokeBeforeAbandon()
                    _ = lazyBuild.journal?.seal()
                    epoch?.abandon()
                }
                runtime.endLongPressReconciliation()
            }
            runtime.afterRetainedCallbacks { [self] in
                request.transaction.perform {
                    if let epoch {
                        if let measureBuildCleanup {
                            measureBuildCleanup { epoch.finishAfterCallbacks() }
                        } else {
                            epoch.finishAfterCallbacks()
                        }
                    }
                    lazyBuild.journal?.finishAcceptedTaskCleanup()
                    lazyBuild.journal?.releaseUnadoptedTransport()
                    if didAdopt, epoch?.canComplete != false, lazyBuild.permitsCompletion {
                        onReloadCompleted?()
                        if epoch?.canComplete != false, lazyBuild.permitsCompletion { request.onCompleted?() }
                    }
                }
                coordinator.finishBuild()
            }
        }
    }

    /// Native facts survive candidate capture cleanup without keeping source
    /// components, view values or callbacks in the sealed disposition.
    @MainActor
    private final class RootLazyBuild {
        var journal: RetainedLazyListAdoptionJournal?
        var preparation: RetainedLazyListAdoptionPreparation?
        var completion: RetainedLazyListAdoptionCompletion?
        var usesManagedPublication = false
        var permitsCompletion: Bool { !usesManagedPublication || completion?.isCurrent == true }
    }

    private func measureBuildAttempt(_ build: () -> Void) {
        resetBuildTimings()
        if let measureBuild {
            measureBuild(build)
        } else {
            build()
        }
    }

    private func resetBuildTimings() {
        lastComposeSeconds = 0
        lastNodeConstructionSeconds = 0
        lastReconcileSeconds = 0
    }

    private func candidateCanAdopt(
        epoch: (any RetainedBuildEpoch)?, sequence: UInt64?, validity: (any RetainedBuildRequest)?,
        diagnostic: ComponentHostConstructionDiagnostic? = nil
    ) -> Bool {
        guard epoch?.canAdopt != false else {
            diagnostic?.postCompositionCheck = .epochRefused
            return false
        }
        guard validity?.isCurrent != false else {
            diagnostic?.postCompositionCheck = .requestRefused
            return false
        }
        if let sequence, runtime.retainedBuildCoordinator.wasSuperseded(since: sequence) {
            diagnostic?.postCompositionCheck = .sequenceRefused
            return false
        }
        diagnostic?.postCompositionCheck = .checkPassed
        return true
    }

    private func buildAndAdopt(
        epoch: (any RetainedBuildEpoch)?, sequence: UInt64?, validity: (any RetainedBuildRequest)?,
        lazyBuild: RootLazyBuild? = nil, constructionDiagnostic: ComponentHostConstructionDiagnostic? = nil
    ) -> Bool {
        let buttonConstruction = RetainedButtonActionConstruction(runtime: runtime)
        defer { buttonConstruction.finish() }
        let taskTransaction = RetainedBuildTransaction()
        var completedNativeBuild = false
        defer {
            // Local source components may own authored destructors. Revoke
            // rejected construction before those locals leave this helper.
            if !completedNativeBuild { lazyBuild?.journal?.revokeBeforeAbandon() }
        }
        if buildComponents == nil, epoch == nil, sequence == nil {
            runtime.root.removeAllChildren()
            return true
        }
        guard candidateCanAdopt(epoch: epoch, sequence: sequence, validity: validity) else { return false }
        let descriptorScope: RetainedLazyListDescriptorBuildScope?
        if let epoch, let activity = epoch as? any RetainedLazyListBuildActivity {
            guard
                let scope = runtime.retainedBuildCoordinator.beginDescriptorBuildScope(
                    origin: .componentHostRoot, epoch: epoch, hostLifetime: runtime.lazyListLogicalHostLifetime,
                    ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
            else { return false }
            let bound = activity.bindLazyListDescriptorScope(scope)
            guard bound, scope.canConstructDescriptors,
                candidateCanAdopt(epoch: epoch, sequence: sequence, validity: validity)
            else {
                scope.revoke()
                return false
            }
            descriptorScope = scope
            let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: taskTransaction)
            journal.seedExistingContributions(from: runtime.root.children)
            lazyBuild?.journal = journal
        } else {
            descriptorScope = nil
        }
        runtime.recordMatchedGeometryFrames()

        let isProfiling = runtime.collectsPhaseTimings
        let reloadStartedAt = isProfiling ? PlatformClock.now() : 0

        let oldChildren = runtime.root.children
        let trace = runtime.constructionTrace
        let composeSpan = trace?.record("compose.enter", host: UInt(bitPattern: ObjectIdentifier(self)))
        let components = buildComponents?() ?? []
        trace?.record("compose.returned", span: composeSpan, host: UInt(bitPattern: ObjectIdentifier(self)))
        constructionDiagnostic?.compositionReturned = true
        let composeEndedAt = isProfiling ? PlatformClock.now() : 0
        if isProfiling { lastComposeSeconds = composeEndedAt - reloadStartedAt }
        guard
            candidateCanAdopt(
                epoch: epoch, sequence: sequence, validity: validity, diagnostic: constructionDiagnostic)
        else { return false }
        let nodesSpan = trace?.record("nodes.enter", host: UInt(bitPattern: ObjectIdentifier(self)))
        let newNodes = components.map { $0.makeNode(runtime: runtime) }
        trace?.record("nodes.returned", span: nodesSpan, host: UInt(bitPattern: ObjectIdentifier(self)))
        if let constructionDiagnostic {
            constructionDiagnostic.newNodeCount = newNodes.count
            constructionDiagnostic.nodesReturned = true
        }
        let nodesEndedAt = isProfiling ? PlatformClock.now() : 0
        if isProfiling { lastNodeConstructionSeconds = nodesEndedAt - composeEndedAt }

        guard candidateCanAdopt(epoch: epoch, sequence: sequence, validity: validity) else { return false }
        if let journal = lazyBuild?.journal {
            let descriptorsSpan = trace?.record("descriptors.enter", host: UInt(bitPattern: ObjectIdentifier(self)))
            let registeredDescriptors = journal.registerSourceDescriptors(in: newNodes)
            trace?.record("descriptors.returned", span: descriptorsSpan, host: UInt(bitPattern: ObjectIdentifier(self)))
            if let constructionDiagnostic {
                constructionDiagnostic.registeredDescriptors = registeredDescriptors
                constructionDiagnostic.descriptorRegistrationReturned = true
            }
            guard registeredDescriptors else { return false }
            lazyBuild?.preparation = journal.preparation()
            if journal.hasManagedContributions {
                lazyBuild?.usesManagedPublication = true
                guard let activity = epoch as? any RetainedLazyListBuildActivity,
                    let preparation = journal.preparation(), descriptorScope?.canConstructDescriptors == true
                else {
                    journal.revokeBeforeAbandon()
                    return false
                }
                let prepared = activity.willAdoptLazyList(preparation)
                guard validity?.isCurrent != false, let prepared,
                    journal.beginAdoption(preparation, preparedActivity: prepared)
                else {
                    journal.revokeBeforeAbandon()
                    return false
                }
            } else {
                // Ordinary component tags are metadata, not opt-in to a
                // different State/observer publication policy.
                guard epoch?.willAdopt() != false, validity?.isCurrent != false
                else {
                    journal.revokeBeforeAbandon()
                    return false
                }
                _ = journal.beginOrdinaryAdoption()
            }
        } else {
            guard epoch?.willAdopt() != false else { return false }
            guard validity?.isCurrent != false else { return false }
        }

        let taskAdoption: RetainedTaskAdoptionContext?
        if let epoch {
            taskAdoption = RetainedTaskAdoptionContext(
                runtime: runtime, epoch: epoch, transaction: taskTransaction)
        } else {
            taskAdoption = nil
        }
        let reconcileSpan = trace?.record("reconcile.enter", host: UInt(bitPattern: ObjectIdentifier(self)))
        constructionDiagnostic?.reconciliationEntered = true
        let result = Self.reconcileChildren(
            of: runtime.root, oldChildren: oldChildren, newNodes: newNodes, taskAdoption: taskAdoption,
            lazyJournal: lazyBuild?.journal)
        trace?.record("reconcile.returned", span: reconcileSpan, host: UInt(bitPattern: ObjectIdentifier(self)))
        if let constructionDiagnostic {
            constructionDiagnostic.completed = result.completed
            constructionDiagnostic.didMutate = result.didMutate
            constructionDiagnostic.childrenCount = result.children.count
            constructionDiagnostic.reconciliationReturned = true
        }
        if let journal = lazyBuild?.journal {
            if result.completed {
                let anchor = runtime.root.lazyListActivityStorage().captureActualAttachment(
                    of: runtime.root, in: runtime)
                let groups =
                    lazyBuild?.preparation?.ordinaryComponents.flatMap(\.groups)
                    .filter { $0.construction == .closedEmpty }.map(\.group) ?? []
                journal.recordAcceptedOrdinaryEmptyGroups(structuralAnchor: anchor, groups: groups)
                let recordedScope = journal.recordCompletedOwnedDescriptorScope(structuralAnchor: anchor)
                if !journal.isOrdinaryAdoption, !recordedScope { return false }
            }
            lazyBuild?.completion =
                result.completed
                ? (result.completion ?? RetainedLazyListAdoptionCompletion(of: runtime.root)) : nil
            if lazyBuild?.usesManagedPublication == true, !result.completed { return false }
        }
        if isProfiling {
            lastReconcileSeconds = PlatformClock.now() - nodesEndedAt
        }
        if hasPerformedInitialBuild {
            Self.applyNewNodeTransitionsRecursively(in: runtime.root)
        } else {
            // The window's first tree animates itself in on nothing: SwiftUI
            // plays a transition on insertion into an existing container, not
            // on the container's own first render. Marking rather than simply
            // not calling, because a `@State` change between here and the first
            // frame would find the same nodes still un-appeared.
            hasPerformedInitialBuild = true
            Self.markInitialBuildNodesRecursively(in: runtime.root)
        }
        // A build does not know where the pointer is, so `updateNodeProperties`
        // has just rewritten every interaction-animated colour from the idle
        // value the builder produced. The runtime does know, and puts them
        // back — without which any `@State` change anywhere in the window
        // leaves every control under the pointer painted dead until the
        // pointer leaves and comes back.
        runtime.restoreInteractionChrome()
        runtime.pendingMatchedGeometryCheck = true
        completedNativeBuild = true
        return true
    }

    /// Starts one owned selection at a time. Native selection returns later;
    /// injected providers may complete inline. Reentrant requests wait until
    /// selection, file access, presentation reset and completion all finish.
    public func processPendingFileDialogs() {
        guard fileDialogLifetimeIsValid else { return }
        guard !expectsNativeDialogOwner || nativeDialogSession != nil else {
            // Do not read application bindings, lease a presenter, or let a
            // missing startup owner select the standalone Win32 path. The
            // bind-and-reload pass will scan the still-pending declaration.
            needsFileDialogProcessing = true
            return
        }
        guard !isProcessingFileDialog else {
            needsFileDialogProcessing = true
            return
        }
        isProcessingFileDialog = true
        continueProcessingFileDialogs()
    }

    private func continueProcessingFileDialogs() {
        var retriedEmptyScan = false
        repeat {
            needsFileDialogProcessing = false
            guard fileDialogLifetimeIsValid else {
                isProcessingFileDialog = false
                return
            }
            let requestedSelection = processNextFileDialog()
            if activeFileDialogOperation?.isAwaitingSelection == true { return }
            if !requestedSelection {
                // A getter may replace the tree and enqueue its new presenter.
                // Retry once without spinning on an unchanged false getter
                // that calls this method every time it is read.
                guard needsFileDialogProcessing, !retriedEmptyScan else {
                    isProcessingFileDialog = false
                    return
                }
                retriedEmptyScan = true
                continue
            }
            retriedEmptyScan = false
        } while needsFileDialogProcessing
        isProcessingFileDialog = false
    }

    /// Revocation precedes application teardown callbacks. It does not release
    /// the suspended operation's payloads or allow a later request to revive it.
    package func invalidateFileDialogRequests() {
        guard fileDialogLifetimeIsValid else { return }
        fileDialogLifetimeIsValid = false
        fileDialogOwnerGeneration &+= 1
        needsFileDialogProcessing = false
        activeFileDialogOperation?.revoke()
    }

    private func processNextFileDialog() -> Bool {
        guard let (config, operation) = findActiveFileDialogConfiguration(in: runtime.root) else { return false }
        operation.isInitiatingSelection = true
        presentFileDialog(config, operation: operation)
        operation.isInitiatingSelection = false
        if !operation.isAwaitingSelection { finishFileDialogOperation(operation) }
        return operation.didRequestSelection
    }

    private func finishFileDialogOperation(_ operation: FileDialogOperation) {
        operation.presenterLease.invalidate()
        if operation.phase != .revoked { operation.phase = .finished }
        if activeFileDialogOperation === operation { activeFileDialogOperation = nil }
    }

    private func receiveFileDialogSelection<Selection>(
        _ selection: DialogRequestOutcome<Selection>, config: FileDialogConfig,
        operation: FileDialogOperation,
        complete: (DialogRequestOutcome<Selection>) -> Void
    ) {
        // Consume before any binding, file encoder or application completion
        // can reenter. A duplicate reply cannot retire a later operation.
        guard operation.isAwaitingSelection else { return }
        operation.isAwaitingSelection = false
        if case .revoked = selection {
            operation.revoke()
        } else if !isCurrentFileDialogPresenter(operation) {
            operation.revoke()
        } else if !operation.isInitiatingSelection, let scope = config.invocationScope {
            // Application getters may replace a provider before selection.
            // Actual deferred consumption needs its captured facade scope even
            // when the initial provider was an inline/headless implementation.
            scope.withInvocation {
                if self.validateFileDialogPresentation(config, operation: operation) {
                    complete(selection)
                }
            }
        } else if validateFileDialogPresentation(config, operation: operation) {
            complete(selection)
        }
        // Inline providers let the outer bounded scan do its usual cleanup.
        // Deferred selection owns that same cleanup only after its real reply.
        guard !operation.isInitiatingSelection else { return }
        finishFileDialogOperation(operation)
        guard fileDialogLifetimeIsValid, needsFileDialogProcessing else {
            isProcessingFileDialog = false
            return
        }
        continueProcessingFileDialogs()
    }

    private func findActiveFileDialogConfiguration(in node: ViewNode) -> (FileDialogConfig, FileDialogOperation)? {
        guard fileDialogLifetimeIsValid, node.isFileDialogPresenter(in: runtime) else { return nil }
        for kind in RetainedFileDialogKind.allCases {
            guard fileDialogLifetimeIsValid, node.isFileDialogPresenter(in: runtime) else { return nil }
            // A preceding binding getter can replace a later modifier. Read
            // each configuration only when its own lease is about to begin.
            guard let config = FileDialogConfig.current(kind: kind, on: node) else { continue }
            // Install the lease before reading an application binding: even its
            // getter can remove and reinsert this same retained presenter.
            let invocationScope =
                nativeDialogSession != nil && FileDialogManager.providerSupportsNativeOwnerRequests
                ? config.invocationScope : nil
            let operation = FileDialogOperation(
                ownerGeneration: fileDialogOwnerGeneration, node: node, kind: config.kind,
                invocationScope: invocationScope)
            activeFileDialogOperation = operation
            if validateFileDialogPresentation(config, operation: operation) {
                operation.phase = .selecting
                return (config, operation)
            }
            if activeFileDialogOperation === operation { activeFileDialogOperation = nil }
        }
        for child in node.children {
            if let result = findActiveFileDialogConfiguration(in: child) {
                return result
            }
        }
        return nil
    }

    @MainActor
    private enum FileDialogConfig {
        case exporter(RetainedFileExporterConfiguration)
        case importer(RetainedFileImporterConfiguration)
        case importerMulti(RetainedFileImporterMultiConfiguration)
        case mover(RetainedFileMoverConfiguration)

        static func current(kind: RetainedFileDialogKind, on node: ViewNode) -> FileDialogConfig? {
            switch kind {
            case .exporter: return node.fileExporterConfiguration.map { .exporter($0) }
            case .importer: return node.fileImporterConfiguration.map { .importer($0) }
            case .importerMulti: return node.fileImporterMultiConfiguration.map { .importerMulti($0) }
            case .mover: return node.fileMoverConfiguration.map { .mover($0) }
            }
        }

        var kind: RetainedFileDialogKind {
            switch self {
            case .exporter: return .exporter
            case .importer: return .importer
            case .importerMulti: return .importerMulti
            case .mover: return .mover
            }
        }

        var isPresented: Binding<Bool> {
            switch self {
            case .exporter(let configuration): return configuration.isPresented
            case .importer(let configuration): return configuration.isPresented
            case .importerMulti(let configuration): return configuration.isPresented
            case .mover(let configuration): return configuration.isPresented
            }
        }

        var invocationScope: (any RetainedFileDialogInvocationScope)? {
            switch self {
            case .exporter(let configuration): return configuration.invocationScope
            case .importer(let configuration): return configuration.invocationScope
            case .importerMulti(let configuration): return configuration.invocationScope
            case .mover(let configuration): return configuration.invocationScope
            }
        }
    }

    private func isCurrentFileDialogOperation(_ operation: FileDialogOperation) -> Bool {
        fileDialogLifetimeIsValid && operation.ownerGeneration == fileDialogOwnerGeneration
            && activeFileDialogOperation === operation && operation.phase != .revoked && operation.phase != .finished
    }

    private func isCurrentFileDialogPresenter(_ operation: FileDialogOperation) -> Bool {
        isCurrentFileDialogOperation(operation) && operation.presenterLease.isValid
            && operation.node.isFileDialogPresenter(in: runtime)
    }

    private func validateFileDialogPresentation(_ config: FileDialogConfig, operation: FileDialogOperation) -> Bool {
        guard isCurrentFileDialogPresenter(operation) else {
            operation.revoke()
            return false
        }
        var isPresented = false
        if let scope = operation.invocationScope {
            scope.withInvocation { isPresented = config.isPresented.wrappedValue }
        } else {
            isPresented = config.isPresented.wrappedValue
        }
        guard isCurrentFileDialogPresenter(operation), isPresented else {
            operation.revoke()
            return false
        }
        return true
    }

    private func validateFileDialogAccess(_ config: FileDialogConfig, operation: FileDialogOperation) throws {
        guard operation.phase == .accessingFile, validateFileDialogPresentation(config, operation: operation) else {
            operation.revoke()
            throw FileDialogOperationError.revoked
        }
    }

    private func canSubmitFileDialog(_ config: FileDialogConfig, operation: FileDialogOperation) -> Bool {
        guard isCurrentFileDialogPresenter(operation) else { return false }
        var canSubmit = false
        if let scope = config.invocationScope {
            scope.withInvocation {
                canSubmit = self.validateFileDialogPresentation(config, operation: operation)
            }
        } else {
            canSubmit = validateFileDialogPresentation(config, operation: operation)
        }
        return canSubmit
    }

    private func completeFileDialog(
        _ config: FileDialogConfig,
        operation: FileDialogOperation,
        outcome: FileDialogOperation.Outcome,
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard isCurrentFileDialogPresenter(operation) else {
            operation.revoke()
            return
        }
        operation.outcome = outcome
        operation.phase = .resetting
        // A normal reset can remove the presenter. The captured terminal result
        // still belongs to this operation, but a closing host cannot receive it.
        operation.presenterLease.invalidate()
        config.isPresented.wrappedValue = false
        guard isCurrentFileDialogOperation(operation) else { return }
        operation.phase = .completing
        completion?()
    }

    private func completeFileDialog<Value>(
        _ config: FileDialogConfig,
        operation: FileDialogOperation,
        result: Result<Value, Error>,
        completion: @escaping (Result<Value, Error>) -> Void
    ) {
        let outcome: FileDialogOperation.Outcome
        switch result {
        case .success: outcome = .completed
        case .failure: outcome = .failed
        }
        completeFileDialog(config, operation: operation, outcome: outcome) {
            completion(result)
        }
    }

    private func presentFileDialog(_ config: FileDialogConfig, operation: FileDialogOperation) {
        let title = operation.node.fileDialogMessage
        let defaultDirectory = operation.node.fileDialogDefaultDirectory
        guard validateFileDialogPresentation(config, operation: operation) else { return }
        let owner: FileDialogOwner
        if let scope = operation.invocationScope {
            var scopedOwner = FileDialogOwner.hosted(nil)
            scope.withInvocation { scopedOwner = self.fileDialogOwner() }
            owner = scopedOwner
        } else {
            owner = fileDialogOwner()
        }
        guard validateFileDialogPresentation(config, operation: operation) else { return }
        operation.didRequestSelection = true
        operation.isAwaitingSelection = true
        let requestIsCurrent: @MainActor () -> Bool = {
            self.canSubmitFileDialog(config, operation: operation)
        }
        switch config {
        case .exporter(let exporter):
            FileDialogManager.requestSaveFileDialog(
                defaultFilename: exporter.defaultFilename,
                allowedExtensions: FileDialogManager.fileExtensions(forContentTypes: [exporter.contentType]),
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner,
                nativeSession: nativeDialogSession,
                isCurrent: requestIsCurrent
            ) { selection in
                self.receiveFileDialogSelection(selection, config: config, operation: operation) { selection in
                    switch selection {
                    case .cancelled:
                        self.completeFileDialog(config, operation: operation, outcome: .cancelled)
                    case .failed(let error):
                        self.completeFileDialog(
                            config, operation: operation, result: .failure(error), completion: exporter.onCompletion)
                    case .selected(let url):
                        operation.phase = .accessingFile
                        let result: Result<URL, Error> = Result {
                            try exporter.write(to: url) {
                                try self.validateFileDialogAccess(config, operation: operation)
                            }
                            return url
                        }
                        self.completeFileDialog(
                            config, operation: operation, result: result, completion: exporter.onCompletion)
                    case .revoked:
                        break
                    }
                }
            }

        case .importer(let importer):
            FileDialogManager.requestOpenFileDialog(
                allowedExtensions: FileDialogManager.fileExtensions(forContentTypes: importer.allowedContentTypes),
                allowsMultipleSelection: false,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner,
                nativeSession: nativeDialogSession,
                isCurrent: requestIsCurrent
            ) { selection in
                self.receiveFileDialogSelection(selection, config: config, operation: operation) { selection in
                    switch selection {
                    case .selected(let urls):
                        let result: Result<URL, Error> =
                            urls.first.map(Result.success) ?? .failure(FileDialogError.invalidSelection)
                        self.completeFileDialog(
                            config, operation: operation, result: result, completion: importer.onCompletion)
                    case .cancelled:
                        let error = self.fileDialogCancellationError()
                        self.completeFileDialog(config, operation: operation, outcome: .cancelled) {
                            importer.onCompletion(.failure(error))
                        }
                    case .failed(let error):
                        self.completeFileDialog(
                            config, operation: operation, result: .failure(error), completion: importer.onCompletion)
                    case .revoked:
                        break
                    }
                }
            }

        case .importerMulti(let importerMulti):
            FileDialogManager.requestOpenFileDialog(
                allowedExtensions: FileDialogManager.fileExtensions(
                    forContentTypes: importerMulti.allowedContentTypes),
                allowsMultipleSelection: importerMulti.allowsMultipleSelection,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner,
                nativeSession: nativeDialogSession,
                isCurrent: requestIsCurrent
            ) { selection in
                self.receiveFileDialogSelection(selection, config: config, operation: operation) { selection in
                    switch selection {
                    case .selected(let urls):
                        let result: Result<[URL], Error> =
                            urls.isEmpty ? .failure(FileDialogError.invalidSelection) : .success(urls)
                        self.completeFileDialog(
                            config, operation: operation, result: result, completion: importerMulti.onCompletion)
                    case .cancelled:
                        let error = self.fileDialogCancellationError()
                        self.completeFileDialog(config, operation: operation, outcome: .cancelled) {
                            importerMulti.onCompletion(.failure(error))
                        }
                    case .failed(let error):
                        self.completeFileDialog(
                            config, operation: operation, result: .failure(error),
                            completion: importerMulti.onCompletion)
                    case .revoked:
                        break
                    }
                }
            }

        case .mover(let mover):
            FileDialogManager.requestSaveFileDialog(
                defaultFilename: mover.file.lastPathComponent,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner,
                nativeSession: nativeDialogSession,
                isCurrent: requestIsCurrent
            ) { selection in
                self.receiveFileDialogSelection(selection, config: config, operation: operation) { selection in
                    switch selection {
                    case .selected(let destination):
                        operation.phase = .accessingFile
                        let result: Result<URL, Error> = Result {
                            try self.validateFileDialogAccess(config, operation: operation)
                            try FileManager.default.moveItem(at: mover.file, to: destination)
                            return destination
                        }
                        self.completeFileDialog(
                            config, operation: operation, result: result, completion: mover.onCompletion)
                    case .cancelled:
                        let error = self.fileDialogCancellationError()
                        self.completeFileDialog(config, operation: operation, outcome: .cancelled) {
                            mover.onCompletion(.failure(error))
                        }
                    case .failed(let error):
                        self.completeFileDialog(
                            config, operation: operation, result: .failure(error), completion: mover.onCompletion)
                    case .revoked:
                        break
                    }
                }
            }
        }
    }

    private func fileDialogCancellationError() -> Error {
        struct FileDialogCancellationError: Error {}
        return FileDialogCancellationError()
    }

    static func applyNewNodeTransitionsRecursively(in node: ViewNode) {
        if !node.hasAppeared, !node.isInitialBuildNode, !node.didPlayInsertionTransition,
            node.transition.kind != .identity
        {
            node.applyInsertionTransition()
        }
        for child in node.children {
            applyNewNodeTransitionsRecursively(in: child)
        }
    }

    /// Stamps a host's first tree so nothing in it plays an insertion
    /// transition. Nodes that have already appeared (the host root itself)
    /// are left alone.
    static func markInitialBuildNodesRecursively(in node: ViewNode) {
        if !node.hasAppeared {
            node.isInitialBuildNode = true
        }
        for child in node.children {
            markInitialBuildNodesRecursively(in: child)
        }
    }

    /// Re-runs one already-matched node against a freshly built counterpart:
    /// the node keeps its identity (and everything the runtime hung on it —
    /// scroll offset, `hasAppeared`, focus) and adopts the new build's
    /// properties and children. This is the `nodesMatch` branch of
    /// `reconcileChildren` addressed directly, for callers that already know
    /// which node the new build corresponds to. `RetainedViewRuntime` uses it
    /// to re-seat a `GeometryReader` body on its resolved slot.
    @discardableResult
    static func adopt(
        source: ViewNode, into target: ViewNode,
        admission: RetainedLazyListAdoptionAdmission? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> RetainedLazyListAdoptionResult {
        let buttonActions = RetainedButtonActionAdoption(retainedRoots: [target], sourceRoots: [source])
        // Keep the final primitive check outside the scope that owns matching,
        // transaction and retired-property payloads. Their destruction can
        // synchronously replace or close the provider.
        let check = NodeReconcileAdmission(
            admission, source: source, target: target, lazyJournal: lazyJournal, taskAdoption: taskAdoption,
            buttonActions: buttonActions, uiaAuthority: uiaAuthority)
        var completion: RetainedLazyListAdoptionCompletion?
        let completed = performAdoption(
            source: source, into: target, admission: admission, taskAdoption: taskAdoption,
            lazyJournal: lazyJournal, buttonActions: buttonActions, uiaAuthority: check.uiaAuthority,
            completion: &completion)
        let stayedCurrent = (completed || check.uiaAuthority != nil) && check.isCurrent
        return adoptionResult(
            of: target, completed: completed && stayedCurrent,
            admission: admission, completion: completion, lazyJournal: lazyJournal, buttonActions: buttonActions,
            uiaAuthority: check.uiaAuthority, check: check)
    }

    private static func performAdoption(
        source: ViewNode, into target: ViewNode,
        admission: RetainedLazyListAdoptionAdmission?, taskAdoption: RetainedTaskAdoptionContext?,
        lazyJournal: RetainedLazyListAdoptionJournal?,
        buttonActions: RetainedButtonActionAdoption?, uiaAuthority: RetainedLazyListUIAContinuationAuthority?,
        completion: inout RetainedLazyListAdoptionCompletion?
    ) -> Bool {
        let check = NodeReconcileAdmission(
            admission, source: source, target: target, lazyJournal: lazyJournal, taskAdoption: taskAdoption,
            buttonActions: buttonActions, uiaAuthority: uiaAuthority)
        guard check.isCurrent, admission?.permitsMutation(of: target) != false else { return false }
        if lazyJournal != nil, source.containsRejectedRetainedSource { return false }
        if source === target, admission != nil || check.uiaAuthority != nil {
            lazyJournal?.recordUnchangedNode(target)
            completion = RetainedLazyListAdoptionCompletion(of: target)
            return check.recordUIACompletion(completion) && check.isCurrent
        }
        let completionSources: RetainedReconciliationSourceNodes?
        if admission == nil, lazyJournal?.isOrdinaryAdoption == true {
            guard let sources = RetainedReconciliationSourceNodes(roots: [source]) else { return false }
            completionSources = sources
        } else {
            completionSources = nil
        }
        let preservesChildren = preservesLazyListChildren(source: source, target: target)
        let newNodes = target.childrenForLazyListReconciliation(from: source)
        let oldChildren = target.children
        let plan: PreparedChildrenPlan?
        if check.requiresCheckedReconciliation {
            guard
                let prepared = prepareChildrenPlan(
                    of: target, oldChildren: oldChildren, newNodes: newNodes, admission: admission,
                    sourceParent: preservesChildren ? target : source, lazyJournal: lazyJournal,
                    buttonActions: buttonActions, uiaAuthority: check.uiaAuthority)
            else { return false }
            plan = prepared
        } else {
            plan = nil
        }
        guard check.isCurrent, plan?.isCurrent != false else { return false }
        if let plan {
            // All matching callbacks have returned. Reject an unsupported
            // input change anywhere in the plan before revoking any owner.
            guard target.supportsLazyListScrollInputAdoption(from: source), plan.supportsScrollInputAdoption else {
                return false
            }
        }
        guard admission?.beginInsertionAdoption() != false,
            admission?.beginInsertionNode(source: source, target: target, isFresh: false) != false
        else { return false }
        taskAdoption?.associate(source: source, target: target)
        guard check.isCurrent, plan?.isCurrent != false, plan?.stillOwnsOldChildren != false else { return false }
        guard check.markMutationStarted(), check.prepareTaskTransport(from: source, to: target) else { return false }
        target.invalidateRenderLifecycleCandidates()
        guard
            revokeDepartingTextInputOwnership(
                source: source, target: target, plan: plan, admission: admission, lazyJournal: lazyJournal,
                buttonActions: buttonActions, uiaAuthority: check.uiaAuthority)
        else { return false }
        guard check.isCurrent, plan?.isCurrent != false, plan?.stillOwnsOldChildren != false else { return false }
        let propertyCheck = NodeReconcileAdmission(
            admission, source: source, target: target, childrenSnapshot: plan?.childrenSnapshot,
            lazyJournal: lazyJournal, taskAdoption: taskAdoption, buttonActions: buttonActions,
            uiaAuthority: check.uiaAuthority)
        let previous = admission?.isLogicalInsertion(source: source) == true ? nil : target
        let completed = withReconcileAnimationTransaction(source: source, previous: previous, check: propertyCheck) {
            guard plan?.isCurrent != false, plan?.stillOwnsOldChildren != false else { return false }
            guard
                admission?.prepareInsertionNode(
                    source: source, target: target, transaction: RetainedBuildTransaction()) != false
            else { return false }
            guard updateNodeProperties(target: target, source: source, check: propertyCheck), propertyCheck.isCurrent
            else {
                return false
            }
            return reconcilePreparedChildren(
                of: target, oldChildren: oldChildren, newNodes: newNodes, plan: plan, admission: admission,
                preservesChildren: preservesChildren, sourceParent: source,
                taskAdoption: taskAdoption, lazyJournal: lazyJournal, completionSources: completionSources,
                buttonActions: buttonActions, uiaAuthority: check.uiaAuthority)
        }
        guard completed, check.isCurrent else { return false }
        check.recordCompletedNode(from: source, to: target)
        guard check.isCurrent else { return false }
        if check.requiresCheckedReconciliation || buttonActions != nil {
            completion = RetainedLazyListAdoptionCompletion(of: target)
            guard check.recordUIACompletion(completion) else { return false }
        }
        return true
    }

    private static func preservesLazyListChildren(source: ViewNode, target: ViewNode) -> Bool {
        guard let previous = target.retainedLazyListAdapter, let incoming = source.retainedLazyListAdapter else {
            return false
        }
        return incoming === previous || incoming.canInheritMountedRecords(from: previous, in: target)
    }

    private static func adoptionResult(
        of parent: ViewNode, completed: Bool, admission: RetainedLazyListAdoptionAdmission?,
        completion: RetainedLazyListAdoptionCompletion?, lazyJournal: RetainedLazyListAdoptionJournal?,
        buttonActions: RetainedButtonActionAdoption?, uiaAuthority: RetainedLazyListUIAContinuationAuthority?,
        check: NodeReconcileAdmission
    ) -> RetainedLazyListAdoptionResult {
        let isComplete =
            completed && admission?.isCurrent != false && uiaAuthority?.isCurrent != false
            && ((admission == nil && lazyJournal?.isOrdinaryAdoption != false && uiaAuthority == nil)
                || completion?.isCurrent == true)
        let actionsAccepted =
            buttonActions?.finish(completed: isComplete, check: check, completion: completion) ?? isComplete
        return RetainedLazyListAdoptionResult(
            completed: isComplete && actionsAccepted,
            didMutate: (admission?.didMutate ?? (lazyJournal?.hasAcceptedContributions ?? completed))
                || uiaAuthority?.didMutate == true,
            children: parent.children, completion: isComplete && actionsAccepted ? completion : nil)
    }

    /// The actual retirement scope already owns matching. Preserve its parent
    /// child table while removal modifiers and the animation clock can reenter.
    @MainActor
    static func makeRemovalTransitionCheck(
        admission: RetainedLazyListAdoptionAdmission?, target: ViewNode, parent: ViewNode,
        sourceParent: ViewNode? = nil, proposedChildren: [ViewNode],
        lazyJournal: RetainedLazyListAdoptionJournal?, buttonActions: RetainedButtonActionAdoption? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> NodeReconcileAdmission? {
        let snapshot = ReconcileChildrenSnapshot(
            parent: parent, oldChildren: parent.children, sourceParent: sourceParent,
            newNodes: sourceParent?.children ?? [], ancestor: nil)
        // Proposed children can include both retained matches and detached
        // construction roots. Keep their entire native subtrees current across
        // every removal callout, without making them departing roots. This
        // private snapshot never begins transfers or weakens its order checks.
        var proposedIdentities: Set<ObjectIdentifier> = []
        for node in proposedChildren {
            guard proposedIdentities.insert(ObjectIdentifier(node)).inserted,
                snapshot.recordPreparedSubtree(of: node)
            else { return nil }
        }
        let check = NodeReconcileAdmission(
            admission, source: sourceParent, target: target, childrenSnapshot: snapshot, lazyJournal: lazyJournal,
            buttonActions: buttonActions, uiaAuthority: uiaAuthority)
        return check.isCurrent ? check : nil
    }

    /// The token is concrete and performs only native generation/lifetime
    /// reads. Per-node witnesses reject detach/reattach even when a callback
    /// restores the same parent and runtime before returning.
    /// An optional UIA authority belongs to this transient operation, never to
    /// the accepted node or completion. A journal may supply the same original
    /// authority; a conflicting explicit authority is rejected.
    @MainActor
    struct NodeReconcileAdmission {
        let admission: RetainedLazyListAdoptionAdmission?
        let lazyJournal: RetainedLazyListAdoptionJournal?
        let taskAdoption: RetainedTaskAdoptionContext?
        let buttonActions: RetainedButtonActionAdoption?
        let uiaAuthority: RetainedLazyListUIAContinuationAuthority?
        private let hasConsistentUIAAuthority: Bool
        weak var source: ViewNode?
        let sourceAttachment: RetainedLazyListAttachmentProof?
        let targetAttachment: RetainedLazyListAttachmentProof?
        let sourceIdentity: RetainedLazyListViewIdentityProof?
        let targetIdentity: RetainedLazyListViewIdentityProof?
        fileprivate let childrenSnapshot: ReconcileChildrenSnapshot?

        fileprivate init(
            _ admission: RetainedLazyListAdoptionAdmission?, source: ViewNode? = nil, target: ViewNode,
            childrenSnapshot: ReconcileChildrenSnapshot? = nil,
            lazyJournal: RetainedLazyListAdoptionJournal? = nil,
            taskAdoption: RetainedTaskAdoptionContext? = nil,
            buttonActions: RetainedButtonActionAdoption? = nil,
            uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
        ) {
            self.admission = admission
            self.lazyJournal = lazyJournal
            self.taskAdoption = taskAdoption
            self.buttonActions = buttonActions
            let journalAuthority = lazyJournal?.uiaContinuationAuthority
            self.uiaAuthority = uiaAuthority ?? journalAuthority
            hasConsistentUIAAuthority =
                uiaAuthority == nil || journalAuthority == nil || uiaAuthority === journalAuthority
            self.source = source
            let isChecked =
                admission != nil || lazyJournal?.isOrdinaryAdoption == false || self.uiaAuthority != nil
            sourceAttachment = isChecked ? source?.captureLazyListAttachmentProof() : nil
            targetAttachment = isChecked ? target.captureLazyListAttachmentProof() : nil
            sourceIdentity = isChecked ? source?.captureLazyListIdentityProof() : nil
            targetIdentity = isChecked ? target.captureLazyListIdentityProof() : nil
            self.childrenSnapshot = childrenSnapshot
        }

        var isCurrent: Bool {
            guard hasConsistentUIAAuthority else { return false }
            let current =
                buttonActions?.isCurrent != false && uiaAuthority?.isCurrent != false
                && admission?.isCurrent != false && sourceAttachment?.isCurrent != false
                && targetAttachment?.isCurrent != false && sourceIdentity?.isCurrent != false
                && targetIdentity?.isCurrent != false && childrenSnapshot?.isCurrent != false
                && (lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false)
            if !current { uiaAuthority?.revoke() }
            return current
        }

        fileprivate var requiresCheckedReconciliation: Bool {
            admission != nil || lazyJournal?.isOrdinaryAdoption == false || uiaAuthority != nil
        }

        func markMutationStarted() -> Bool {
            guard isCurrent else { return false }
            if let lazyJournal {
                let started = lazyJournal.markMutationStarted()
                guard lazyJournal.isOrdinaryAdoption || started else { return false }
            }
            guard uiaAuthority == nil || isCurrent else { return false }
            admission?.markMutationStarted()
            uiaAuthority?.markMutationStarted()
            return true
        }

        func preparePropertyCopy(from source: ViewNode, to target: ViewNode, keyPath: PartialKeyPath<ViewNode>) -> Bool
        {
            guard uiaAuthority == nil || isCurrent else { return false }
            guard let lazyJournal else { return isCurrent }
            let prepared = lazyJournal.preparePropertyCopy(from: source, to: target, keyPath: keyPath)
            return (lazyJournal.isOrdinaryAdoption || prepared) && (uiaAuthority == nil || isCurrent)
        }

        func prepareTaskTransport(from source: ViewNode, to target: ViewNode) -> Bool {
            guard let lazyJournal else { return isCurrent }
            for candidate in source.existingRetainedTaskState?.lazyCandidateDeclarations() ?? [] {
                guard isCurrent else { return false }
                let accepted = lazyJournal.recordAcceptedTaskDeclarationTransport(
                    from: source, to: target, declarationIDs: candidate.declarations)
                associate(accepted, from: source, to: target)
            }
            for candidate in source.existingRetainedTaskState?.descriptorCandidateDeclarations() ?? [] {
                guard isCurrent else { return false }
                lazyJournal.recordAcceptedDescriptorTaskDeclarationTransport(
                    from: source, to: target, declarationIDs: candidate.declarations)
                associate([], from: source, to: target)
            }
            return isCurrent
        }

        func associate(
            _ groups: [RetainedLazyListAcceptedTaskGroup], from source: ViewNode, to target: ViewNode
        ) {
            guard let lazyJournal else { return }
            for group in groups {
                taskAdoption?.associateLazyAccepted(group, journal: lazyJournal)
            }
            for group in lazyJournal.takeAcceptedDescriptorTaskGroups() {
                taskAdoption?.associateDescriptorAccepted(group, journal: lazyJournal)
            }
        }

        func recordCompletedNode(from source: ViewNode, to target: ViewNode) {
            guard let lazyJournal else { return }
            associate(lazyJournal.recordAcceptedAttachment(from: source, to: target), from: source, to: target)
            associate(lazyJournal.recordCompletedNode(from: source, to: target), from: source, to: target)
            admission?.recordCompletedOwnedSource(from: source, to: target, journal: lazyJournal)
        }

        /// Later siblings must still satisfy the native witnesses of completed
        /// descendants. The original UIA operation owns those obligations;
        /// neither an accepted node nor the completion retains its authority.
        fileprivate func recordUIACompletion(_ completion: RetainedLazyListAdoptionCompletion?) -> Bool {
            guard let uiaAuthority else { return true }
            guard isCurrent else { return false }
            guard let completion else {
                uiaAuthority.revoke()
                return false
            }
            return uiaAuthority.recordCompletion(completion)
        }
    }

    /// A same-parent reorder does not change the children's attachment stamps.
    /// Preserve old and selected source order through matching and property
    /// callouts, including callbacks in descendants. Each plan retires only its
    /// own order assertions when it begins transfers; ancestor lists stay checked.
    @MainActor
    fileprivate final class ReconcileChildrenSnapshot {
        @MainActor
        private struct Membership {
            weak var owner: ViewNode?
            let attachment: RetainedLazyListAttachmentProof
            let identity: RetainedLazyListViewIdentityProof
            let children: [ObjectIdentifier]

            init(owner: ViewNode, children: [ViewNode]) {
                self.owner = owner
                attachment = owner.captureLazyListAttachmentProof()
                identity = owner.captureLazyListIdentityProof()
                self.children = children.map(ObjectIdentifier.init)
            }

            var ownerIsCurrent: Bool { attachment.isCurrent && identity.isCurrent }

            var matchesOrder: Bool {
                guard let owner, owner.children.count == children.count else { return false }
                return zip(owner.children, children).allSatisfy { pair in ObjectIdentifier(pair.0) == pair.1 }
            }
        }

        private let retained: Membership
        private let source: Membership?
        private let ancestor: ReconcileChildrenSnapshot?
        private var preparedSubtrees: [RetainedLazyListAdoptionCompletion] = []
        private var transfersHaveStarted = false

        init(
            parent: ViewNode, oldChildren: [ViewNode], sourceParent: ViewNode?, newNodes: [ViewNode],
            ancestor: ReconcileChildrenSnapshot?
        ) {
            retained = Membership(owner: parent, children: oldChildren)
            source = sourceParent.map { Membership(owner: $0, children: newNodes) }
            self.ancestor = ancestor
        }

        var isCurrent: Bool {
            guard ancestor?.isCurrent != false, retained.ownerIsCurrent, source?.ownerIsCurrent != false else {
                return false
            }
            guard !transfersHaveStarted else { return true }
            return retained.matchesOrder && source?.matchesOrder != false
                && preparedSubtrees.allSatisfy { $0.isCurrent }
        }

        /// Matching identifies fresh roots before property or insertion
        /// callbacks. Keep their full native proofs until the transfer plan
        /// takes ownership; attaching them would invalidate these proofs.
        func recordPreparedSubtree(of node: ViewNode) -> Bool {
            guard !transfersHaveStarted, isCurrent, let completion = RetainedLazyListAdoptionCompletion(of: node),
                completion.isCurrent
            else { return false }
            preparedSubtrees.append(completion)
            return isCurrent
        }

        func beginTransfers() -> Bool {
            guard isCurrent else { return false }
            transfersHaveStarted = true
            return true
        }
    }

    /// Checked calls prepare identity matching once. Both revocation and
    /// adoption consume this plan; no second user Hashable lookup can change
    /// the set of owners after departure preparation has started.
    @MainActor
    private final class PreparedChildrenPlan {
        @MainActor
        struct Entry {
            let source: ViewNode
            let retained: ViewNode?
            let sourceAttachment: RetainedLazyListAttachmentProof
            let retainedAttachment: RetainedLazyListAttachmentProof?
            let sourceIdentity: RetainedLazyListViewIdentityProof
            let retainedIdentity: RetainedLazyListViewIdentityProof?
            let descendants: PreparedChildrenPlan?

            var isCurrent: Bool {
                sourceAttachment.isCurrent && retainedAttachment?.isCurrent != false
                    && sourceIdentity.isCurrent && retainedIdentity?.isCurrent != false
            }
        }

        let parent: ViewNode
        let oldChildren: [ViewNode]
        let parentAttachment: RetainedLazyListAttachmentProof
        let parentIdentity: RetainedLazyListViewIdentityProof
        let oldAttachments: [RetainedLazyListAttachmentProof]
        let oldIdentities: [RetainedLazyListViewIdentityProof]
        let childrenSnapshot: ReconcileChildrenSnapshot?
        let entries: [Entry]
        let uiaAuthority: RetainedLazyListUIAContinuationAuthority?

        init(
            parent: ViewNode, oldChildren: [ViewNode], parentAttachment: RetainedLazyListAttachmentProof,
            parentIdentity: RetainedLazyListViewIdentityProof, oldAttachments: [RetainedLazyListAttachmentProof],
            oldIdentities: [RetainedLazyListViewIdentityProof], childrenSnapshot: ReconcileChildrenSnapshot?,
            entries: [Entry], uiaAuthority: RetainedLazyListUIAContinuationAuthority?
        ) {
            self.parent = parent
            self.oldChildren = oldChildren
            self.parentAttachment = parentAttachment
            self.parentIdentity = parentIdentity
            self.oldAttachments = oldAttachments
            self.oldIdentities = oldIdentities
            self.childrenSnapshot = childrenSnapshot
            self.entries = entries
            self.uiaAuthority = uiaAuthority
        }

        var isCurrent: Bool {
            let current =
                uiaAuthority?.isCurrent != false && parentAttachment.isCurrent && parentIdentity.isCurrent
                && oldAttachments.allSatisfy { $0.isCurrent }
                && oldIdentities.allSatisfy { $0.isCurrent } && childrenSnapshot?.isCurrent != false
                && entries.allSatisfy { $0.isCurrent }
            if !current { uiaAuthority?.revoke() }
            return current
        }

        var stillOwnsOldChildren: Bool {
            let current = ComponentHost.sameChildren(parent.children, oldChildren)
            if !current { uiaAuthority?.revoke() }
            return current
        }

        var supportsScrollInputAdoption: Bool {
            for entry in entries {
                guard let retained = entry.retained, retained !== entry.source else { continue }
                guard retained.supportsLazyListScrollInputAdoption(from: entry.source),
                    entry.descendants?.supportsScrollInputAdoption != false
                else { return false }
            }
            return true
        }
    }

    private static func sameChildren(_ lhs: [ViewNode], _ rhs: [ViewNode]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { pair in pair.0 === pair.1 }
    }

    private static func prepareChildrenPlan(
        of parent: ViewNode, oldChildren: [ViewNode], newNodes: [ViewNode],
        admission: RetainedLazyListAdoptionAdmission?, sourceParent: ViewNode? = nil,
        inheritedChildren: ReconcileChildrenSnapshot? = nil, depth: Int = 0,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        buttonActions: RetainedButtonActionAdoption? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> PreparedChildrenPlan? {
        guard buttonActions?.isCurrent != false, admission?.isCurrent != false, uiaAuthority?.isCurrent != false,
            (uiaAuthority != nil && lazyJournal?.isOrdinaryAdoption == true)
                || lazyJournal?.canContinueAdoption != false,
            depth <= ViewNode.maximumTraversalDepth,
            sameChildren(parent.children, oldChildren)
        else { return nil }
        if let sourceParent, !parent.canAdoptStagedLazyListAdapter(from: sourceParent) { return nil }
        let parentAttachment = parent.captureLazyListAttachmentProof()
        let parentIdentity = parent.captureLazyListIdentityProof()
        let oldAttachments = oldChildren.map { $0.captureLazyListAttachmentProof() }
        let sourceAttachments = newNodes.map { $0.captureLazyListAttachmentProof() }
        let oldIdentities = oldChildren.map { $0.captureLazyListIdentityProof() }
        let sourceIdentities = newNodes.map { $0.captureLazyListIdentityProof() }
        let childrenSnapshot = ReconcileChildrenSnapshot(
            parent: parent, oldChildren: oldChildren, sourceParent: sourceParent, newNodes: newNodes,
            ancestor: inheritedChildren)
        guard
            let matches = matchingChildren(
                oldChildren: oldChildren, newNodes: newNodes, admission: admission, parent: parent,
                childrenSnapshot: childrenSnapshot, lazyJournal: lazyJournal, buttonActions: buttonActions,
                uiaAuthority: uiaAuthority),
            buttonActions?.isCurrent != false, admission?.isCurrent != false, uiaAuthority?.isCurrent != false,
            (uiaAuthority != nil && lazyJournal?.isOrdinaryAdoption == true)
                || lazyJournal?.canContinueAdoption != false,
            parentAttachment.isCurrent, parentIdentity.isCurrent,
            oldAttachments.allSatisfy({ $0.isCurrent }), sourceAttachments.allSatisfy({ $0.isCurrent }),
            oldIdentities.allSatisfy({ $0.isCurrent }), sourceIdentities.allSatisfy({ $0.isCurrent }),
            sameChildren(parent.children, oldChildren)
        else { return nil }
        for (index, source) in newNodes.enumerated() where matches[index] == nil {
            guard childrenSnapshot.recordPreparedSubtree(of: source) else { return nil }
        }
        var entries: [PreparedChildrenPlan.Entry] = []
        entries.reserveCapacity(newNodes.count)
        for (index, source) in newNodes.enumerated() {
            guard buttonActions?.isCurrent != false, admission?.isCurrent != false, uiaAuthority?.isCurrent != false,
                (uiaAuthority != nil && lazyJournal?.isOrdinaryAdoption == true)
                    || lazyJournal?.canContinueAdoption != false,
                parentAttachment.isCurrent, parentIdentity.isCurrent,
                sourceAttachments[index].isCurrent, sourceIdentities[index].isCurrent, childrenSnapshot.isCurrent
            else {
                return nil
            }
            let retained = matches[index]
            let retainedAttachment = retained?.captureLazyListAttachmentProof()
            let retainedIdentity = retained?.captureLazyListIdentityProof()
            let descendants: PreparedChildrenPlan?
            if let retained, retained !== source {
                let sourceParent = preservesLazyListChildren(source: source, target: retained) ? retained : source
                guard
                    let childPlan = prepareChildrenPlan(
                        of: retained, oldChildren: retained.children,
                        newNodes: retained.childrenForLazyListReconciliation(from: source),
                        admission: admission, sourceParent: sourceParent, inheritedChildren: childrenSnapshot,
                        depth: depth + 1, lazyJournal: lazyJournal, buttonActions: buttonActions,
                        uiaAuthority: uiaAuthority)
                else { return nil }
                descendants = childPlan
            } else {
                descendants = nil
            }
            entries.append(
                .init(
                    source: source, retained: retained, sourceAttachment: sourceAttachments[index],
                    retainedAttachment: retainedAttachment, sourceIdentity: sourceIdentities[index],
                    retainedIdentity: retainedIdentity, descendants: descendants))
        }
        let plan = PreparedChildrenPlan(
            parent: parent, oldChildren: oldChildren, parentAttachment: parentAttachment,
            parentIdentity: parentIdentity, oldAttachments: oldAttachments, oldIdentities: oldIdentities,
            childrenSnapshot: childrenSnapshot, entries: entries, uiaAuthority: uiaAuthority)
        let surviving = Set(entries.compactMap(\.retained).map(ObjectIdentifier.init))
        let departing = oldChildren.filter { !surviving.contains(ObjectIdentifier($0)) }
        guard
            ViewNode.supportsLazyListRemoval(
                of: departing, admission: admission, lazyJournal: lazyJournal, uiaAuthority: uiaAuthority)
        else {
            return nil
        }
        return buttonActions?.isCurrent != false && admission?.isCurrent != false && uiaAuthority?.isCurrent != false
            && ((uiaAuthority != nil && lazyJournal?.isOrdinaryAdoption == true)
                || lazyJournal?.canContinueAdoption != false)
            && plan.isCurrent && plan.stillOwnsOldChildren ? plan : nil
    }

    private static var inheritedTransaction: Transaction? {
        if let currentTransaction { return currentTransaction }
        guard let animation = currentAnimationTransaction else { return nil }
        return Transaction(animation: Animation(duration: animation.duration, easing: animation.easing))
    }

    /// Modifier configuration belongs to the new build, but value triggers
    /// belong to the retained identity. Scope the resulting transaction over
    /// both the node and its children, restoring the parent before siblings.
    private static func withReconcileAnimationTransaction(
        source: ViewNode, previous: ViewNode?, check: NodeReconcileAdmission, perform body: () -> Bool
    ) -> Bool {
        guard check.isCurrent else { return false }
        let modifiers = source.reconcileAnimationModifiers
        guard !modifiers.isEmpty else {
            return body()
        }
        let previousModifiers = previous?.reconcileAnimationModifiers ?? []
        var transaction = inheritedTransaction ?? Transaction()
        var didApplyModifier = false
        for index in modifiers.indices.reversed() {
            guard check.isCurrent else { return false }
            let previousModifier = previousModifiers.indices.contains(index) ? previousModifiers[index] : nil
            if modifiers[index].apply(
                to: &transaction, previous: previousModifier, admission: check.admission, nativeCheck: check)
            {
                didApplyModifier = true
            }
            guard check.isCurrent else { return false }
        }
        guard didApplyModifier else {
            return body()
        }

        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = transaction
        currentAnimationTransaction =
            transaction.disablesAnimations
            ? nil : transaction.animation.map { ($0.duration, $0.easing) }
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        guard check.isCurrent else { return false }
        return body()
    }

    private static func prepareInsertedSubtree(
        _ node: ViewNode, admission: RetainedLazyListAdoptionAdmission?,
        taskAdoption: RetainedTaskAdoptionContext?,
        inheritedChildren: ReconcileChildrenSnapshot? = nil, depth: Int = 0,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        buttonActions: RetainedButtonActionAdoption? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> Bool {
        let children = node.children
        let childrenSnapshot =
            admission == nil && lazyJournal?.isOrdinaryAdoption != false && uiaAuthority == nil
            ? nil
            : ReconcileChildrenSnapshot(
                parent: node, oldChildren: children, sourceParent: nil, newNodes: children, ancestor: inheritedChildren)
        let check = NodeReconcileAdmission(
            admission, source: node, target: node, childrenSnapshot: childrenSnapshot,
            lazyJournal: lazyJournal, taskAdoption: taskAdoption, buttonActions: buttonActions,
            uiaAuthority: uiaAuthority)
        guard check.isCurrent, !check.requiresCheckedReconciliation || depth <= ViewNode.maximumTraversalDepth
        else { return false }
        guard admission?.beginInsertionNode(source: node, target: node, isFresh: true) != false else { return false }
        taskAdoption?.associate(source: node, target: node)
        guard check.isCurrent else { return false }
        let completed = withReconcileAnimationTransaction(source: node, previous: nil, check: check) {
            let transaction = RetainedBuildTransaction()
            node.retainedLazyListAdapter?.stageInsertionBuildTransaction(transaction)
            guard admission?.prepareInsertionNode(source: node, target: node, transaction: transaction) != false else {
                return false
            }
            guard
                node.retainInsertionTransaction(
                    inheritedTransaction, admission: admission, uiaAuthority: check.uiaAuthority), check.isCurrent
            else {
                return false
            }
            for child in children {
                guard check.isCurrent,
                    (admission == nil && check.uiaAuthority == nil) || sameChildren(children, node.children),
                    prepareInsertedSubtree(
                        child, admission: admission, taskAdoption: taskAdoption,
                        inheritedChildren: childrenSnapshot, depth: depth + 1, lazyJournal: lazyJournal,
                        buttonActions: buttonActions, uiaAuthority: check.uiaAuthority)
                else { return false }
            }
            return check.isCurrent
                && ((admission == nil && check.uiaAuthority == nil) || sameChildren(children, node.children))
        }
        return completed && check.isCurrent
    }

    /// Reconciliation claims typed identities first, legacy tags second,
    /// then considers the next unclaimed positional candidate. A typed node
    /// never bridges to an untyped node through a tag or matching layout.
    ///
    /// Each old node can be claimed once, including when duplicate identities
    /// occur. Survivors keep their nodes and move into the new order, retaining
    /// runtime-owned focus, scroll state, and animations. Raw retained trees
    /// without typed identities keep their existing matching behavior.
    @discardableResult
    static func reconcileChildren(
        of parent: ViewNode, oldChildren: [ViewNode], newNodes: [ViewNode],
        admission: RetainedLazyListAdoptionAdmission? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> RetainedLazyListAdoptionResult {
        let buttonActions = RetainedButtonActionAdoption(retainedRoots: [parent], sourceRoots: newNodes)
        let check = NodeReconcileAdmission(
            admission, target: parent, lazyJournal: lazyJournal, taskAdoption: taskAdoption,
            buttonActions: buttonActions, uiaAuthority: uiaAuthority)
        var completion: RetainedLazyListAdoptionCompletion?
        let completed = performChildrenReconciliation(
            of: parent, oldChildren: oldChildren, newNodes: newNodes, admission: admission,
            taskAdoption: taskAdoption, lazyJournal: lazyJournal, buttonActions: buttonActions,
            uiaAuthority: check.uiaAuthority, completion: &completion)
        let stayedCurrent = (completed || check.uiaAuthority != nil) && check.isCurrent
        return adoptionResult(
            of: parent, completed: completed && stayedCurrent,
            admission: admission, completion: completion, lazyJournal: lazyJournal, buttonActions: buttonActions,
            uiaAuthority: check.uiaAuthority, check: check)
    }

    private static func performChildrenReconciliation(
        of parent: ViewNode, oldChildren: [ViewNode], newNodes: [ViewNode],
        admission: RetainedLazyListAdoptionAdmission?, taskAdoption: RetainedTaskAdoptionContext?,
        lazyJournal: RetainedLazyListAdoptionJournal?,
        buttonActions: RetainedButtonActionAdoption?, uiaAuthority: RetainedLazyListUIAContinuationAuthority?,
        completion: inout RetainedLazyListAdoptionCompletion?
    ) -> Bool {
        let check = NodeReconcileAdmission(
            admission, target: parent, lazyJournal: lazyJournal, taskAdoption: taskAdoption,
            buttonActions: buttonActions, uiaAuthority: uiaAuthority)
        guard check.isCurrent, admission?.permitsMutation(of: parent) != false else { return false }
        if lazyJournal != nil, ViewNode.containsRejectedRetainedSource(in: newNodes) { return false }
        let completionSources: RetainedReconciliationSourceNodes?
        if admission == nil, lazyJournal?.isOrdinaryAdoption == true {
            guard let sources = RetainedReconciliationSourceNodes(roots: newNodes) else { return false }
            completionSources = sources
        } else {
            completionSources = nil
        }
        let plan: PreparedChildrenPlan?
        if check.requiresCheckedReconciliation {
            guard
                let prepared = prepareChildrenPlan(
                    of: parent, oldChildren: oldChildren, newNodes: newNodes, admission: admission,
                    lazyJournal: lazyJournal, buttonActions: buttonActions, uiaAuthority: check.uiaAuthority)
            else { return false }
            plan = prepared
        } else {
            plan = nil
        }
        // Inspect the complete plan after every authored matching callback,
        // before lifecycle invalidation, editor revocation, or property copies.
        guard check.isCurrent, plan?.isCurrent != false, plan?.supportsScrollInputAdoption != false else {
            return false
        }
        guard admission?.beginInsertionAdoption() != false else { return false }
        if let admission, let lazyJournal {
            guard admission.claimDepartingEmptyRows(journal: lazyJournal), check.isCurrent else { return false }
        }
        guard check.markMutationStarted() else { return false }
        parent.invalidateRenderLifecycleCandidates()
        // Mark every departure before any branch starts its callbacks. A
        // callback in an earlier branch can otherwise replay a later editor
        // that will leave in the same adoption but still reaches the root.
        guard
            revokeDepartingTextInputOwnership(
                oldChildren: oldChildren, newNodes: newNodes, plan: plan, admission: admission,
                parent: parent, lazyJournal: lazyJournal, buttonActions: buttonActions, uiaAuthority: check.uiaAuthority
            ), check.isCurrent
        else { return false }
        guard
            reconcilePreparedChildren(
                of: parent, oldChildren: oldChildren, newNodes: newNodes, plan: plan, admission: admission,
                taskAdoption: taskAdoption, lazyJournal: lazyJournal, completionSources: completionSources,
                buttonActions: buttonActions, uiaAuthority: check.uiaAuthority),
            check.isCurrent
        else { return false }
        if check.requiresCheckedReconciliation || buttonActions != nil {
            completion = RetainedLazyListAdoptionCompletion(of: parent)
            guard check.recordUIACompletion(completion) else { return false }
        }
        return true
    }

    /// Dictionary and equality operations may execute application Hashable
    /// code. Their post-checks inspect only these native snapshots, including
    /// an equal-value identity assignment or a change to the old child list.
    @MainActor
    private struct MatchingChildrenAdmission {
        let admission: RetainedLazyListAdoptionAdmission?
        let lazyJournal: RetainedLazyListAdoptionJournal?
        let buttonActions: RetainedButtonActionAdoption?
        let uiaAuthority: RetainedLazyListUIAContinuationAuthority?
        private let hasConsistentUIAAuthority: Bool
        weak var parent: ViewNode?
        let hadParent: Bool
        let parentCheck: NodeReconcileAdmission?
        let oldChildIdentifiers: [ObjectIdentifier]
        let attachments: [RetainedLazyListAttachmentProof]
        let identities: [RetainedLazyListViewIdentityProof]
        let childrenSnapshot: ReconcileChildrenSnapshot?

        init(
            _ admission: RetainedLazyListAdoptionAdmission?, oldChildren: [ViewNode], newNodes: [ViewNode],
            parent: ViewNode?, childrenSnapshot: ReconcileChildrenSnapshot?,
            lazyJournal: RetainedLazyListAdoptionJournal?, buttonActions: RetainedButtonActionAdoption?,
            uiaAuthority: RetainedLazyListUIAContinuationAuthority?
        ) {
            self.admission = admission
            self.lazyJournal = lazyJournal
            self.buttonActions = buttonActions
            let journalAuthority = lazyJournal?.uiaContinuationAuthority
            let effectiveAuthority = uiaAuthority ?? journalAuthority
            self.uiaAuthority = effectiveAuthority
            hasConsistentUIAAuthority =
                uiaAuthority == nil || journalAuthority == nil || uiaAuthority === journalAuthority
            let checked =
                admission != nil || lazyJournal?.isOrdinaryAdoption == false || buttonActions != nil
                || effectiveAuthority != nil
            self.parent = checked ? parent : nil
            hadParent = checked && parent != nil
            parentCheck =
                checked
                ? parent.map {
                    NodeReconcileAdmission(
                        admission, target: $0, lazyJournal: lazyJournal, buttonActions: buttonActions,
                        uiaAuthority: effectiveAuthority)
                } : nil
            oldChildIdentifiers = checked ? oldChildren.map(ObjectIdentifier.init) : []
            let nodes = checked ? oldChildren + newNodes : []
            attachments = nodes.map { $0.captureLazyListAttachmentProof() }
            identities = nodes.map { $0.captureLazyListIdentityProof() }
            self.childrenSnapshot = childrenSnapshot
        }

        var isCurrent: Bool {
            guard hasConsistentUIAAuthority else { return false }
            guard buttonActions?.isCurrent != false, uiaAuthority?.isCurrent != false,
                admission?.isCurrent != false, parentCheck?.isCurrent != false,
                attachments.allSatisfy({ $0.isCurrent }), identities.allSatisfy({ $0.isCurrent }),
                childrenSnapshot?.isCurrent != false,
                lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false
            else {
                uiaAuthority?.revoke()
                return false
            }
            guard hadParent else { return true }
            guard let parent, parent.children.count == oldChildIdentifiers.count else {
                uiaAuthority?.revoke()
                return false
            }
            let current = zip(parent.children, oldChildIdentifiers).allSatisfy {
                pair in ObjectIdentifier(pair.0) == pair.1
            }
            if !current { uiaAuthority?.revoke() }
            return current
        }
    }

    private static func matchingChildren(
        oldChildren: [ViewNode], newNodes: [ViewNode], admission: RetainedLazyListAdoptionAdmission? = nil,
        parent: ViewNode? = nil, childrenSnapshot: ReconcileChildrenSnapshot? = nil,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        buttonActions: RetainedButtonActionAdoption? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> [ViewNode?]? {
        let check = MatchingChildrenAdmission(
            admission, oldChildren: oldChildren, newNodes: newNodes, parent: parent,
            childrenSnapshot: childrenSnapshot, lazyJournal: lazyJournal, buttonActions: buttonActions,
            uiaAuthority: uiaAuthority)
        guard check.isCurrent else { return nil }
        if check.uiaAuthority != nil {
            return matchingChildrenWhileUIAAuthorized(oldChildren: oldChildren, newNodes: newNodes, check: check)
        }
        // A single candidate has no competing claims; the same typed, tag,
        // and layout rules can be applied without constructing lookup tables.
        if oldChildren.count == 1 && newNodes.count == 1 {
            let match = nodesMatch(oldChildren[0], newNodes[0]) ? oldChildren[0] : nil
            return check.isCurrent ? [match] : nil
        }

        var matches = [ViewNode?](repeating: nil, count: newNodes.count)
        var isClaimed = [Bool](repeating: false, count: oldChildren.count)

        var oldIndicesByIdentity: [RetainedViewIdentity: [Int]] = [:]
        var oldIndicesByTag: [String: [Int]] = [:]
        for (index, oldNode) in oldChildren.enumerated() {
            guard check.isCurrent else { return nil }
            if let identity = oldNode.retainedViewIdentity {
                oldIndicesByIdentity[identity, default: []].append(index)
                guard check.isCurrent else { return nil }
            } else if let tag = oldNode.nodeTag {
                oldIndicesByTag[tag, default: []].append(index)
            }
        }

        if !oldIndicesByIdentity.isEmpty {
            for (newIndex, newNode) in newNodes.enumerated() {
                guard check.isCurrent else { return nil }
                guard let identity = newNode.retainedViewIdentity else { continue }
                let found = oldIndicesByIdentity[identity]
                guard check.isCurrent else { return nil }
                guard var candidates = found, !candidates.isEmpty else { continue }
                let oldIndex = candidates.removeFirst()
                oldIndicesByIdentity[identity] = candidates
                guard check.isCurrent else { return nil }
                matches[newIndex] = oldChildren[oldIndex]
                isClaimed[oldIndex] = true
            }
        }

        if !oldIndicesByTag.isEmpty {
            for (newIndex, newNode) in newNodes.enumerated() {
                guard check.isCurrent else { return nil }
                guard newNode.retainedViewIdentity == nil, let tag = newNode.nodeTag,
                    var candidates = oldIndicesByTag[tag], !candidates.isEmpty
                else { continue }
                let oldIndex = candidates.removeFirst()
                oldIndicesByTag[tag] = candidates
                matches[newIndex] = oldChildren[oldIndex]
                isClaimed[oldIndex] = true
            }
        }

        var cursor = 0
        for (newIndex, newNode) in newNodes.enumerated() where matches[newIndex] == nil {
            guard check.isCurrent else { return nil }
            while cursor < oldChildren.count {
                if isClaimed[cursor] {
                    cursor += 1
                    continue
                }
                let matchesPosition = nodesMatch(oldChildren[cursor], newNode)
                guard check.isCurrent else { return nil }
                if matchesPosition {
                    matches[newIndex] = oldChildren[cursor]
                    isClaimed[cursor] = true
                    cursor += 1
                }
                break
            }
        }

        return check.isCurrent ? matches : nil
    }

    /// A composed typed identity can execute several authored key callbacks.
    /// UIA matching uses native hash buckets so revocation is checked between
    /// those callbacks, while preserving typed, tag and positional claim order.
    /// The ordinary path above keeps its existing dictionary behavior.
    private static func matchingChildrenWhileUIAAuthorized(
        oldChildren: [ViewNode], newNodes: [ViewNode], check: MatchingChildrenAdmission
    ) -> [ViewNode?]? {
        guard check.isCurrent else { return nil }
        if oldChildren.count == 1 && newNodes.count == 1 {
            guard let matches = checkedNodesMatch(oldChildren[0], newNodes[0], check: check), check.isCurrent else {
                return nil
            }
            return [matches ? oldChildren[0] : nil]
        }

        var matches = [ViewNode?](repeating: nil, count: newNodes.count)
        var isClaimed = [Bool](repeating: false, count: oldChildren.count)
        var oldIndicesByIdentityHash: [Int: [Int]] = [:]
        var oldIndicesByTag: [String: [Int]] = [:]
        for (index, oldNode) in oldChildren.enumerated() {
            guard check.isCurrent else { return nil }
            if let identity = oldNode.retainedViewIdentity {
                guard let hash = checkedIdentityHash(identity, check: check), check.isCurrent else { return nil }
                oldIndicesByIdentityHash[hash, default: []].append(index)
            } else if let tag = oldNode.nodeTag {
                oldIndicesByTag[tag, default: []].append(index)
            }
        }

        if !oldIndicesByIdentityHash.isEmpty {
            for (newIndex, newNode) in newNodes.enumerated() {
                guard check.isCurrent else { return nil }
                guard let identity = newNode.retainedViewIdentity else { continue }
                guard let hash = checkedIdentityHash(identity, check: check), check.isCurrent else { return nil }
                guard var candidates = oldIndicesByIdentityHash[hash], !candidates.isEmpty else { continue }
                var matchedPosition: Int?
                for position in candidates.indices {
                    guard check.isCurrent, let previous = oldChildren[candidates[position]].retainedViewIdentity,
                        let equal = previous.checkedEquals(identity, isCurrent: { check.isCurrent }), check.isCurrent
                    else { return nil }
                    if equal {
                        matchedPosition = position
                        break
                    }
                }
                guard check.isCurrent else { return nil }
                guard let matchedPosition else { continue }
                let oldIndex = candidates.remove(at: matchedPosition)
                oldIndicesByIdentityHash[hash] = candidates
                matches[newIndex] = oldChildren[oldIndex]
                isClaimed[oldIndex] = true
            }
        }

        if !oldIndicesByTag.isEmpty {
            for (newIndex, newNode) in newNodes.enumerated() {
                guard check.isCurrent else { return nil }
                guard newNode.retainedViewIdentity == nil, let tag = newNode.nodeTag,
                    var candidates = oldIndicesByTag[tag], !candidates.isEmpty
                else { continue }
                let oldIndex = candidates.removeFirst()
                oldIndicesByTag[tag] = candidates
                matches[newIndex] = oldChildren[oldIndex]
                isClaimed[oldIndex] = true
            }
        }

        var cursor = 0
        for (newIndex, newNode) in newNodes.enumerated() where matches[newIndex] == nil {
            guard check.isCurrent else { return nil }
            while cursor < oldChildren.count {
                if isClaimed[cursor] {
                    cursor += 1
                    continue
                }
                guard let matchesPosition = checkedNodesMatch(oldChildren[cursor], newNode, check: check),
                    check.isCurrent
                else { return nil }
                if matchesPosition {
                    matches[newIndex] = oldChildren[cursor]
                    isClaimed[cursor] = true
                    cursor += 1
                }
                break
            }
        }
        return check.isCurrent ? matches : nil
    }

    private static func checkedIdentityHash(
        _ identity: RetainedViewIdentity, check: MatchingChildrenAdmission
    ) -> Int? {
        var hasher = Hasher()
        guard identity.checkedHash(into: &hasher, isCurrent: { check.isCurrent }) else { return nil }
        return hasher.finalize()
    }

    private static func checkedNodesMatch(
        _ previous: ViewNode, _ incoming: ViewNode, check: MatchingChildrenAdmission
    ) -> Bool? {
        guard check.isCurrent else { return nil }
        let previousIdentity = previous.retainedViewIdentity
        let incomingIdentity = incoming.retainedViewIdentity
        if previousIdentity != nil || incomingIdentity != nil {
            guard let previousIdentity, let incomingIdentity else { return false }
            return previousIdentity.checkedEquals(incomingIdentity, isCurrent: { check.isCurrent })
        }
        return nodesMatch(previous, incoming)
    }

    private static func revokeDepartingTextInputOwnership(
        source: ViewNode, target: ViewNode, plan: PreparedChildrenPlan? = nil,
        admission: RetainedLazyListAdoptionAdmission? = nil,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        buttonActions: RetainedButtonActionAdoption? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> Bool {
        let check = NodeReconcileAdmission(
            admission, source: source, target: target, childrenSnapshot: plan?.childrenSnapshot,
            lazyJournal: lazyJournal, buttonActions: buttonActions, uiaAuthority: uiaAuthority)
        guard check.isCurrent, plan?.isCurrent != false else { return false }
        guard target.canAdoptStagedLazyListAdapter(from: source) else { return false }
        if source === target, admission != nil || check.uiaAuthority != nil { return true }
        target.listNavigationOwner?.prepareForAdoption(of: source.listNavigationOwner)
        guard check.isCurrent else { return false }
        target.revokeFileDialogPresentation(ifAbsentFrom: source)
        guard check.isCurrent else { return false }
        if let controller = source.textInputController {
            controller.prepareForReconciliation(from: target.textInputController, onto: target)
        } else {
            target.textInputController?.revokeOwnership(from: target)
        }
        guard check.isCurrent else { return false }
        return revokeDepartingTextInputOwnership(
            oldChildren: plan?.oldChildren ?? target.children,
            newNodes: plan?.entries.map(\.source) ?? target.childrenForLazyListReconciliation(from: source),
            plan: plan, admission: admission, parent: target, lazyJournal: lazyJournal,
            buttonActions: buttonActions, uiaAuthority: check.uiaAuthority)
    }

    private static func revokeDepartingTextInputOwnership(
        oldChildren: [ViewNode], newNodes: [ViewNode], plan: PreparedChildrenPlan? = nil,
        admission: RetainedLazyListAdoptionAdmission? = nil,
        parent: ViewNode? = nil, lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        buttonActions: RetainedButtonActionAdoption? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> Bool {
        guard buttonActions?.isCurrent != false, admission?.isCurrent != false, uiaAuthority?.isCurrent != false,
            lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false,
            plan?.isCurrent != false, plan?.stillOwnsOldChildren != false
        else {
            return false
        }
        guard
            let matches = plan?.entries.map(\.retained)
                ?? matchingChildren(
                    oldChildren: oldChildren, newNodes: newNodes, admission: admission, parent: parent,
                    lazyJournal: lazyJournal, buttonActions: buttonActions, uiaAuthority: uiaAuthority)
        else { return false }
        guard buttonActions?.isCurrent != false, admission?.isCurrent != false, uiaAuthority?.isCurrent != false,
            lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false,
            plan?.isCurrent != false, plan?.stillOwnsOldChildren != false
        else {
            return false
        }
        let survivors = Set(matches.compactMap { $0 }.map(ObjectIdentifier.init))
        let departing = oldChildren.filter { !survivors.contains(ObjectIdentifier($0)) }
        guard buttonActions?.prepareDepartures(in: departing) != false else { return false }
        for oldNode in oldChildren where !survivors.contains(ObjectIdentifier(oldNode)) {
            guard buttonActions?.isCurrent != false, admission?.isCurrent != false, uiaAuthority?.isCurrent != false,
                lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false,
                plan?.isCurrent != false, plan?.stillOwnsOldChildren != false
            else {
                return false
            }
            // Button admission is suspended by the native operation batch.
            // Permanent retirement belongs to actual departure, not matching.
            oldNode.revokeTextInputOwnership(revokesButtonActions: false)
            guard buttonActions?.isCurrent != false, admission?.isCurrent != false, uiaAuthority?.isCurrent != false,
                lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false,
                plan?.isCurrent != false, plan?.stillOwnsOldChildren != false
            else {
                return false
            }
        }
        for (index, newNode) in newNodes.enumerated() {
            guard buttonActions?.isCurrent != false, admission?.isCurrent != false, uiaAuthority?.isCurrent != false,
                lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false,
                plan?.isCurrent != false, plan?.stillOwnsOldChildren != false,
                plan?.entries[index].isCurrent != false
            else { return false }
            if let oldNode = matches[index] {
                guard
                    revokeDepartingTextInputOwnership(
                        source: newNode, target: oldNode, plan: plan?.entries[index].descendants, admission: admission,
                        lazyJournal: lazyJournal, buttonActions: buttonActions, uiaAuthority: uiaAuthority)
                else { return false }
            }
            guard buttonActions?.isCurrent != false, admission?.isCurrent != false, uiaAuthority?.isCurrent != false,
                lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false,
                plan?.isCurrent != false, plan?.stillOwnsOldChildren != false
            else {
                return false
            }
        }
        return buttonActions?.isCurrent != false && admission?.isCurrent != false && uiaAuthority?.isCurrent != false
            && (lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false)
            && plan?.isCurrent != false && plan?.stillOwnsOldChildren != false
    }

    private static func reconcilePreparedChildren(
        of parent: ViewNode, oldChildren: [ViewNode], newNodes: [ViewNode], plan: PreparedChildrenPlan? = nil,
        admission: RetainedLazyListAdoptionAdmission? = nil, preservesChildren: Bool = false,
        sourceParent: ViewNode? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        completionSources: RetainedReconciliationSourceNodes?,
        buttonActions: RetainedButtonActionAdoption? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> Bool {
        let check = NodeReconcileAdmission(
            admission, target: parent, childrenSnapshot: plan?.childrenSnapshot,
            lazyJournal: lazyJournal, taskAdoption: taskAdoption, buttonActions: buttonActions,
            uiaAuthority: uiaAuthority)
        guard check.isCurrent, plan?.isCurrent != false, plan?.stillOwnsOldChildren != false else { return false }
        guard
            let matches = plan?.entries.map(\.retained)
                ?? matchingChildren(
                    oldChildren: oldChildren, newNodes: newNodes, admission: admission, parent: parent,
                    lazyJournal: lazyJournal, buttonActions: buttonActions, uiaAuthority: check.uiaAuthority)
        else { return false }
        guard check.isCurrent else { return false }

        var nextChildren: [ViewNode] = []
        nextChildren.reserveCapacity(newNodes.count)
        for (newIndex, newNode) in newNodes.enumerated() {
            guard check.isCurrent, plan?.entries[newIndex].isCurrent != false,
                plan?.stillOwnsOldChildren != false
            else { return false }
            guard let oldNode = matches[newIndex] else {
                guard
                    prepareInsertedSubtree(
                        newNode, admission: admission, taskAdoption: taskAdoption,
                        inheritedChildren: plan?.childrenSnapshot, lazyJournal: lazyJournal,
                        buttonActions: buttonActions, uiaAuthority: check.uiaAuthority),
                    check.isCurrent,
                    plan?.entries[newIndex].isCurrent != false
                else { return false }
                nextChildren.append(newNode)
                continue
            }
            if oldNode === newNode, admission != nil || preservesChildren || check.uiaAuthority != nil {
                lazyJournal?.recordUnchangedNode(oldNode)
                // A container whose adapter survives adopts its configuration,
                // not its fresh candidate's empty materialized-child array.
                if admission != nil || check.uiaAuthority != nil {
                    let completion = RetainedLazyListAdoptionCompletion(of: oldNode)
                    guard check.recordUIACompletion(completion) else { return false }
                    if let admission {
                        guard let completion, admission.recordCompletion(completion) else { return false }
                    }
                }
                nextChildren.append(oldNode)
                continue
            }
            let childPlan = plan?.entries[newIndex].descendants
            let nodeCheck = NodeReconcileAdmission(
                admission, source: newNode, target: oldNode, childrenSnapshot: childPlan?.childrenSnapshot,
                lazyJournal: lazyJournal, taskAdoption: taskAdoption, buttonActions: buttonActions,
                uiaAuthority: check.uiaAuthority)
            guard admission?.permitsMutation(of: oldNode) != false,
                childPlan?.isCurrent != false, childPlan?.stillOwnsOldChildren != false
            else { return false }
            let preservesChildren = preservesLazyListChildren(source: newNode, target: oldNode)
            let previousChildren = childPlan?.oldChildren ?? oldNode.children
            let proposedChildren =
                childPlan?.entries.map(\.source) ?? oldNode.childrenForLazyListReconciliation(from: newNode)
            guard admission?.beginInsertionNode(source: newNode, target: oldNode, isFresh: false) != false else {
                return false
            }
            taskAdoption?.associate(source: newNode, target: oldNode)
            guard check.isCurrent, nodeCheck.isCurrent, childPlan?.isCurrent != false,
                childPlan?.stillOwnsOldChildren != false
            else { return false }
            guard nodeCheck.prepareTaskTransport(from: newNode, to: oldNode) else { return false }
            let previous = admission?.isLogicalInsertion(source: newNode) == true ? nil : oldNode
            let completed = withReconcileAnimationTransaction(source: newNode, previous: previous, check: nodeCheck) {
                guard childPlan?.isCurrent != false, childPlan?.stillOwnsOldChildren != false else { return false }
                guard
                    admission?.prepareInsertionNode(
                        source: newNode, target: oldNode, transaction: RetainedBuildTransaction()) != false
                else { return false }
                guard updateNodeProperties(target: oldNode, source: newNode, check: nodeCheck), nodeCheck.isCurrent
                else {
                    return false
                }
                return reconcilePreparedChildren(
                    of: oldNode, oldChildren: previousChildren, newNodes: proposedChildren,
                    plan: childPlan, admission: admission,
                    preservesChildren: preservesChildren, sourceParent: newNode,
                    taskAdoption: taskAdoption, lazyJournal: lazyJournal, completionSources: completionSources,
                    buttonActions: buttonActions, uiaAuthority: check.uiaAuthority)
            }
            guard completed, check.isCurrent, nodeCheck.isCurrent else { return false }
            nodeCheck.recordCompletedNode(from: newNode, to: oldNode)
            guard check.isCurrent, nodeCheck.isCurrent else { return false }
            nextChildren.append(oldNode)
        }

        guard check.isCurrent, plan?.isCurrent != false, plan?.stillOwnsOldChildren != false else { return false }
        guard plan?.childrenSnapshot?.beginTransfers() != false else { return false }
        let result = parent.setChildren(
            nextChildren, admission: admission, lazyJournal: lazyJournal, taskAdoption: taskAdoption,
            sourceParent: sourceParent, completionSources: completionSources,
            buttonActions: buttonActions, uiaAuthority: check.uiaAuthority)
        guard result.completed, check.isCurrent else { return false }
        guard check.recordUIACompletion(result.completion) else { return false }
        if let admission {
            guard let completion = result.completion, admission.recordCompletion(completion) else { return false }
        }
        return check.isCurrent
    }

    /// Typed identities must agree on both nodes. Otherwise the legacy path
    /// compares tags when both have one, then falls back to layout category.
    private static func nodesMatch(_ a: ViewNode, _ b: ViewNode) -> Bool {
        if a.retainedViewIdentity != nil || b.retainedViewIdentity != nil {
            return a.retainedViewIdentity == b.retainedViewIdentity
        }

        // If both nodes carry an explicit tag, match on tag only.
        if let tagA = a.nodeTag, let tagB = b.nodeTag {
            return tagA == tagB
        }

        // Fall back to structural similarity.
        return layoutModeTag(a.layoutMode) == layoutModeTag(b.layoutMode)
    }

    /// The structural category of a layout mode: what has to agree for two
    /// nodes to be the same node, ignoring the parameters inside the mode.
    ///
    /// An enum rather than the `String` this used to return. The value is
    /// computed twice per reconciled node — once to match, once to decide
    /// whether the mode has to be re-assigned — and a reconcile touches every
    /// node in the window, so the two string materializations and the string
    /// comparison between them were paid several hundred times per rebuild
    /// for a five-way distinction that fits in a byte.
    private enum LayoutModeCategory: UInt8 {
        case absolute
        case verticalStack
        case horizontalStack
        case verticalLazyStack
        case horizontalLazyStack
        case flex
        case grid
        case gridRow
    }

    /// Produce a cheap comparable key for a layout mode.
    private static func layoutModeTag(_ mode: ViewLayoutMode) -> LayoutModeCategory {
        switch mode {
        case .absolute:
            return .absolute
        case .stack(let layout):
            switch layout.axis {
            case .vertical:
                return .verticalStack
            case .horizontal:
                return .horizontalStack
            }
        case .lazyStack(let layout):
            switch layout.axis {
            case .vertical:
                return .verticalLazyStack
            case .horizontal:
                return .horizontalLazyStack
            }
        case .flex:
            return .flex
        case .grid:
            return .grid
        case .gridRow:
            return .gridRow
        }
    }

    private static func layoutConfigurationChanged(_ target: ViewLayoutMode, _ source: ViewLayoutMode) -> Bool {
        switch (target, source) {
        case (.stack(let old), .stack(let new)),
            (.lazyStack(let old), .lazyStack(let new)):
            return old != new
        case (.grid(let old), .grid(let new)):
            return old != new
        case (.gridRow(let old), .gridRow(let new)):
            return old != new
        default:
            return false
        }
    }

    /// Reconcile a model value without replacing an animation's presentation
    /// value. An unchanged destination keeps its original clock; a different
    /// destination starts from the value that is currently on screen.
    private static func reconciledAnimatedValue(
        _ property: AnimatableProperty, current: Double, proposed: Double,
        target: ViewNode, source: ViewNode, transaction: AnimationTransaction?,
        startTime: inout Double?, animationsDisabled: Bool, check: NodeReconcileAdmission
    ) -> Double {
        guard check.isCurrent else { return current }
        let existing = target.animationStates[property]
        if animationsDisabled {
            if existing != nil { target.animationStates.removeValue(forKey: property) }
            return proposed
        }
        if existing != nil, let surface = target.interactionSurface,
            (property == .opacity && surface.pressedContentOpacity != 1)
                || ((property == .transformScaleX || property == .transformScaleY) && surface.pressedScale != 1)
        {
            // A build describes idle control chrome. Pointer-owned animation
            // destinations are restored by the runtime after reconciliation.
            return current
        }
        if let existing, existing.startValue != existing.endValue, existing.endValue == proposed {
            return current
        }
        guard current != proposed else {
            if existing != nil { target.animationStates.removeValue(forKey: property) }
            return proposed
        }
        let animation =
            source.animationStates[property].map {
                AnimationTransaction(duration: $0.duration, easing: $0.easing)
            } ?? transaction
        guard let animation, animation.duration > 0 else {
            if existing != nil { target.animationStates.removeValue(forKey: property) }
            return proposed
        }
        let timestamp: Double
        if let startTime {
            timestamp = startTime
        } else {
            guard let sampled = target.reconciliationAnimationTime(admission: check.admission) else {
                check.admission?.revoke()
                return current
            }
            guard check.isCurrent else { return current }
            timestamp = sampled
        }
        guard check.isCurrent else { return current }
        startTime = timestamp
        target.animationStates[property] = AnimationState(
            startValue: current, endValue: proposed, startTime: timestamp,
            duration: animation.duration, easing: animation.easing)
        return current
    }

    /// Keep both values alive until the comparison returns. A user Equatable
    /// implementation may replace either node's identity while comparing it;
    /// the caller must check after this helper's temporary values are released.
    private static func nodePropertyValuesDiffer<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<ViewNode, Value>, source: ViewNode, target: ViewNode
    ) -> Bool {
        let previous = target[keyPath: keyPath]
        let incoming = source[keyPath: keyPath]
        return previous != incoming
    }

    /// A composed retained identity can contain several authored keys. Stop
    /// after the first hash/equality boundary that changes adoption authority,
    /// and release both temporary identity values before the caller rechecks.
    @inline(never)
    private static func retainedViewIdentitiesDiffer(
        source: ViewNode, target: ViewNode, check: NodeReconcileAdmission
    ) -> Bool? {
        guard check.isCurrent else { return nil }
        let previous = target.retainedViewIdentity
        let incoming = source.retainedViewIdentity
        switch (previous, incoming) {
        case (nil, nil):
            return false
        case (.some(let previous), .some(let incoming)):
            guard let matches = previous.checkedEquals(incoming, isCurrent: { check.isCurrent }) else { return nil }
            return !matches
        default:
            return true
        }
    }

    @inline(__always)
    private static func copyNodeProperty<Value>(
        _ keyPath: ReferenceWritableKeyPath<ViewNode, Value>, source: ViewNode, target: ViewNode,
        check: NodeReconcileAdmission
    ) -> Bool {
        if check.admission == nil, check.lazyJournal == nil, check.buttonActions == nil, check.uiaAuthority == nil {
            target[keyPath: keyPath] = source[keyPath: keyPath]
            return true
        }
        guard check.isCurrent,
            check.preparePropertyCopy(from: source, to: target, keyPath: keyPath),
            check.markMutationStarted()
        else { return false }
        replacePinnedNodeProperty(
            keyPath, on: target, with: source[keyPath: keyPath], source: source, check: check)
        return check.isCurrent
    }

    @inline(__always)
    private static func assignNodeProperty<Value>(
        _ keyPath: ReferenceWritableKeyPath<ViewNode, Value>, on target: ViewNode, value: Value,
        check: NodeReconcileAdmission
    ) -> Bool {
        if check.admission == nil, check.lazyJournal == nil, check.buttonActions == nil, check.uiaAuthority == nil {
            target[keyPath: keyPath] = value
            return true
        }
        guard check.isCurrent else { return false }
        if let source = check.source {
            guard check.preparePropertyCopy(from: source, to: target, keyPath: keyPath) else {
                return false
            }
        }
        guard check.markMutationStarted() else { return false }
        replacePinnedNodeProperty(keyPath, on: target, with: value, source: check.source, check: check)
        return check.isCurrent
    }

    /// Pin the outgoing field, not merely its node or sparse-storage object.
    /// Publish the replacement before destruction can reenter the same slot.
    /// The guard belongs in the caller, after this scope has released previous.
    private static func replacePinnedNodeProperty<Value>(
        _ keyPath: ReferenceWritableKeyPath<ViewNode, Value>, on target: ViewNode, with incoming: Value,
        source: ViewNode?, check: NodeReconcileAdmission
    ) {
        let previous = target[keyPath: keyPath]
        target[keyPath: keyPath] = incoming
        if keyPath == \ViewNode.retainedViewIdentity { check.buttonActions?.recordIdentityWrite(on: target) }
        if let source, let journal = check.lazyJournal {
            let accepted = journal.recordAcceptedProperty(from: source, to: target, keyPath: keyPath)
            check.associate(accepted, from: source, to: target)
        }
        withExtendedLifetime(previous) {}
    }

    private static func copyGeometryReaderPair(
        source: ViewNode, target: ViewNode, check: NodeReconcileAdmission
    ) {
        let previous = target.geometryReaderBuild
        let incoming = source.geometryReaderBuild
        let size = source.geometryReaderBuiltSize
        target.geometryReaderBuild = incoming
        target.geometryReaderBuiltSize = size
        if let journal = check.lazyJournal {
            check.associate(
                journal.recordAcceptedProperty(from: source, to: target, keyPath: \ViewNode.geometryReaderBuild),
                from: source, to: target)
            check.associate(
                journal.recordAcceptedProperty(from: source, to: target, keyPath: \ViewNode.geometryReaderBuiltSize),
                from: source, to: target)
        }
        withExtendedLifetime(previous) {}
    }

    private static func invokePlatformUpdate(on target: ViewNode) {
        let update = target.onUpdatePlatformView
        update?(target)
    }

    @inline(never)
    private static func copyButtonActionOwner(
        source: ViewNode, target: ViewNode, check: NodeReconcileAdmission
    ) -> Bool {
        guard source !== target else { return check.isCurrent }
        guard source.buttonActionOwner != nil || target.buttonActionOwner != nil else { return check.isCurrent }
        guard let buttonActions = check.buttonActions, check.isCurrent,
            check.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.buttonActionOwner),
            check.markMutationStarted()
        else { return false }
        let previous = target.buttonActionOwner
        let incoming = source.buttonActionOwner
        guard buttonActions.prepareOwnerCopy(from: source, to: target) else { return false }
        target.buttonActionOwner = incoming
        guard buttonActions.recordOwnerCopy(from: source, to: target) else { return false }
        if let journal = check.lazyJournal {
            check.associate(
                journal.recordAcceptedProperty(from: source, to: target, keyPath: \ViewNode.buttonActionOwner),
                from: source, to: target)
        }
        guard check.isCurrent, buttonActions.consumeSourceOwner(on: source, copiedTo: target) else { return false }
        previous?.releaseRetiredPayload()
        withExtendedLifetime(previous) {}
        return check.isCurrent
    }

    /// Copy visual / layout properties from `source` onto `target`, keeping
    /// `target`'s identity (parent, runtime, callbacks) intact.
    private static func updateNodeProperties(
        target: ViewNode, source: ViewNode, check: NodeReconcileAdmission
    ) -> Bool {
        guard check.isCurrent else { return false }
        source.retainedLazyListAdapter?.stageInsertionBuildTransaction(RetainedBuildTransaction())
        guard check.isCurrent, copyButtonActionOwner(source: source, target: target, check: check), check.isCurrent
        else {
            return false
        }
        // An incomplete checked update must not clear revocations installed by
        // a newer preparation. Ordinary reconciliation retains its old scope.
        defer {
            if check.admission == nil, check.lazyJournal == nil, check.uiaAuthority == nil {
                target.finishFileDialogConfigurationAdoption()
            }
        }
        guard
            target.reconcileLazyListAdapter(
                from: source, admission: check.admission, lazyJournal: check.lazyJournal,
                taskAdoption: check.taskAdoption, uiaAuthority: check.uiaAuthority),
            check.isCurrent
        else {
            return false
        }
        let listNavigationOwner = target.adoptListNavigationOwner(from: source)
        defer { listNavigationOwner?.finishAdoption() }
        guard check.isCurrent else { return false }
        let oldFrame = target.frame
        let oldOpacity = target.opacity
        let oldBackgroundColor = target.backgroundColor
        let oldBackgroundGradient = target.backgroundGradient
        // One change must not start width, height or transforms on slightly
        // different clocks. Sample lazily so static nodes incur no clock read.
        var animationStartTime: Double? = nil
        // Assignments below are guarded on *emptiness* rather than equality
        // wherever the property is heap-backed, carries a `didSet`, or both.
        //
        // This runs once per node in the window on every state change, and
        // the overwhelming majority of nodes carry none of these: a plain
        // `VStack` row has no animation states, no canvas draw, no swipe
        // actions and no accessibility actions. Assigning an empty
        // collection over an empty collection is not free — it retains and
        // releases the source storage, and where the property observes
        // itself it also runs `invalidateRuntime`, which walks the node's
        // ancestors to the root. Measured 2026-08 on the demo's screen
        // switch: the unconditional block cost about four times as much per
        // property as the guarded compares around it.
        if !target.reconcileAnimationModifiers.isEmpty || !source.reconcileAnimationModifiers.isEmpty {
            guard copyNodeProperty(\.reconcileAnimationModifiers, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.implicitReconcileAnimation != source.implicitReconcileAnimation {
            guard copyNodeProperty(\.implicitReconcileAnimation, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.interactionSurface != nil || source.interactionSurface != nil {
            guard copyNodeProperty(\.interactionSurface, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        guard
            target.retainInsertionTransaction(
                inheritedTransaction, admission: check.admission, uiaAuthority: check.uiaAuthority), check.isCurrent
        else {
            return false
        }
        // A node may animate its own changes with no ambient `withAnimation`
        // — `NSSwitch` does, and a rebuilt control's state change carries no
        // transaction at all. The explicit one still wins when both are set.
        let inherited = inheritedTransaction
        let animationsDisabled = inherited.map { $0.disablesAnimations || $0.animation == nil } ?? false
        let reconcileTransaction: AnimationTransaction? =
            animationsDisabled
            ? nil
            : inherited?.animation.map { AnimationTransaction(duration: $0.duration, easing: $0.easing) }
                ?? target.implicitReconcileAnimation

        if oldFrame != source.frame || !target.animationStates.isEmpty {
            let nextFrame = Rect(
                x: reconciledAnimatedValue(
                    .frameOriginX, current: oldFrame.origin.x, proposed: source.frame.origin.x,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled, check: check),
                y: reconciledAnimatedValue(
                    .frameOriginY, current: oldFrame.origin.y, proposed: source.frame.origin.y,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled, check: check),
                width: reconciledAnimatedValue(
                    .frameWidth, current: oldFrame.size.width, proposed: source.frame.size.width,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled, check: check),
                height: reconciledAnimatedValue(
                    .frameHeight, current: oldFrame.size.height, proposed: source.frame.size.height,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled, check: check)
            )
            if target.frame != nextFrame {
                guard assignNodeProperty(\.frame, on: target, value: nextFrame, check: check), check.isCurrent else {
                    return false
                }
            }
        }
        guard check.isCurrent else { return false }
        if target.backgroundColor != source.backgroundColor {
            guard copyNodeProperty(\.backgroundColor, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.backgroundGradient != source.backgroundGradient {
            guard copyNodeProperty(\.backgroundGradient, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        guard
            target.applyReconcileFillTween(
                fromBackgroundColor: oldBackgroundColor,
                fromBackgroundGradient: oldBackgroundGradient,
                animation: reconcileTransaction,
                animationsDisabled: animationsDisabled,
                admission: check.admission,
                nativeCheck: check.lazyJournal?.isOrdinaryAdoption == false || check.uiaAuthority != nil ? check : nil
            ), check.isCurrent
        else { return false }
        if target.bitmapSurface != source.bitmapSurface {
            guard copyNodeProperty(\.bitmapSurface, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.canvasDraw != nil || source.canvasDraw != nil {
            guard copyNodeProperty(\.canvasDraw, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.text != source.text {
            guard copyNodeProperty(\.text, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.textStyle != source.textStyle {
            guard copyNodeProperty(\.textStyle, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.borderColor != source.borderColor {
            guard copyNodeProperty(\.borderColor, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.borderGradient != source.borderGradient {
            guard copyNodeProperty(\.borderGradient, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.borderWidth != source.borderWidth {
            guard copyNodeProperty(\.borderWidth, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.borderStrokeStyle != source.borderStrokeStyle {
            guard copyNodeProperty(\.borderStrokeStyle, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.outlineColor != source.outlineColor {
            guard copyNodeProperty(\.outlineColor, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.outlineWidth != source.outlineWidth {
            guard copyNodeProperty(\.outlineWidth, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.shadowColor != source.shadowColor {
            guard copyNodeProperty(\.shadowColor, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.shadowOffset != source.shadowOffset {
            guard copyNodeProperty(\.shadowOffset, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.shadowSpread != source.shadowSpread {
            guard copyNodeProperty(\.shadowSpread, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.cornerRadius != source.cornerRadius {
            guard copyNodeProperty(\.cornerRadius, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.cornerRadii != source.cornerRadii {
            guard copyNodeProperty(\.cornerRadii, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.clipsToBounds != source.clipsToBounds {
            guard copyNodeProperty(\.clipsToBounds, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.clipFillStyle != source.clipFillStyle {
            guard copyNodeProperty(\.clipFillStyle, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.backgroundPath != source.backgroundPath {
            guard copyNodeProperty(\.backgroundPath, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if let oldSize = target.preferredSize, let proposedSize = source.preferredSize {
            // Fixed SwiftUI frame modifiers declare preferred dimensions on
            // their wrapper. Animate those dimensions so layout and sibling
            // placement see the intermediate size, not only paint geometry.
            let nextSize = Size(
                width: reconciledAnimatedValue(
                    .preferredWidth, current: oldSize.width, proposed: proposedSize.width,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled || oldSize.width <= 0 || proposedSize.width <= 0
                        || !oldSize.width.isFinite || !proposedSize.width.isFinite, check: check),
                height: reconciledAnimatedValue(
                    .preferredHeight, current: oldSize.height, proposed: proposedSize.height,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled || oldSize.height <= 0 || proposedSize.height <= 0
                        || !oldSize.height.isFinite || !proposedSize.height.isFinite, check: check)
            )
            if target.preferredSize != nextSize {
                guard assignNodeProperty(\.preferredSize, on: target, value: nextSize, check: check), check.isCurrent
                else { return false }
            }
        } else {
            if target.animationStates[.preferredWidth] != nil { target.animationStates[.preferredWidth] = nil }
            if target.animationStates[.preferredHeight] != nil { target.animationStates[.preferredHeight] = nil }
            if target.preferredSize != source.preferredSize {
                guard copyNodeProperty(\.preferredSize, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
        }
        guard check.isCurrent else { return false }
        if target.layoutConstraints != source.layoutConstraints {
            guard copyNodeProperty(\.layoutConstraints, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.fixedSizeAxes != source.fixedSizeAxes {
            guard copyNodeProperty(\.fixedSizeAxes, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.layoutFillAxes != source.layoutFillAxes {
            guard copyNodeProperty(\.layoutFillAxes, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.fixedPreferredSizeAxes != source.fixedPreferredSizeAxes {
            guard copyNodeProperty(\.fixedPreferredSizeAxes, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.explicitFrameFillAxes != source.explicitFrameFillAxes {
            guard copyNodeProperty(\.explicitFrameFillAxes, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.forwardsStackMainAxisProposal != source.forwardsStackMainAxisProposal {
            guard copyNodeProperty(\.forwardsStackMainAxisProposal, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.forwardsChildSize != source.forwardsChildSize {
            guard copyNodeProperty(\.forwardsChildSize, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.aspectFitLayout != source.aspectFitLayout {
            guard copyNodeProperty(\.aspectFitLayout, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.layoutPriority != source.layoutPriority {
            guard copyNodeProperty(\.layoutPriority, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.spatialCompressionResistance != source.spatialCompressionResistance {
            guard copyNodeProperty(\.spatialCompressionResistance, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.spatialExpansionResistance != source.spatialExpansionResistance {
            guard copyNodeProperty(\.spatialExpansionResistance, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.alignmentGuides != source.alignmentGuides {
            guard copyNodeProperty(\.alignmentGuides, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.gridCellAnchor != source.gridCellAnchor {
            guard copyNodeProperty(\.gridCellAnchor, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.gridCellUnsizedAxes != source.gridCellUnsizedAxes {
            guard copyNodeProperty(\.gridCellUnsizedAxes, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.gridCellColumns != source.gridCellColumns {
            guard copyNodeProperty(\.gridCellColumns, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.gridColumnAlignment != source.gridColumnAlignment {
            guard copyNodeProperty(\.gridColumnAlignment, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.blurRadius != source.blurRadius {
            guard copyNodeProperty(\.blurRadius, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.blurOpaque != source.blurOpaque {
            guard copyNodeProperty(\.blurOpaque, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.contentBlurRadius != source.contentBlurRadius {
            guard copyNodeProperty(\.contentBlurRadius, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.contentBlurOpaque != source.contentBlurOpaque {
            guard copyNodeProperty(\.contentBlurOpaque, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.geometryEffect != source.geometryEffect {
            guard copyNodeProperty(\.geometryEffect, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if oldOpacity != source.opacity || target.animationStates[.opacity] != nil {
            let nextOpacity = reconciledAnimatedValue(
                .opacity, current: oldOpacity, proposed: source.opacity,
                target: target, source: source, transaction: reconcileTransaction,
                startTime: &animationStartTime,
                animationsDisabled: animationsDisabled, check: check)
            if target.opacity != nextOpacity {
                guard assignNodeProperty(\.opacity, on: target, value: nextOpacity, check: check), check.isCurrent
                else { return false }
            }
        }
        guard check.isCurrent else { return false }
        if target.blendMode != source.blendMode {
            guard copyNodeProperty(\.blendMode, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.isCompositingGroup != source.isCompositingGroup {
            guard copyNodeProperty(\.isCompositingGroup, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.drawingGroup != source.drawingGroup {
            guard copyNodeProperty(\.drawingGroup, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.colorEffects != source.colorEffects {
            guard copyNodeProperty(\.colorEffects, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.visualEffects != source.visualEffects {
            guard copyNodeProperty(\.visualEffects, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.viewMask != source.viewMask {
            guard copyNodeProperty(\.viewMask, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.listRowSeparator != source.listRowSeparator {
            guard copyNodeProperty(\.listRowSeparator, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.listRowSeparatorTint != source.listRowSeparatorTint {
            guard copyNodeProperty(\.listRowSeparatorTint, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.listSectionSeparator != source.listSectionSeparator {
            guard copyNodeProperty(\.listSectionSeparator, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.listSectionSeparatorTint != source.listSectionSeparatorTint {
            guard copyNodeProperty(\.listSectionSeparatorTint, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.alternatingRowBackgrounds != source.alternatingRowBackgrounds {
            guard copyNodeProperty(\.alternatingRowBackgrounds, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.listRowHoverStyle != source.listRowHoverStyle {
            guard copyNodeProperty(\.listRowHoverStyle, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.listItemTint != source.listItemTint {
            guard copyNodeProperty(\.listItemTint, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.listRowPlatterColor != source.listRowPlatterColor {
            guard copyNodeProperty(\.listRowPlatterColor, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.navigationSplitViewColumnWidth != source.navigationSplitViewColumnWidth {
            guard copyNodeProperty(\.navigationSplitViewColumnWidth, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.preferredCompactColumn != source.preferredCompactColumn {
            guard copyNodeProperty(\.preferredCompactColumn, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.selectionDisabled != source.selectionDisabled {
            guard copyNodeProperty(\.selectionDisabled, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.selectionDisabledOverride != source.selectionDisabledOverride {
            guard copyNodeProperty(\.selectionDisabledOverride, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.deleteDisabled != source.deleteDisabled {
            guard copyNodeProperty(\.deleteDisabled, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.deleteDisabledOverride != source.deleteDisabledOverride {
            guard copyNodeProperty(\.deleteDisabledOverride, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.moveDisabled != source.moveDisabled {
            guard copyNodeProperty(\.moveDisabled, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.moveDisabledOverride != source.moveDisabledOverride {
            guard copyNodeProperty(\.moveDisabledOverride, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.onDeleteAction != nil || source.onDeleteAction != nil {
            guard copyNodeProperty(\.onDeleteAction, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.onMoveAction != nil || source.onMoveAction != nil {
            guard copyNodeProperty(\.onMoveAction, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.editActions != source.editActions {
            guard copyNodeProperty(\.editActions, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.swipeActionsLeading != nil || source.swipeActionsLeading != nil {
            guard copyNodeProperty(\.swipeActionsLeading, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.swipeActionsTrailing != nil || source.swipeActionsTrailing != nil {
            guard copyNodeProperty(\.swipeActionsTrailing, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.swipeActionsAllowsFullSwipe != source.swipeActionsAllowsFullSwipe {
            guard copyNodeProperty(\.swipeActionsAllowsFullSwipe, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if !(target.commandHandlers.isEmpty && source.commandHandlers.isEmpty) {
            guard copyNodeProperty(\.commandHandlers, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.fileExporterConfiguration != nil || source.fileExporterConfiguration != nil {
            guard copyNodeProperty(\.fileExporterConfiguration, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.fileImporterConfiguration != nil || source.fileImporterConfiguration != nil {
            guard copyNodeProperty(\.fileImporterConfiguration, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.fileImporterMultiConfiguration != nil || source.fileImporterMultiConfiguration != nil {
            guard copyNodeProperty(\.fileImporterMultiConfiguration, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.fileMoverConfiguration != nil || source.fileMoverConfiguration != nil {
            guard copyNodeProperty(\.fileMoverConfiguration, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.inspectorColumnWidth != source.inspectorColumnWidth {
            guard copyNodeProperty(\.inspectorColumnWidth, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.inspectorColumnWidthFraction != source.inspectorColumnWidthFraction {
            guard copyNodeProperty(\.inspectorColumnWidthFraction, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.inspectorColumnWidthMin != source.inspectorColumnWidthMin {
            guard copyNodeProperty(\.inspectorColumnWidthMin, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.inspectorPresentationStyle != source.inspectorPresentationStyle {
            guard copyNodeProperty(\.inspectorPresentationStyle, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.fileDialogCustomizationID != source.fileDialogCustomizationID {
            guard copyNodeProperty(\.fileDialogCustomizationID, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.fileDialogConfirmationLabel != source.fileDialogConfirmationLabel {
            guard copyNodeProperty(\.fileDialogConfirmationLabel, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.fileDialogDefaultDirectory != source.fileDialogDefaultDirectory {
            guard copyNodeProperty(\.fileDialogDefaultDirectory, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.fileDialogMessage != source.fileDialogMessage {
            guard copyNodeProperty(\.fileDialogMessage, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.dynamicContentIndex != source.dynamicContentIndex {
            guard copyNodeProperty(\.dynamicContentIndex, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.dynamicInsertContentTypes != source.dynamicInsertContentTypes {
            guard copyNodeProperty(\.dynamicInsertContentTypes, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.dynamicDropPayloadType != source.dynamicDropPayloadType {
            guard copyNodeProperty(\.dynamicDropPayloadType, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.dropAcceptedContentTypes != source.dropAcceptedContentTypes {
            guard copyNodeProperty(\.dropAcceptedContentTypes, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.dropPayloadType != source.dropPayloadType {
            guard copyNodeProperty(\.dropPayloadType, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.isDropDestinationEnabled != source.isDropDestinationEnabled {
            guard copyNodeProperty(\.isDropDestinationEnabled, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.hasDropConfiguration != source.hasDropConfiguration {
            guard copyNodeProperty(\.hasDropConfiguration, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.dragDropPreviewsFormation != source.dragDropPreviewsFormation {
            guard copyNodeProperty(\.dragDropPreviewsFormation, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.springLoadingBehavior != source.springLoadingBehavior {
            guard copyNodeProperty(\.springLoadingBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.dragPayloadType != source.dragPayloadType {
            guard copyNodeProperty(\.dragPayloadType, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.dragItemProviderTypeIdentifiers != source.dragItemProviderTypeIdentifiers {
            guard copyNodeProperty(\.dragItemProviderTypeIdentifiers, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        let dragContainerItemIDChanged = nodePropertyValuesDiffer(\.dragContainerItemID, source: source, target: target)
        guard check.isCurrent else { return false }
        if dragContainerItemIDChanged {
            guard copyNodeProperty(\.dragContainerItemID, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.dragContainerNamespaceID != source.dragContainerNamespaceID {
            guard copyNodeProperty(\.dragContainerNamespaceID, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.hasDragPreview != source.hasDragPreview {
            guard copyNodeProperty(\.hasDragPreview, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.horizontalScrollBounceBehavior != source.horizontalScrollBounceBehavior {
            guard copyNodeProperty(\.horizontalScrollBounceBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.verticalScrollBounceBehavior != source.verticalScrollBounceBehavior {
            guard copyNodeProperty(\.verticalScrollBounceBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollTargetBehavior != source.scrollTargetBehavior {
            guard copyNodeProperty(\.scrollTargetBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isScrollTargetLayout != source.isScrollTargetLayout {
            guard copyNodeProperty(\.isScrollTargetLayout, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollInputBehaviors != source.scrollInputBehaviors {
            guard copyNodeProperty(\.scrollInputBehaviors, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollIndicatorsFlashOnAppear != source.scrollIndicatorsFlashOnAppear {
            guard copyNodeProperty(\.scrollIndicatorsFlashOnAppear, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollIndicatorsFlashTrigger != source.scrollIndicatorsFlashTrigger {
            guard copyNodeProperty(\.scrollIndicatorsFlashTrigger, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollTransition != source.scrollTransition {
            guard copyNodeProperty(\.scrollTransition, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.scrollPosition != source.scrollPosition {
            guard copyNodeProperty(\.scrollPosition, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.scrollObservations != source.scrollObservations {
            guard copyNodeProperty(\.scrollObservations, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        guard
            target.reconcileScrollObservers(
                from: source, admission: check.admission, lazyJournal: check.lazyJournal,
                taskAdoption: check.taskAdoption, uiaAuthority: check.uiaAuthority),
            check.isCurrent
        else {
            return false
        }
        if target.scrollReaderID != source.scrollReaderID {
            guard copyNodeProperty(\.scrollReaderID, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.scrollProxyRequests != source.scrollProxyRequests {
            guard copyNodeProperty(\.scrollProxyRequests, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.zIndex != source.zIndex {
            guard copyNodeProperty(\.zIndex, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.position != source.position {
            guard copyNodeProperty(\.position, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.transform != source.transform || !target.animationStates.isEmpty {
            let oldTransform = target.transform
            let nextTransform = Transform2D(
                translationX: reconciledAnimatedValue(
                    .transformTranslationX, current: oldTransform.translationX, proposed: source.transform.translationX,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled, check: check),
                translationY: reconciledAnimatedValue(
                    .transformTranslationY, current: oldTransform.translationY, proposed: source.transform.translationY,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled, check: check),
                scaleX: reconciledAnimatedValue(
                    .transformScaleX, current: oldTransform.scaleX, proposed: source.transform.scaleX,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled, check: check),
                scaleY: reconciledAnimatedValue(
                    .transformScaleY, current: oldTransform.scaleY, proposed: source.transform.scaleY,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled, check: check),
                rotation: reconciledAnimatedValue(
                    .transformRotation, current: oldTransform.rotation, proposed: source.transform.rotation,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled, check: check),
                skewX: source.transform.skewX,
                skewY: source.transform.skewY
            )
            if target.transform != nextTransform {
                guard assignNodeProperty(\.transform, on: target, value: nextTransform, check: check), check.isCurrent
                else { return false }
            }
        }
        guard check.isCurrent else { return false }
        if target.transition != source.transition {
            guard copyNodeProperty(\.transition, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.contentTransition != source.contentTransition {
            guard copyNodeProperty(\.contentTransition, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.sensoryFeedback != source.sensoryFeedback {
            guard copyNodeProperty(\.sensoryFeedback, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.flexItem != source.flexItem {
            guard copyNodeProperty(\.flexItem, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.flexItemStyle != source.flexItemStyle {
            guard copyNodeProperty(\.flexItemStyle, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.scrollAxis != source.scrollAxis {
            guard copyNodeProperty(\.scrollAxis, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        guard
            target.reconcileScrollContainer(
                from: source, admission: check.admission,
                nativeCheck: check.lazyJournal?.isOrdinaryAdoption == false || check.uiaAuthority != nil ? check : nil),
            check.isCurrent
        else {
            return false
        }
        // Scroll offsets are runtime-driven (wheel/drag/keyboard); a freshly
        // built node always starts at zero, so only adopt a source offset that
        // was explicitly set and never let a rebuild reset a live offset.
        guard
            target.reconcileScrollOffset(
                from: source, admission: check.admission,
                nativeCheck: check.lazyJournal?.isOrdinaryAdoption == false || check.uiaAuthority != nil ? check : nil),
            check.isCurrent
        else {
            return false
        }
        if target.scrollStep != source.scrollStep {
            guard copyNodeProperty(\.scrollStep, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.showsScrollIndicator != source.showsScrollIndicator {
            guard copyNodeProperty(\.showsScrollIndicator, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollIndicatorAutoHides != source.scrollIndicatorAutoHides {
            guard copyNodeProperty(\.scrollIndicatorAutoHides, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
            guard copyNodeProperty(\.scrollIndicatorColor, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        } else if !source.scrollIndicatorAutoHides, target.scrollIndicatorColor != source.scrollIndicatorColor {
            // An overlay scroller's painted colour is runtime-driven — it is
            // mid-reveal or mid-fade — and a freshly built node always carries
            // the resting one. Copying it across a rebuild would blink the
            // scroller out from under a scroll that is still happening, the
            // same reason `scrollOffset` above is not adopted wholesale.
            guard copyNodeProperty(\.scrollIndicatorColor, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollIndicatorIdleColor != source.scrollIndicatorIdleColor {
            guard copyNodeProperty(\.scrollIndicatorIdleColor, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollIndicatorHoverColor != source.scrollIndicatorHoverColor {
            guard copyNodeProperty(\.scrollIndicatorHoverColor, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollIndicatorActiveColor != source.scrollIndicatorActiveColor {
            guard copyNodeProperty(\.scrollIndicatorActiveColor, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollIndicatorThickness != source.scrollIndicatorThickness {
            guard copyNodeProperty(\.scrollIndicatorThickness, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.scrollIndicatorInsets != source.scrollIndicatorInsets {
            guard copyNodeProperty(\.scrollIndicatorInsets, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.initialScrollAnchor != source.initialScrollAnchor {
            guard copyNodeProperty(\.initialScrollAnchor, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.scrollSizeChangeAnchor != source.scrollSizeChangeAnchor {
            guard copyNodeProperty(\.scrollSizeChangeAnchor, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isFocusable != source.isFocusable {
            guard copyNodeProperty(\.isFocusable, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        // Positional reuse can turn a caret into a label or vice versa.
        // The marker belongs to the incoming chrome, not the retained slot.
        if target.isTextInputCaret != source.isTextInputCaret {
            guard copyNodeProperty(\.isTextInputCaret, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isHitTestVisible != source.isHitTestVisible {
            guard copyNodeProperty(\.isHitTestVisible, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.allowsAutomaticWindowDecorations != source.allowsAutomaticWindowDecorations {
            guard copyNodeProperty(\.allowsAutomaticWindowDecorations, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isHidden != source.isHidden {
            guard copyNodeProperty(\.isHidden, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.accessibilityLabel != source.accessibilityLabel {
            guard copyNodeProperty(\.accessibilityLabel, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.accessibilityDescription != source.accessibilityDescription {
            guard copyNodeProperty(\.accessibilityDescription, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityValue != source.accessibilityValue {
            guard copyNodeProperty(\.accessibilityValue, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.accessibilityHint != source.accessibilityHint {
            guard copyNodeProperty(\.accessibilityHint, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.accessibilityIdentifier != source.accessibilityIdentifier {
            guard copyNodeProperty(\.accessibilityIdentifier, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityLanguage != source.accessibilityLanguage {
            guard copyNodeProperty(\.accessibilityLanguage, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityTextualContext != source.accessibilityTextualContext {
            guard copyNodeProperty(\.accessibilityTextualContext, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityHeadingLevel != source.accessibilityHeadingLevel {
            guard copyNodeProperty(\.accessibilityHeadingLevel, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.tooltip != source.tooltip {
            guard copyNodeProperty(\.tooltip, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.accessibilityTraits != source.accessibilityTraits {
            guard copyNodeProperty(\.accessibilityTraits, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.accessibilityChildBehavior != source.accessibilityChildBehavior {
            guard copyNodeProperty(\.accessibilityChildBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilitySortPriority != source.accessibilitySortPriority {
            guard copyNodeProperty(\.accessibilitySortPriority, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if !(target.accessibilityActions.isEmpty && source.accessibilityActions.isEmpty) {
            guard copyNodeProperty(\.accessibilityActions, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityInputLabels != source.accessibilityInputLabels {
            guard copyNodeProperty(\.accessibilityInputLabels, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isAccessibilityHidden != source.isAccessibilityHidden {
            guard copyNodeProperty(\.isAccessibilityHidden, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityIgnoresInvertColors != source.accessibilityIgnoresInvertColors {
            guard copyNodeProperty(\.accessibilityIgnoresInvertColors, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityRespondsToUserInteraction != source.accessibilityRespondsToUserInteraction {
            guard
                copyNodeProperty(
                    \.accessibilityRespondsToUserInteraction, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityPrefersSliderBehavior != source.accessibilityPrefersSliderBehavior {
            guard copyNodeProperty(\.accessibilityPrefersSliderBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityRequiresActivationPoint != source.accessibilityRequiresActivationPoint {
            guard
                copyNodeProperty(\.accessibilityRequiresActivationPoint, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityDirectTouchOptions != source.accessibilityDirectTouchOptions {
            guard copyNodeProperty(\.accessibilityDirectTouchOptions, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityPrefersCrossFadeTransitions != source.accessibilityPrefersCrossFadeTransitions {
            guard
                copyNodeProperty(
                    \.accessibilityPrefersCrossFadeTransitions, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityShowLargeContentViewer != source.accessibilityShowLargeContentViewer {
            guard copyNodeProperty(\.accessibilityShowLargeContentViewer, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.symbolVariableValue != source.symbolVariableValue {
            guard copyNodeProperty(\.symbolVariableValue, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.symbolRenderingMode != source.symbolRenderingMode {
            guard copyNodeProperty(\.symbolRenderingMode, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.symbolVariants != source.symbolVariants {
            guard copyNodeProperty(\.symbolVariants, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.imageResizingMode != source.imageResizingMode {
            guard copyNodeProperty(\.imageResizingMode, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.imageCapInsets != source.imageCapInsets {
            guard copyNodeProperty(\.imageCapInsets, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.imageUsesBitmapResizing != source.imageUsesBitmapResizing {
            guard copyNodeProperty(\.imageUsesBitmapResizing, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.imageBitmapScale != source.imageBitmapScale {
            guard copyNodeProperty(\.imageBitmapScale, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.imageRenderingMode != source.imageRenderingMode {
            guard copyNodeProperty(\.imageRenderingMode, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.imageInterpolation != source.imageInterpolation {
            guard copyNodeProperty(\.imageInterpolation, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.imageAntialiased != source.imageAntialiased {
            guard copyNodeProperty(\.imageAntialiased, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.keyboardShortcuts != source.keyboardShortcuts {
            guard copyNodeProperty(\.keyboardShortcuts, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.interceptsVerticalArrowKeys != source.interceptsVerticalArrowKeys {
            guard copyNodeProperty(\.interceptsVerticalArrowKeys, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.textInputSubmitLabel != source.textInputSubmitLabel {
            guard copyNodeProperty(\.textInputSubmitLabel, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        let hasIncomingTextInputController = source.textInputController != nil
        guard
            target.reconcileTextInputController(
                from: source, admission: check.admission, lazyJournal: check.lazyJournal,
                taskAdoption: check.taskAdoption, uiaAuthority: check.uiaAuthority),
            check.isCurrent
        else {
            return false
        }
        if !hasIncomingTextInputController {
            if target.textInputCaretOffset != source.textInputCaretOffset {
                guard copyNodeProperty(\.textInputCaretOffset, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.textInputSelection != source.textInputSelection {
                guard copyNodeProperty(\.textInputSelection, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
        }
        if target.textSelectability != source.textSelectability {
            guard copyNodeProperty(\.textSelectability, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.textSelectionAffinity != source.textSelectionAffinity {
            guard copyNodeProperty(\.textSelectionAffinity, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.textContentType != source.textContentType {
            guard copyNodeProperty(\.textContentType, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.textInputKeyboardType != source.textInputKeyboardType {
            guard copyNodeProperty(\.textInputKeyboardType, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.textInputCompletion != source.textInputCompletion {
            guard copyNodeProperty(\.textInputCompletion, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.textInputSuggestions != source.textInputSuggestions {
            guard copyNodeProperty(\.textInputSuggestions, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.writingToolsBehavior != source.writingToolsBehavior {
            guard copyNodeProperty(\.writingToolsBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.writingToolsAffordanceVisibility != source.writingToolsAffordanceVisibility {
            guard copyNodeProperty(\.writingToolsAffordanceVisibility, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.textInputDictationBehavior != source.textInputDictationBehavior {
            guard copyNodeProperty(\.textInputDictationBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isFindDisabled != source.isFindDisabled {
            guard copyNodeProperty(\.isFindDisabled, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.isReplaceDisabled != source.isReplaceDisabled {
            guard copyNodeProperty(\.isReplaceDisabled, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.isFindNavigatorPresented != source.isFindNavigatorPresented {
            guard copyNodeProperty(\.isFindNavigatorPresented, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isSubmitScopeBoundary != source.isSubmitScopeBoundary {
            guard copyNodeProperty(\.isSubmitScopeBoundary, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.submitScopeTriggersRawValue != source.submitScopeTriggersRawValue {
            guard copyNodeProperty(\.submitScopeTriggersRawValue, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isFocusSection != source.isFocusSection {
            guard copyNodeProperty(\.isFocusSection, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.prefersDefaultFocus != source.prefersDefaultFocus {
            guard copyNodeProperty(\.prefersDefaultFocus, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.focusNamespace != source.focusNamespace {
            guard copyNodeProperty(\.focusNamespace, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.isGeometryGroup != source.isGeometryGroup {
            guard copyNodeProperty(\.isGeometryGroup, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.hoverEffect != source.hoverEffect {
            guard copyNodeProperty(\.hoverEffect, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.isHoverEffectDisabled != source.isHoverEffectDisabled {
            guard copyNodeProperty(\.isHoverEffectDisabled, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isFocusEffectDisabled != source.isFocusEffectDisabled {
            guard copyNodeProperty(\.isFocusEffectDisabled, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isFocusDestination != source.isFocusDestination {
            guard copyNodeProperty(\.isFocusDestination, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.isFocusActive != source.isFocusActive {
            guard copyNodeProperty(\.isFocusActive, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.isFocusEnabled != source.isFocusEnabled {
            guard copyNodeProperty(\.isFocusEnabled, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.pointerStyle != source.pointerStyle {
            guard copyNodeProperty(\.pointerStyle, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.pointerVisibility != source.pointerVisibility {
            guard copyNodeProperty(\.pointerVisibility, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.digitalCrownRotation != source.digitalCrownRotation {
            guard copyNodeProperty(\.digitalCrownRotation, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.windowDragInteraction != source.windowDragInteraction {
            guard copyNodeProperty(\.windowDragInteraction, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.windowResizeInteraction != source.windowResizeInteraction {
            guard copyNodeProperty(\.windowResizeInteraction, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.windowDismissBehavior != source.windowDismissBehavior {
            guard copyNodeProperty(\.windowDismissBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.windowFullScreenBehavior != source.windowFullScreenBehavior {
            guard copyNodeProperty(\.windowFullScreenBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.windowMinimizeBehavior != source.windowMinimizeBehavior {
            guard copyNodeProperty(\.windowMinimizeBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.windowResizeBehavior != source.windowResizeBehavior {
            guard copyNodeProperty(\.windowResizeBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.windowCornerRadius != source.windowCornerRadius {
            guard copyNodeProperty(\.windowCornerRadius, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.contentShapes != source.contentShapes {
            guard copyNodeProperty(\.contentShapes, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.buttonRepeatBehavior != source.buttonRepeatBehavior {
            guard copyNodeProperty(\.buttonRepeatBehavior, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.redactionReasons != source.redactionReasons {
            guard copyNodeProperty(\.redactionReasons, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.isPrivacySensitive != source.isPrivacySensitive {
            guard copyNodeProperty(\.isPrivacySensitive, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.isAccessibilityShowsLargeContentViewer != source.isAccessibilityShowsLargeContentViewer {
            guard
                copyNodeProperty(
                    \.isAccessibilityShowsLargeContentViewer, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isAccessibilityQuickActionEnabled != source.isAccessibilityQuickActionEnabled {
            guard copyNodeProperty(\.isAccessibilityQuickActionEnabled, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityQuickActionStyle != source.accessibilityQuickActionStyle {
            guard copyNodeProperty(\.accessibilityQuickActionStyle, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isAccessibilityZoomActionEnabled != source.isAccessibilityZoomActionEnabled {
            guard copyNodeProperty(\.isAccessibilityZoomActionEnabled, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isAccessibilityScrollActionEnabled != source.isAccessibilityScrollActionEnabled {
            guard copyNodeProperty(\.isAccessibilityScrollActionEnabled, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isAccessibilityFocusSection != source.isAccessibilityFocusSection {
            guard copyNodeProperty(\.isAccessibilityFocusSection, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isAccessibilityImage != source.isAccessibilityImage {
            guard copyNodeProperty(\.isAccessibilityImage, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityLinkDestination != source.accessibilityLinkDestination {
            guard copyNodeProperty(\.accessibilityLinkDestination, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityLinkedGroup != source.accessibilityLinkedGroup {
            guard copyNodeProperty(\.accessibilityLinkedGroup, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityPage != source.accessibilityPage {
            guard copyNodeProperty(\.accessibilityPage, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.contextMenuForSelectionType != source.contextMenuForSelectionType {
            guard copyNodeProperty(\.contextMenuForSelectionType, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.widgetURL != source.widgetURL {
            guard copyNodeProperty(\.widgetURL, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.isWidgetAccentable != source.isWidgetAccentable {
            guard copyNodeProperty(\.isWidgetAccentable, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.widgetAccentedRenderingMode != source.widgetAccentedRenderingMode {
            guard copyNodeProperty(\.widgetAccentedRenderingMode, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.widgetBackgroundStyle != source.widgetBackgroundStyle {
            guard copyNodeProperty(\.widgetBackgroundStyle, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.widgetBackgroundPlacement != source.widgetBackgroundPlacement {
            guard copyNodeProperty(\.widgetBackgroundPlacement, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.widgetRelevancy != source.widgetRelevancy {
            guard copyNodeProperty(\.widgetRelevancy, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.paletteSelectionEffect != source.paletteSelectionEffect {
            guard copyNodeProperty(\.paletteSelectionEffect, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.paintsInDeferredPhase != source.paintsInDeferredPhase {
            guard copyNodeProperty(\.paintsInDeferredPhase, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.matchedGeometryEffect != source.matchedGeometryEffect {
            guard copyNodeProperty(\.matchedGeometryEffect, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.matchedTransitionSource != source.matchedTransitionSource {
            guard copyNodeProperty(\.matchedTransitionSource, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.navigationTransition != source.navigationTransition {
            guard copyNodeProperty(\.navigationTransition, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.hasAllocatedChartMetadata || source.hasAllocatedChartMetadata {
            if target.chartXAxis != source.chartXAxis {
                guard copyNodeProperty(\.chartXAxis, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartXScale != source.chartXScale {
                guard copyNodeProperty(\.chartXScale, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartYScale != source.chartYScale {
                guard copyNodeProperty(\.chartYScale, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.meshGradient != source.meshGradient {
                guard copyNodeProperty(\.meshGradient, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartYAxis != source.chartYAxis {
                guard copyNodeProperty(\.chartYAxis, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartLegend != source.chartLegend {
                guard copyNodeProperty(\.chartLegend, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartBackground != source.chartBackground {
                guard copyNodeProperty(\.chartBackground, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartPlotStyle != source.chartPlotStyle {
                guard copyNodeProperty(\.chartPlotStyle, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartOverlay != source.chartOverlay {
                guard copyNodeProperty(\.chartOverlay, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartSelection != source.chartSelection {
                guard copyNodeProperty(\.chartSelection, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartScrollableAxes != source.chartScrollableAxes {
                guard copyNodeProperty(\.chartScrollableAxes, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.chartForegroundStyleScale != source.chartForegroundStyleScale {
                guard copyNodeProperty(\.chartForegroundStyleScale, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.chartSymbolSize != source.chartSymbolSize {
                guard copyNodeProperty(\.chartSymbolSize, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartSymbol != source.chartSymbol {
                guard copyNodeProperty(\.chartSymbol, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartAngleScale != source.chartAngleScale {
                guard copyNodeProperty(\.chartAngleScale, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartBackgroundStyleScale != source.chartBackgroundStyleScale {
                guard copyNodeProperty(\.chartBackgroundStyleScale, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.chartSymbolScale != source.chartSymbolScale {
                guard copyNodeProperty(\.chartSymbolScale, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.chartXVisibleDomain != source.chartXVisibleDomain {
                guard copyNodeProperty(\.chartXVisibleDomain, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.chartYVisibleDomain != source.chartYVisibleDomain {
                guard copyNodeProperty(\.chartYVisibleDomain, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.chartXSelection != source.chartXSelection {
                guard copyNodeProperty(\.chartXSelection, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartYSelection != source.chartYSelection {
                guard copyNodeProperty(\.chartYSelection, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.chartAngleSelection != source.chartAngleSelection {
                guard copyNodeProperty(\.chartAngleSelection, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.chartScrollPositionX != source.chartScrollPositionX {
                guard copyNodeProperty(\.chartScrollPositionX, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.chartScrollPositionY != source.chartScrollPositionY {
                guard copyNodeProperty(\.chartScrollPositionY, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
        }
        if target.tableColumnHeadersVisible != source.tableColumnHeadersVisible {
            guard copyNodeProperty(\.tableColumnHeadersVisible, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isContentInvalidatable != source.isContentInvalidatable {
            guard copyNodeProperty(\.isContentInvalidatable, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isLineSelectable != source.isLineSelectable {
            guard copyNodeProperty(\.isLineSelectable, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.accessibilityActivationPoint != source.accessibilityActivationPoint {
            guard copyNodeProperty(\.accessibilityActivationPoint, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityTextContentType != source.accessibilityTextContentType {
            guard copyNodeProperty(\.accessibilityTextContentType, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityMagicTapAction != nil || source.accessibilityMagicTapAction != nil {
            guard copyNodeProperty(\.accessibilityMagicTapAction, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.presentationChrome != source.presentationChrome {
            guard copyNodeProperty(\.presentationChrome, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.isToolbarContainer != source.isToolbarContainer {
            guard copyNodeProperty(\.isToolbarContainer, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.toolbarPlacementTags != source.toolbarPlacementTags {
            guard copyNodeProperty(\.toolbarPlacementTags, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.menuOrder != source.menuOrder {
            guard copyNodeProperty(\.menuOrder, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.toolbarTitleMenuChildren != nil || source.toolbarTitleMenuChildren != nil {
            guard copyNodeProperty(\.toolbarTitleMenuChildren, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.toolbarTitleActionsChildren != nil || source.toolbarTitleActionsChildren != nil {
            guard copyNodeProperty(\.toolbarTitleActionsChildren, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.accessibilityRepresentationChildren != nil || source.accessibilityRepresentationChildren != nil {
            guard copyNodeProperty(\.accessibilityRepresentationChildren, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.gestureName != source.gestureName {
            guard copyNodeProperty(\.gestureName, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.textRenderer != nil || source.textRenderer != nil {
            guard copyNodeProperty(\.textRenderer, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.scenePaddingEdges != source.scenePaddingEdges {
            guard copyNodeProperty(\.scenePaddingEdges, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.coordinateSpaceName != source.coordinateSpaceName {
            guard copyNodeProperty(\.coordinateSpaceName, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        if target.sectionHeaderChildCount != source.sectionHeaderChildCount {
            guard copyNodeProperty(\.sectionHeaderChildCount, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.sectionFooterChildCount != source.sectionFooterChildCount {
            guard copyNodeProperty(\.sectionFooterChildCount, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if !(target.retainedPreferenceValues.isEmpty && source.retainedPreferenceValues.isEmpty) {
            guard copyNodeProperty(\.retainedPreferenceValues, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if !(target.retainedPreferenceTransformBoundaries.isEmpty
            && source.retainedPreferenceTransformBoundaries.isEmpty)
        {
            guard
                copyNodeProperty(\.retainedPreferenceTransformBoundaries, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if !(target.retainedLayoutValues.isEmpty && source.retainedLayoutValues.isEmpty) {
            guard copyNodeProperty(\.retainedLayoutValues, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if !(target.retainedContainerValues.isEmpty && source.retainedContainerValues.isEmpty) {
            guard copyNodeProperty(\.retainedContainerValues, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.nodeTag != source.nodeTag {
            guard copyNodeProperty(\.nodeTag, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        guard
            let retainedViewIdentityChanged = retainedViewIdentitiesDiffer(
                source: source, target: target, check: check),
            check.isCurrent
        else { return false }
        if retainedViewIdentityChanged {
            guard copyNodeProperty(\.retainedViewIdentity, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.retainedSubtreeBuildLease != nil || source.retainedSubtreeBuildLease != nil {
            guard copyNodeProperty(\.retainedSubtreeBuildLease, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.retainedLazyListGap != source.retainedLazyListGap {
            guard copyNodeProperty(\.retainedLazyListGap, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.retainedLazyListRowChrome != nil || source.retainedLazyListRowChrome != nil {
            guard copyNodeProperty(\.retainedLazyListRowChrome, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.isSeparatorRule != source.isSeparatorRule {
            guard copyNodeProperty(\.isSeparatorRule, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }
        let targetLayoutTag = layoutModeTag(target.layoutMode)
        let sourceLayoutTag = layoutModeTag(source.layoutMode)
        if targetLayoutTag != sourceLayoutTag || layoutConfigurationChanged(target.layoutMode, source.layoutMode) {
            guard copyNodeProperty(\.layoutMode, source: source, target: target, check: check), check.isCurrent else {
                return false
            }
        }
        if target.previousPropertyValues != nil || source.previousPropertyValues != nil {
            guard copyNodeProperty(\.previousPropertyValues, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }

        if target.hasAllocatedInteractionHandlers || source.hasAllocatedInteractionHandlers {
            if target.onPointerEnter != nil || source.onPointerEnter != nil {
                guard copyNodeProperty(\.onPointerEnter, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onPointerExit != nil || source.onPointerExit != nil {
                guard copyNodeProperty(\.onPointerExit, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onPointerMove != nil || source.onPointerMove != nil {
                guard copyNodeProperty(\.onPointerMove, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onPointerDown != nil || source.onPointerDown != nil {
                guard copyNodeProperty(\.onPointerDown, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onPointerUpInside != nil || source.onPointerUpInside != nil {
                guard copyNodeProperty(\.onPointerUpInside, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onPointerUpInsideAt != nil || source.onPointerUpInsideAt != nil {
                guard copyNodeProperty(\.onPointerUpInsideAt, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onPointerUpOutside != nil || source.onPointerUpOutside != nil {
                guard copyNodeProperty(\.onPointerUpOutside, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onContextMenu != nil || source.onContextMenu != nil {
                guard copyNodeProperty(\.onContextMenu, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onFocusEnter != nil || source.onFocusEnter != nil {
                guard copyNodeProperty(\.onFocusEnter, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onFocusExit != nil || source.onFocusExit != nil {
                guard copyNodeProperty(\.onFocusExit, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onKeyDown != nil || source.onKeyDown != nil {
                guard copyNodeProperty(\.onKeyDown, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onIMEComposition != nil || source.onIMEComposition != nil {
                guard copyNodeProperty(\.onIMEComposition, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.textInputCaretRectProvider != nil || source.textInputCaretRectProvider != nil {
                guard copyNodeProperty(\.textInputCaretRectProvider, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onKeyUp != nil || source.onKeyUp != nil {
                guard copyNodeProperty(\.onKeyUp, source: source, target: target, check: check), check.isCurrent else {
                    return false
                }
            }
            if target.onActivate != nil || source.onActivate != nil {
                guard copyNodeProperty(\.onActivate, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onRepeatActivate != nil || source.onRepeatActivate != nil {
                guard copyNodeProperty(\.onRepeatActivate, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.longPressGesture != nil || source.longPressGesture != nil {
                guard copyNodeProperty(\.longPressGesture, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
        }

        if target.hasAllocatedDropHandlers || source.hasAllocatedDropHandlers {
            if target.onDeleteRows != nil || source.onDeleteRows != nil {
                guard copyNodeProperty(\.onDeleteRows, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onMoveRows != nil || source.onMoveRows != nil {
                guard copyNodeProperty(\.onMoveRows, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onInsertRows != nil || source.onInsertRows != nil {
                guard copyNodeProperty(\.onInsertRows, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onDropRows != nil || source.onDropRows != nil {
                guard copyNodeProperty(\.onDropRows, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onValidateDrop != nil || source.onValidateDrop != nil {
                guard copyNodeProperty(\.onValidateDrop, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onDropEntered != nil || source.onDropEntered != nil {
                guard copyNodeProperty(\.onDropEntered, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onDropUpdated != nil || source.onDropUpdated != nil {
                guard copyNodeProperty(\.onDropUpdated, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onDropExited != nil || source.onDropExited != nil {
                guard copyNodeProperty(\.onDropExited, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onDropProviders != nil || source.onDropProviders != nil {
                guard copyNodeProperty(\.onDropProviders, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onDropPayloads != nil || source.onDropPayloads != nil {
                guard copyNodeProperty(\.onDropPayloads, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onMakeDropConfiguration != nil || source.onMakeDropConfiguration != nil {
                guard copyNodeProperty(\.onMakeDropConfiguration, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onMakeDragPayload != nil || source.onMakeDragPayload != nil {
                guard copyNodeProperty(\.onMakeDragPayload, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onMakeDragItemProvider != nil || source.onMakeDragItemProvider != nil {
                guard copyNodeProperty(\.onMakeDragItemProvider, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onDragStart != nil || source.onDragStart != nil {
                guard copyNodeProperty(\.onDragStart, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onDragChange != nil || source.onDragChange != nil {
                guard copyNodeProperty(\.onDragChange, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onDragEnd != nil || source.onDragEnd != nil {
                guard copyNodeProperty(\.onDragEnd, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
        }

        if target.hasAllocatedLifecycleHandlers || source.hasAllocatedLifecycleHandlers {
            if target.onLayout != nil || source.onLayout != nil {
                guard copyNodeProperty(\.onLayout, source: source, target: target, check: check), check.isCurrent else {
                    return false
                }
            }
            if target.onLayoutWithNode != nil || source.onLayoutWithNode != nil {
                guard copyNodeProperty(\.onLayoutWithNode, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.absoluteChildFrame != nil || source.absoluteChildFrame != nil {
                guard copyNodeProperty(\.absoluteChildFrame, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onAppear != nil || source.onAppear != nil {
                guard copyNodeProperty(\.onAppear, source: source, target: target, check: check), check.isCurrent else {
                    return false
                }
            }
            if target.onDisappear != nil || source.onDisappear != nil {
                guard copyNodeProperty(\.onDisappear, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            if target.onAppearWithNode != nil || source.onAppearWithNode != nil {
                guard copyNodeProperty(\.onAppearWithNode, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onDisappearWithNode != nil || source.onDisappearWithNode != nil {
                guard copyNodeProperty(\.onDisappearWithNode, source: source, target: target, check: check),
                    check.isCurrent
                else { return false }
            }
            if target.onSizeChange != nil || source.onSizeChange != nil {
                guard copyNodeProperty(\.onSizeChange, source: source, target: target, check: check), check.isCurrent
                else { return false }
            }
            // The reader's body and the slot it was built from travel together:
            // `target` has just adopted `source`'s children, so it has also
            // adopted the size they were built against. Splitting them would
            // leave the convergence loop comparing a slot against a body it did
            // not produce, and it would rebuild forever. Guarded as a pair for
            // the same reason: either both move or neither does.
            if target.geometryReaderBuild != nil || source.geometryReaderBuild != nil {
                guard check.isCurrent else { return false }
                if check.admission != nil || check.lazyJournal != nil || check.uiaAuthority != nil {
                    guard
                        check.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.geometryReaderBuild),
                        check.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.geometryReaderBuiltSize),
                        check.markMutationStarted()
                    else { return false }
                    copyGeometryReaderPair(source: source, target: target, check: check)
                } else {
                    target.geometryReaderBuild = source.geometryReaderBuild
                    target.geometryReaderBuiltSize = source.geometryReaderBuiltSize
                }
                guard check.isCurrent else { return false }
            }
        }
        if target.onUpdatePlatformView != nil || source.onUpdatePlatformView != nil {
            guard copyNodeProperty(\.onUpdatePlatformView, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.onDismantlePlatformView != nil || source.onDismantlePlatformView != nil {
            guard copyNodeProperty(\.onDismantlePlatformView, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }
        if target.phaseAnimatorState != nil || source.phaseAnimatorState != nil {
            guard copyNodeProperty(\.phaseAnimatorState, source: source, target: target, check: check), check.isCurrent
            else { return false }
        }

        if target.hasAppeared, !target.hasPendingAppearanceCallbacks {
            for launch in source.pendingLifecycleTaskLaunches {
                guard check.isCurrent,
                    target.launchLifecycleTask(
                        launch, admission: check.admission, lazyJournal: check.lazyJournal, source: source,
                        uiaAuthority: check.uiaAuthority),
                    check.isCurrent
                else { return false }
            }
        } else {
            guard copyNodeProperty(\.pendingLifecycleTaskLaunches, source: source, target: target, check: check),
                check.isCurrent
            else { return false }
        }

        guard check.isCurrent else { return false }
        invokePlatformUpdate(on: target)
        guard check.isCurrent else { return false }
        if check.admission != nil || check.lazyJournal != nil || check.uiaAuthority != nil {
            target.finishFileDialogConfigurationAdoption()
        }
        return check.isCurrent
    }
}
