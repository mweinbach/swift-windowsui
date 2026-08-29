import Foundation
import SwiftWindowsCore
import SwiftWindowsPlatform

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
        var phase = Phase.inspecting
        var outcome: Outcome?
        var didRequestSelection = false

        init(ownerGeneration: UInt64, node: ViewNode, kind: RetainedFileDialogKind) {
            self.ownerGeneration = ownerGeneration
            self.node = node
            self.presenterLease = node.beginFileDialogPresentation(kind: kind)
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
    }

    private final class BuildLifecycleInstallation {}
    private var buildLifecycleInstallation = BuildLifecycleInstallation()

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
        buildComponents = content
        reload()
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
        if buildLifecycle == nil, !runtime.hasActiveRetainedBuild {
            performUnmanagedReload(onCompleted: onCompleted)
            return
        }
        let request = ReloadRequest(
            transaction: RetainedBuildTransaction(), validity: buildLifecycle?.captureBuildRequest(),
            onCompleted: onCompleted)
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
            measureBuildAttempt {
                epoch = lifecycle?.beginBuild()
                coordinator.install(epoch, startedAt: sequence)
                runtime.beginLongPressReconciliation()
                didAdopt =
                    (lifecycle == nil || epoch != nil)
                    && buildAndAdopt(epoch: epoch, sequence: sequence, validity: request.validity)
                if didAdopt {
                    epoch?.commit()
                } else {
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
                    if didAdopt, epoch?.canComplete != false {
                        onReloadCompleted?()
                        if epoch?.canComplete != false { request.onCompleted?() }
                    }
                }
                coordinator.finishBuild()
            }
        }
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
        epoch: (any RetainedBuildEpoch)?, sequence: UInt64?, validity: (any RetainedBuildRequest)?
    ) -> Bool {
        guard epoch?.canAdopt != false, validity?.isCurrent != false else { return false }
        if let sequence, runtime.retainedBuildCoordinator.wasSuperseded(since: sequence) { return false }
        return true
    }

    private func buildAndAdopt(
        epoch: (any RetainedBuildEpoch)?, sequence: UInt64?, validity: (any RetainedBuildRequest)?
    ) -> Bool {
        if buildComponents == nil, epoch == nil, sequence == nil {
            runtime.root.removeAllChildren()
            return true
        }
        guard candidateCanAdopt(epoch: epoch, sequence: sequence, validity: validity) else { return false }
        runtime.recordMatchedGeometryFrames()

        let isProfiling = runtime.collectsPhaseTimings
        let reloadStartedAt = isProfiling ? PlatformClock.now() : 0

        let oldChildren = runtime.root.children
        let components = buildComponents?() ?? []
        let composeEndedAt = isProfiling ? PlatformClock.now() : 0
        if isProfiling { lastComposeSeconds = composeEndedAt - reloadStartedAt }
        guard candidateCanAdopt(epoch: epoch, sequence: sequence, validity: validity) else { return false }
        let newNodes = components.map { $0.makeNode(runtime: runtime) }
        let nodesEndedAt = isProfiling ? PlatformClock.now() : 0
        if isProfiling { lastNodeConstructionSeconds = nodesEndedAt - composeEndedAt }

        guard candidateCanAdopt(epoch: epoch, sequence: sequence, validity: validity) else { return false }
        guard epoch?.willAdopt() != false else { return false }
        guard validity?.isCurrent != false else { return false }

        Self.reconcileChildren(of: runtime.root, oldChildren: oldChildren, newNodes: newNodes)
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
        return true
    }

    /// Scans the view tree for active file-dialog configurations and presents
    /// the corresponding Win32 modal dialog. Reentrant requests wait until the
    /// active operation, presentation reset, and completion callback finish.
    public func processPendingFileDialogs() {
        guard fileDialogLifetimeIsValid else { return }
        guard !isProcessingFileDialog else {
            needsFileDialogProcessing = true
            return
        }
        isProcessingFileDialog = true
        defer { isProcessingFileDialog = false }
        var retriedEmptyScan = false
        repeat {
            needsFileDialogProcessing = false
            guard fileDialogLifetimeIsValid else { return }
            if !processNextFileDialog() {
                // A getter may replace the tree and enqueue its new presenter.
                // Retry once without spinning on an unchanged false getter
                // that calls this method every time it is read.
                guard needsFileDialogProcessing, !retriedEmptyScan else { return }
                retriedEmptyScan = true
                continue
            }
            retriedEmptyScan = false
        } while needsFileDialogProcessing
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
        defer {
            operation.presenterLease.invalidate()
            if operation.phase != .revoked { operation.phase = .finished }
            if activeFileDialogOperation === operation { activeFileDialogOperation = nil }
        }
        presentFileDialog(config, operation: operation)
        return operation.didRequestSelection
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
            let operation = FileDialogOperation(
                ownerGeneration: fileDialogOwnerGeneration, node: node, kind: config.kind)
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
        let isPresented = config.isPresented.wrappedValue
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
        let owner = fileDialogOwner()
        guard validateFileDialogPresentation(config, operation: operation) else { return }
        operation.didRequestSelection = true
        switch config {
        case .exporter(let exporter):
            let selection = FileDialogManager.saveFileDialogOutcome(
                defaultFilename: exporter.defaultFilename,
                allowedExtensions: FileDialogManager.fileExtensions(forContentTypes: [exporter.contentType]),
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner
            )
            guard validateFileDialogPresentation(config, operation: operation) else { return }
            switch selection {
            case .cancelled:
                completeFileDialog(config, operation: operation, outcome: .cancelled)
            case .failed(let error):
                completeFileDialog(
                    config, operation: operation, result: .failure(error), completion: exporter.onCompletion)
            case .selected(let url):
                operation.phase = .accessingFile
                let result: Result<URL, Error> = Result {
                    try exporter.write(to: url) {
                        try self.validateFileDialogAccess(config, operation: operation)
                    }
                    return url
                }
                completeFileDialog(config, operation: operation, result: result, completion: exporter.onCompletion)
            }

        case .importer(let importer):
            let selection = FileDialogManager.openFileDialogOutcome(
                allowedExtensions: FileDialogManager.fileExtensions(forContentTypes: importer.allowedContentTypes),
                allowsMultipleSelection: false,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner
            )
            guard validateFileDialogPresentation(config, operation: operation) else { return }
            switch selection {
            case .selected(let urls):
                let result: Result<URL, Error> =
                    urls.first.map(Result.success) ?? .failure(FileDialogError.invalidSelection)
                completeFileDialog(config, operation: operation, result: result, completion: importer.onCompletion)
            case .cancelled:
                let error = fileDialogCancellationError()
                completeFileDialog(config, operation: operation, outcome: .cancelled) {
                    importer.onCompletion(.failure(error))
                }
            case .failed(let error):
                completeFileDialog(
                    config, operation: operation, result: .failure(error), completion: importer.onCompletion)
            }

        case .importerMulti(let importerMulti):
            let selection = FileDialogManager.openFileDialogOutcome(
                allowedExtensions: FileDialogManager.fileExtensions(
                    forContentTypes: importerMulti.allowedContentTypes),
                allowsMultipleSelection: importerMulti.allowsMultipleSelection,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner
            )
            guard validateFileDialogPresentation(config, operation: operation) else { return }
            switch selection {
            case .selected(let urls):
                let result: Result<[URL], Error> =
                    urls.isEmpty ? .failure(FileDialogError.invalidSelection) : .success(urls)
                completeFileDialog(config, operation: operation, result: result, completion: importerMulti.onCompletion)
            case .cancelled:
                let error = fileDialogCancellationError()
                completeFileDialog(config, operation: operation, outcome: .cancelled) {
                    importerMulti.onCompletion(.failure(error))
                }
            case .failed(let error):
                completeFileDialog(
                    config, operation: operation, result: .failure(error), completion: importerMulti.onCompletion)
            }

        case .mover(let mover):
            let selection = FileDialogManager.saveFileDialogOutcome(
                defaultFilename: mover.file.lastPathComponent,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner
            )
            guard validateFileDialogPresentation(config, operation: operation) else { return }
            switch selection {
            case .selected(let destination):
                operation.phase = .accessingFile
                let result: Result<URL, Error> = Result {
                    try validateFileDialogAccess(config, operation: operation)
                    try FileManager.default.moveItem(at: mover.file, to: destination)
                    return destination
                }
                completeFileDialog(config, operation: operation, result: result, completion: mover.onCompletion)
            case .cancelled:
                let error = fileDialogCancellationError()
                completeFileDialog(config, operation: operation, outcome: .cancelled) {
                    mover.onCompletion(.failure(error))
                }
            case .failed(let error):
                completeFileDialog(
                    config, operation: operation, result: .failure(error), completion: mover.onCompletion)
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
    static func adopt(source: ViewNode, into target: ViewNode) {
        target.invalidateRenderLifecycleCandidates()
        revokeDepartingTextInputOwnership(source: source, target: target)
        withReconcileAnimationTransaction(source: source, previous: target) {
            updateNodeProperties(target: target, source: source)
            reconcilePreparedChildren(of: target, oldChildren: target.children, newNodes: source.children)
        }
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
        source: ViewNode, previous: ViewNode?, perform body: () -> Void
    ) {
        let modifiers = source.reconcileAnimationModifiers
        guard !modifiers.isEmpty else {
            body()
            return
        }
        let previousModifiers = previous?.reconcileAnimationModifiers ?? []
        var transaction = inheritedTransaction ?? Transaction()
        var didApplyModifier = false
        for index in modifiers.indices.reversed() {
            let previousModifier = previousModifiers.indices.contains(index) ? previousModifiers[index] : nil
            if modifiers[index].apply(to: &transaction, previous: previousModifier) {
                didApplyModifier = true
            }
        }
        guard didApplyModifier else {
            body()
            return
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
        body()
    }

    private static func prepareInsertedSubtree(_ node: ViewNode) {
        withReconcileAnimationTransaction(source: node, previous: nil) {
            node.retainInsertionTransaction(inheritedTransaction)
            for child in node.children {
                prepareInsertedSubtree(child)
            }
        }
    }

    /// Reconciliation claims typed identities first, legacy tags second,
    /// then considers the next unclaimed positional candidate. A typed node
    /// never bridges to an untyped node through a tag or matching layout.
    ///
    /// Each old node can be claimed once, including when duplicate identities
    /// occur. Survivors keep their nodes and move into the new order, retaining
    /// runtime-owned focus, scroll state, and animations. Raw retained trees
    /// without typed identities keep their existing matching behavior.
    static func reconcileChildren(of parent: ViewNode, oldChildren: [ViewNode], newNodes: [ViewNode]) {
        parent.invalidateRenderLifecycleCandidates()
        // Mark every departure before any branch starts its callbacks. A
        // callback in an earlier branch can otherwise replay a later editor
        // that will leave in the same adoption but still reaches the root.
        revokeDepartingTextInputOwnership(oldChildren: oldChildren, newNodes: newNodes)
        reconcilePreparedChildren(of: parent, oldChildren: oldChildren, newNodes: newNodes)
    }

    private static func matchingChildren(oldChildren: [ViewNode], newNodes: [ViewNode]) -> [ViewNode?] {
        // A single candidate has no competing claims; the same typed, tag,
        // and layout rules can be applied without constructing lookup tables.
        if oldChildren.count == 1 && newNodes.count == 1 {
            return [nodesMatch(oldChildren[0], newNodes[0]) ? oldChildren[0] : nil]
        }

        var matches = [ViewNode?](repeating: nil, count: newNodes.count)
        var isClaimed = [Bool](repeating: false, count: oldChildren.count)

        var oldIndicesByIdentity: [RetainedViewIdentity: [Int]] = [:]
        var oldIndicesByTag: [String: [Int]] = [:]
        for (index, oldNode) in oldChildren.enumerated() {
            if let identity = oldNode.retainedViewIdentity {
                oldIndicesByIdentity[identity, default: []].append(index)
            } else if let tag = oldNode.nodeTag {
                oldIndicesByTag[tag, default: []].append(index)
            }
        }

        if !oldIndicesByIdentity.isEmpty {
            for (newIndex, newNode) in newNodes.enumerated() {
                guard let identity = newNode.retainedViewIdentity,
                    var candidates = oldIndicesByIdentity[identity], !candidates.isEmpty
                else { continue }
                let oldIndex = candidates.removeFirst()
                oldIndicesByIdentity[identity] = candidates
                matches[newIndex] = oldChildren[oldIndex]
                isClaimed[oldIndex] = true
            }
        }

        if !oldIndicesByTag.isEmpty {
            for (newIndex, newNode) in newNodes.enumerated() {
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
            while cursor < oldChildren.count {
                if isClaimed[cursor] {
                    cursor += 1
                    continue
                }
                if nodesMatch(oldChildren[cursor], newNode) {
                    matches[newIndex] = oldChildren[cursor]
                    isClaimed[cursor] = true
                    cursor += 1
                }
                break
            }
        }

        return matches
    }

    private static func revokeDepartingTextInputOwnership(source: ViewNode, target: ViewNode) {
        target.listNavigationOwner?.prepareForAdoption(of: source.listNavigationOwner)
        target.revokeFileDialogPresentation(ifAbsentFrom: source)
        if let controller = source.textInputController {
            controller.prepareForReconciliation(from: target.textInputController, onto: target)
        } else {
            target.textInputController?.revokeOwnership(from: target)
        }
        revokeDepartingTextInputOwnership(oldChildren: target.children, newNodes: source.children)
    }

    private static func revokeDepartingTextInputOwnership(oldChildren: [ViewNode], newNodes: [ViewNode]) {
        let matches = matchingChildren(oldChildren: oldChildren, newNodes: newNodes)
        let survivors = Set(matches.compactMap { $0 }.map(ObjectIdentifier.init))
        for oldNode in oldChildren where !survivors.contains(ObjectIdentifier(oldNode)) {
            oldNode.revokeTextInputOwnership()
        }
        for (index, newNode) in newNodes.enumerated() {
            if let oldNode = matches[index] {
                revokeDepartingTextInputOwnership(source: newNode, target: oldNode)
            }
        }
    }

    private static func reconcilePreparedChildren(of parent: ViewNode, oldChildren: [ViewNode], newNodes: [ViewNode]) {
        let matches = matchingChildren(oldChildren: oldChildren, newNodes: newNodes)

        var nextChildren: [ViewNode] = []
        nextChildren.reserveCapacity(newNodes.count)
        for (newIndex, newNode) in newNodes.enumerated() {
            guard let oldNode = matches[newIndex] else {
                prepareInsertedSubtree(newNode)
                nextChildren.append(newNode)
                continue
            }
            withReconcileAnimationTransaction(source: newNode, previous: oldNode) {
                updateNodeProperties(target: oldNode, source: newNode)
                reconcilePreparedChildren(of: oldNode, oldChildren: oldNode.children, newNodes: newNode.children)
            }
            nextChildren.append(oldNode)
        }

        parent.setChildren(nextChildren)
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
        }
    }

    /// Reconcile a model value without replacing an animation's presentation
    /// value. An unchanged destination keeps its original clock; a different
    /// destination starts from the value that is currently on screen.
    private static func reconciledAnimatedValue(
        _ property: AnimatableProperty, current: Double, proposed: Double,
        target: ViewNode, source: ViewNode, transaction: AnimationTransaction?,
        startTime: inout Double?, animationsDisabled: Bool
    ) -> Double {
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
        let timestamp = startTime ?? target.animationClockNow
        startTime = timestamp
        target.animationStates[property] = AnimationState(
            startValue: current, endValue: proposed, startTime: timestamp,
            duration: animation.duration, easing: animation.easing)
        return current
    }

    /// Copy visual / layout properties from `source` onto `target`, keeping
    /// `target`'s identity (parent, runtime, callbacks) intact.
    private static func updateNodeProperties(target: ViewNode, source: ViewNode) {
        let listNavigationOwner = target.adoptListNavigationOwner(from: source)
        defer { listNavigationOwner?.finishAdoption() }
        defer { target.finishFileDialogConfigurationAdoption() }
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
            target.reconcileAnimationModifiers = source.reconcileAnimationModifiers
        }
        if target.implicitReconcileAnimation != source.implicitReconcileAnimation {
            target.implicitReconcileAnimation = source.implicitReconcileAnimation
        }
        if target.interactionSurface != nil || source.interactionSurface != nil {
            target.interactionSurface = source.interactionSurface
        }
        target.retainInsertionTransaction(inheritedTransaction)
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
                    animationsDisabled: animationsDisabled),
                y: reconciledAnimatedValue(
                    .frameOriginY, current: oldFrame.origin.y, proposed: source.frame.origin.y,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled),
                width: reconciledAnimatedValue(
                    .frameWidth, current: oldFrame.size.width, proposed: source.frame.size.width,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled),
                height: reconciledAnimatedValue(
                    .frameHeight, current: oldFrame.size.height, proposed: source.frame.size.height,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled)
            )
            if target.frame != nextFrame { target.frame = nextFrame }
        }
        if target.backgroundColor != source.backgroundColor { target.backgroundColor = source.backgroundColor }
        if target.backgroundGradient != source.backgroundGradient {
            target.backgroundGradient = source.backgroundGradient
        }
        target.applyReconcileFillTween(
            fromBackgroundColor: oldBackgroundColor,
            fromBackgroundGradient: oldBackgroundGradient,
            animation: reconcileTransaction,
            animationsDisabled: animationsDisabled
        )
        if target.bitmapSurface != source.bitmapSurface { target.bitmapSurface = source.bitmapSurface }
        if target.canvasDraw != nil || source.canvasDraw != nil { target.canvasDraw = source.canvasDraw }
        if target.text != source.text { target.text = source.text }
        if target.textStyle != source.textStyle { target.textStyle = source.textStyle }
        if target.borderColor != source.borderColor { target.borderColor = source.borderColor }
        if target.borderGradient != source.borderGradient { target.borderGradient = source.borderGradient }
        if target.borderWidth != source.borderWidth { target.borderWidth = source.borderWidth }
        if target.borderStrokeStyle != source.borderStrokeStyle { target.borderStrokeStyle = source.borderStrokeStyle }
        if target.outlineColor != source.outlineColor { target.outlineColor = source.outlineColor }
        if target.outlineWidth != source.outlineWidth { target.outlineWidth = source.outlineWidth }
        if target.shadowColor != source.shadowColor { target.shadowColor = source.shadowColor }
        if target.shadowOffset != source.shadowOffset { target.shadowOffset = source.shadowOffset }
        if target.shadowSpread != source.shadowSpread { target.shadowSpread = source.shadowSpread }
        if target.cornerRadius != source.cornerRadius { target.cornerRadius = source.cornerRadius }
        if target.clipsToBounds != source.clipsToBounds { target.clipsToBounds = source.clipsToBounds }
        if target.clipFillStyle != source.clipFillStyle { target.clipFillStyle = source.clipFillStyle }
        if target.backgroundPath != source.backgroundPath { target.backgroundPath = source.backgroundPath }
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
                        || !oldSize.width.isFinite || !proposedSize.width.isFinite),
                height: reconciledAnimatedValue(
                    .preferredHeight, current: oldSize.height, proposed: proposedSize.height,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled || oldSize.height <= 0 || proposedSize.height <= 0
                        || !oldSize.height.isFinite || !proposedSize.height.isFinite)
            )
            if target.preferredSize != nextSize { target.preferredSize = nextSize }
        } else {
            if target.animationStates[.preferredWidth] != nil { target.animationStates[.preferredWidth] = nil }
            if target.animationStates[.preferredHeight] != nil { target.animationStates[.preferredHeight] = nil }
            if target.preferredSize != source.preferredSize { target.preferredSize = source.preferredSize }
        }
        if target.layoutConstraints != source.layoutConstraints { target.layoutConstraints = source.layoutConstraints }
        if target.fixedSizeAxes != source.fixedSizeAxes { target.fixedSizeAxes = source.fixedSizeAxes }
        if target.layoutFillAxes != source.layoutFillAxes { target.layoutFillAxes = source.layoutFillAxes }
        if target.explicitFrameFillAxes != source.explicitFrameFillAxes {
            target.explicitFrameFillAxes = source.explicitFrameFillAxes
        }
        if target.forwardsStackMainAxisProposal != source.forwardsStackMainAxisProposal {
            target.forwardsStackMainAxisProposal = source.forwardsStackMainAxisProposal
        }
        if target.layoutPriority != source.layoutPriority { target.layoutPriority = source.layoutPriority }
        if target.spatialCompressionResistance != source.spatialCompressionResistance {
            target.spatialCompressionResistance = source.spatialCompressionResistance
        }
        if target.spatialExpansionResistance != source.spatialExpansionResistance {
            target.spatialExpansionResistance = source.spatialExpansionResistance
        }
        if target.alignmentGuides != source.alignmentGuides { target.alignmentGuides = source.alignmentGuides }
        if target.gridCellAnchor != source.gridCellAnchor { target.gridCellAnchor = source.gridCellAnchor }
        if target.gridCellUnsizedAxes != source.gridCellUnsizedAxes {
            target.gridCellUnsizedAxes = source.gridCellUnsizedAxes
        }
        if target.gridCellColumns != source.gridCellColumns { target.gridCellColumns = source.gridCellColumns }
        if target.gridColumnAlignment != source.gridColumnAlignment {
            target.gridColumnAlignment = source.gridColumnAlignment
        }
        if target.blurRadius != source.blurRadius { target.blurRadius = source.blurRadius }
        if target.blurOpaque != source.blurOpaque { target.blurOpaque = source.blurOpaque }
        if target.geometryEffect != source.geometryEffect { target.geometryEffect = source.geometryEffect }
        if oldOpacity != source.opacity || target.animationStates[.opacity] != nil {
            let nextOpacity = reconciledAnimatedValue(
                .opacity, current: oldOpacity, proposed: source.opacity,
                target: target, source: source, transaction: reconcileTransaction,
                startTime: &animationStartTime,
                animationsDisabled: animationsDisabled)
            if target.opacity != nextOpacity { target.opacity = nextOpacity }
        }
        if target.blendMode != source.blendMode { target.blendMode = source.blendMode }
        if target.isCompositingGroup != source.isCompositingGroup {
            target.isCompositingGroup = source.isCompositingGroup
        }
        if target.drawingGroup != source.drawingGroup { target.drawingGroup = source.drawingGroup }
        if target.colorEffects != source.colorEffects { target.colorEffects = source.colorEffects }
        if target.visualEffects != source.visualEffects { target.visualEffects = source.visualEffects }
        if target.viewMask != source.viewMask { target.viewMask = source.viewMask }
        if target.listRowSeparator != source.listRowSeparator { target.listRowSeparator = source.listRowSeparator }
        if target.listRowSeparatorTint != source.listRowSeparatorTint {
            target.listRowSeparatorTint = source.listRowSeparatorTint
        }
        if target.listSectionSeparator != source.listSectionSeparator {
            target.listSectionSeparator = source.listSectionSeparator
        }
        if target.listSectionSeparatorTint != source.listSectionSeparatorTint {
            target.listSectionSeparatorTint = source.listSectionSeparatorTint
        }
        if target.alternatingRowBackgrounds != source.alternatingRowBackgrounds {
            target.alternatingRowBackgrounds = source.alternatingRowBackgrounds
        }
        if target.listRowHoverStyle != source.listRowHoverStyle { target.listRowHoverStyle = source.listRowHoverStyle }
        if target.listItemTint != source.listItemTint { target.listItemTint = source.listItemTint }
        if target.listRowPlatterColor != source.listRowPlatterColor {
            target.listRowPlatterColor = source.listRowPlatterColor
        }
        if target.navigationSplitViewColumnWidth != source.navigationSplitViewColumnWidth {
            target.navigationSplitViewColumnWidth = source.navigationSplitViewColumnWidth
        }
        if target.preferredCompactColumn != source.preferredCompactColumn {
            target.preferredCompactColumn = source.preferredCompactColumn
        }
        if target.selectionDisabled != source.selectionDisabled { target.selectionDisabled = source.selectionDisabled }
        if target.selectionDisabledOverride != source.selectionDisabledOverride {
            target.selectionDisabledOverride = source.selectionDisabledOverride
        }
        if target.deleteDisabled != source.deleteDisabled { target.deleteDisabled = source.deleteDisabled }
        if target.deleteDisabledOverride != source.deleteDisabledOverride {
            target.deleteDisabledOverride = source.deleteDisabledOverride
        }
        if target.moveDisabled != source.moveDisabled { target.moveDisabled = source.moveDisabled }
        if target.moveDisabledOverride != source.moveDisabledOverride {
            target.moveDisabledOverride = source.moveDisabledOverride
        }
        if target.onDeleteAction != nil || source.onDeleteAction != nil {
            target.onDeleteAction = source.onDeleteAction
        }
        if target.onMoveAction != nil || source.onMoveAction != nil { target.onMoveAction = source.onMoveAction }
        if target.editActions != source.editActions { target.editActions = source.editActions }
        if target.swipeActionsLeading != nil || source.swipeActionsLeading != nil {
            target.swipeActionsLeading = source.swipeActionsLeading
        }
        if target.swipeActionsTrailing != nil || source.swipeActionsTrailing != nil {
            target.swipeActionsTrailing = source.swipeActionsTrailing
        }
        if target.swipeActionsAllowsFullSwipe != source.swipeActionsAllowsFullSwipe {
            target.swipeActionsAllowsFullSwipe = source.swipeActionsAllowsFullSwipe
        }
        if !(target.commandHandlers.isEmpty && source.commandHandlers.isEmpty) {
            target.commandHandlers = source.commandHandlers
        }
        if target.fileExporterConfiguration != nil || source.fileExporterConfiguration != nil {
            target.fileExporterConfiguration = source.fileExporterConfiguration
        }
        if target.fileImporterConfiguration != nil || source.fileImporterConfiguration != nil {
            target.fileImporterConfiguration = source.fileImporterConfiguration
        }
        if target.fileImporterMultiConfiguration != nil || source.fileImporterMultiConfiguration != nil {
            target.fileImporterMultiConfiguration = source.fileImporterMultiConfiguration
        }
        if target.fileMoverConfiguration != nil || source.fileMoverConfiguration != nil {
            target.fileMoverConfiguration = source.fileMoverConfiguration
        }
        if target.inspectorColumnWidth != source.inspectorColumnWidth {
            target.inspectorColumnWidth = source.inspectorColumnWidth
        }
        if target.inspectorColumnWidthFraction != source.inspectorColumnWidthFraction {
            target.inspectorColumnWidthFraction = source.inspectorColumnWidthFraction
        }
        if target.inspectorColumnWidthMin != source.inspectorColumnWidthMin {
            target.inspectorColumnWidthMin = source.inspectorColumnWidthMin
        }
        if target.inspectorPresentationStyle != source.inspectorPresentationStyle {
            target.inspectorPresentationStyle = source.inspectorPresentationStyle
        }
        if target.fileDialogCustomizationID != source.fileDialogCustomizationID {
            target.fileDialogCustomizationID = source.fileDialogCustomizationID
        }
        if target.fileDialogConfirmationLabel != source.fileDialogConfirmationLabel {
            target.fileDialogConfirmationLabel = source.fileDialogConfirmationLabel
        }
        if target.fileDialogDefaultDirectory != source.fileDialogDefaultDirectory {
            target.fileDialogDefaultDirectory = source.fileDialogDefaultDirectory
        }
        if target.fileDialogMessage != source.fileDialogMessage { target.fileDialogMessage = source.fileDialogMessage }
        if target.dynamicContentIndex != source.dynamicContentIndex {
            target.dynamicContentIndex = source.dynamicContentIndex
        }
        if target.dynamicInsertContentTypes != source.dynamicInsertContentTypes {
            target.dynamicInsertContentTypes = source.dynamicInsertContentTypes
        }
        if target.dynamicDropPayloadType != source.dynamicDropPayloadType {
            target.dynamicDropPayloadType = source.dynamicDropPayloadType
        }
        if target.dropAcceptedContentTypes != source.dropAcceptedContentTypes {
            target.dropAcceptedContentTypes = source.dropAcceptedContentTypes
        }
        if target.dropPayloadType != source.dropPayloadType { target.dropPayloadType = source.dropPayloadType }
        if target.isDropDestinationEnabled != source.isDropDestinationEnabled {
            target.isDropDestinationEnabled = source.isDropDestinationEnabled
        }
        if target.hasDropConfiguration != source.hasDropConfiguration {
            target.hasDropConfiguration = source.hasDropConfiguration
        }
        if target.dragDropPreviewsFormation != source.dragDropPreviewsFormation {
            target.dragDropPreviewsFormation = source.dragDropPreviewsFormation
        }
        if target.springLoadingBehavior != source.springLoadingBehavior {
            target.springLoadingBehavior = source.springLoadingBehavior
        }
        if target.dragPayloadType != source.dragPayloadType { target.dragPayloadType = source.dragPayloadType }
        if target.dragItemProviderTypeIdentifiers != source.dragItemProviderTypeIdentifiers {
            target.dragItemProviderTypeIdentifiers = source.dragItemProviderTypeIdentifiers
        }
        if target.dragContainerItemID != source.dragContainerItemID {
            target.dragContainerItemID = source.dragContainerItemID
        }
        if target.dragContainerNamespaceID != source.dragContainerNamespaceID {
            target.dragContainerNamespaceID = source.dragContainerNamespaceID
        }
        if target.hasDragPreview != source.hasDragPreview { target.hasDragPreview = source.hasDragPreview }
        if target.horizontalScrollBounceBehavior != source.horizontalScrollBounceBehavior {
            target.horizontalScrollBounceBehavior = source.horizontalScrollBounceBehavior
        }
        if target.verticalScrollBounceBehavior != source.verticalScrollBounceBehavior {
            target.verticalScrollBounceBehavior = source.verticalScrollBounceBehavior
        }
        if target.scrollTargetBehavior != source.scrollTargetBehavior {
            target.scrollTargetBehavior = source.scrollTargetBehavior
        }
        if target.isScrollTargetLayout != source.isScrollTargetLayout {
            target.isScrollTargetLayout = source.isScrollTargetLayout
        }
        if target.scrollInputBehaviors != source.scrollInputBehaviors {
            target.scrollInputBehaviors = source.scrollInputBehaviors
        }
        if target.scrollIndicatorsFlashOnAppear != source.scrollIndicatorsFlashOnAppear {
            target.scrollIndicatorsFlashOnAppear = source.scrollIndicatorsFlashOnAppear
        }
        if target.scrollIndicatorsFlashTrigger != source.scrollIndicatorsFlashTrigger {
            target.scrollIndicatorsFlashTrigger = source.scrollIndicatorsFlashTrigger
        }
        if target.scrollTransition != source.scrollTransition { target.scrollTransition = source.scrollTransition }
        if target.scrollPosition != source.scrollPosition { target.scrollPosition = source.scrollPosition }
        if target.scrollObservations != source.scrollObservations {
            target.scrollObservations = source.scrollObservations
        }
        target.reconcileScrollObservers(from: source)
        if target.scrollReaderID != source.scrollReaderID { target.scrollReaderID = source.scrollReaderID }
        if target.scrollProxyRequests != source.scrollProxyRequests {
            target.scrollProxyRequests = source.scrollProxyRequests
        }
        if target.zIndex != source.zIndex { target.zIndex = source.zIndex }
        if target.position != source.position { target.position = source.position }
        if target.transform != source.transform || !target.animationStates.isEmpty {
            let oldTransform = target.transform
            let nextTransform = Transform2D(
                translationX: reconciledAnimatedValue(
                    .transformTranslationX, current: oldTransform.translationX, proposed: source.transform.translationX,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled),
                translationY: reconciledAnimatedValue(
                    .transformTranslationY, current: oldTransform.translationY, proposed: source.transform.translationY,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled),
                scaleX: reconciledAnimatedValue(
                    .transformScaleX, current: oldTransform.scaleX, proposed: source.transform.scaleX,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled),
                scaleY: reconciledAnimatedValue(
                    .transformScaleY, current: oldTransform.scaleY, proposed: source.transform.scaleY,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled),
                rotation: reconciledAnimatedValue(
                    .transformRotation, current: oldTransform.rotation, proposed: source.transform.rotation,
                    target: target, source: source, transaction: reconcileTransaction,
                    startTime: &animationStartTime,
                    animationsDisabled: animationsDisabled),
                skewX: source.transform.skewX,
                skewY: source.transform.skewY
            )
            if target.transform != nextTransform { target.transform = nextTransform }
        }
        if target.transition != source.transition { target.transition = source.transition }
        if target.contentTransition != source.contentTransition { target.contentTransition = source.contentTransition }
        if target.sensoryFeedback != source.sensoryFeedback { target.sensoryFeedback = source.sensoryFeedback }
        if target.flexItem != source.flexItem { target.flexItem = source.flexItem }
        if target.flexItemStyle != source.flexItemStyle { target.flexItemStyle = source.flexItemStyle }
        if target.scrollAxis != source.scrollAxis { target.scrollAxis = source.scrollAxis }
        target.reconcileScrollContainer(from: source)
        // Scroll offsets are runtime-driven (wheel/drag/keyboard); a freshly
        // built node always starts at zero, so only adopt a source offset that
        // was explicitly set and never let a rebuild reset a live offset.
        if source.scrollOffset != 0, target.scrollOffset != source.scrollOffset {
            target.scrollOffset = source.scrollOffset
        }
        if target.scrollStep != source.scrollStep { target.scrollStep = source.scrollStep }
        if target.showsScrollIndicator != source.showsScrollIndicator {
            target.showsScrollIndicator = source.showsScrollIndicator
        }
        if target.scrollIndicatorAutoHides != source.scrollIndicatorAutoHides {
            target.scrollIndicatorAutoHides = source.scrollIndicatorAutoHides
            target.scrollIndicatorColor = source.scrollIndicatorColor
        } else if !source.scrollIndicatorAutoHides, target.scrollIndicatorColor != source.scrollIndicatorColor {
            // An overlay scroller's painted colour is runtime-driven — it is
            // mid-reveal or mid-fade — and a freshly built node always carries
            // the resting one. Copying it across a rebuild would blink the
            // scroller out from under a scroll that is still happening, the
            // same reason `scrollOffset` above is not adopted wholesale.
            target.scrollIndicatorColor = source.scrollIndicatorColor
        }
        if target.scrollIndicatorIdleColor != source.scrollIndicatorIdleColor {
            target.scrollIndicatorIdleColor = source.scrollIndicatorIdleColor
        }
        if target.scrollIndicatorHoverColor != source.scrollIndicatorHoverColor {
            target.scrollIndicatorHoverColor = source.scrollIndicatorHoverColor
        }
        if target.scrollIndicatorActiveColor != source.scrollIndicatorActiveColor {
            target.scrollIndicatorActiveColor = source.scrollIndicatorActiveColor
        }
        if target.scrollIndicatorThickness != source.scrollIndicatorThickness {
            target.scrollIndicatorThickness = source.scrollIndicatorThickness
        }
        if target.scrollIndicatorInsets != source.scrollIndicatorInsets {
            target.scrollIndicatorInsets = source.scrollIndicatorInsets
        }
        if target.initialScrollAnchor != source.initialScrollAnchor {
            target.initialScrollAnchor = source.initialScrollAnchor
        }
        if target.scrollSizeChangeAnchor != source.scrollSizeChangeAnchor {
            target.scrollSizeChangeAnchor = source.scrollSizeChangeAnchor
        }
        if target.isFocusable != source.isFocusable { target.isFocusable = source.isFocusable }
        // Positional reuse can turn a caret into a label or vice versa.
        // The marker belongs to the incoming chrome, not the retained slot.
        if target.isTextInputCaret != source.isTextInputCaret { target.isTextInputCaret = source.isTextInputCaret }
        if target.isHitTestVisible != source.isHitTestVisible { target.isHitTestVisible = source.isHitTestVisible }
        if target.allowsAutomaticWindowDecorations != source.allowsAutomaticWindowDecorations {
            target.allowsAutomaticWindowDecorations = source.allowsAutomaticWindowDecorations
        }
        if target.isHidden != source.isHidden { target.isHidden = source.isHidden }
        if target.accessibilityLabel != source.accessibilityLabel {
            target.accessibilityLabel = source.accessibilityLabel
        }
        if target.accessibilityDescription != source.accessibilityDescription {
            target.accessibilityDescription = source.accessibilityDescription
        }
        if target.accessibilityValue != source.accessibilityValue {
            target.accessibilityValue = source.accessibilityValue
        }
        if target.accessibilityHint != source.accessibilityHint { target.accessibilityHint = source.accessibilityHint }
        if target.accessibilityIdentifier != source.accessibilityIdentifier {
            target.accessibilityIdentifier = source.accessibilityIdentifier
        }
        if target.accessibilityLanguage != source.accessibilityLanguage {
            target.accessibilityLanguage = source.accessibilityLanguage
        }
        if target.accessibilityTextualContext != source.accessibilityTextualContext {
            target.accessibilityTextualContext = source.accessibilityTextualContext
        }
        if target.accessibilityHeadingLevel != source.accessibilityHeadingLevel {
            target.accessibilityHeadingLevel = source.accessibilityHeadingLevel
        }
        if target.tooltip != source.tooltip { target.tooltip = source.tooltip }
        if target.accessibilityTraits != source.accessibilityTraits {
            target.accessibilityTraits = source.accessibilityTraits
        }
        if target.accessibilityChildBehavior != source.accessibilityChildBehavior {
            target.accessibilityChildBehavior = source.accessibilityChildBehavior
        }
        if target.accessibilitySortPriority != source.accessibilitySortPriority {
            target.accessibilitySortPriority = source.accessibilitySortPriority
        }
        if !(target.accessibilityActions.isEmpty && source.accessibilityActions.isEmpty) {
            target.accessibilityActions = source.accessibilityActions
        }
        if target.accessibilityInputLabels != source.accessibilityInputLabels {
            target.accessibilityInputLabels = source.accessibilityInputLabels
        }
        if target.isAccessibilityHidden != source.isAccessibilityHidden {
            target.isAccessibilityHidden = source.isAccessibilityHidden
        }
        if target.accessibilityIgnoresInvertColors != source.accessibilityIgnoresInvertColors {
            target.accessibilityIgnoresInvertColors = source.accessibilityIgnoresInvertColors
        }
        if target.accessibilityRespondsToUserInteraction != source.accessibilityRespondsToUserInteraction {
            target.accessibilityRespondsToUserInteraction = source.accessibilityRespondsToUserInteraction
        }
        if target.accessibilityPrefersSliderBehavior != source.accessibilityPrefersSliderBehavior {
            target.accessibilityPrefersSliderBehavior = source.accessibilityPrefersSliderBehavior
        }
        if target.accessibilityRequiresActivationPoint != source.accessibilityRequiresActivationPoint {
            target.accessibilityRequiresActivationPoint = source.accessibilityRequiresActivationPoint
        }
        if target.accessibilityDirectTouchOptions != source.accessibilityDirectTouchOptions {
            target.accessibilityDirectTouchOptions = source.accessibilityDirectTouchOptions
        }
        if target.accessibilityPrefersCrossFadeTransitions != source.accessibilityPrefersCrossFadeTransitions {
            target.accessibilityPrefersCrossFadeTransitions = source.accessibilityPrefersCrossFadeTransitions
        }
        if target.accessibilityShowLargeContentViewer != source.accessibilityShowLargeContentViewer {
            target.accessibilityShowLargeContentViewer = source.accessibilityShowLargeContentViewer
        }
        if target.symbolVariableValue != source.symbolVariableValue {
            target.symbolVariableValue = source.symbolVariableValue
        }
        if target.symbolRenderingMode != source.symbolRenderingMode {
            target.symbolRenderingMode = source.symbolRenderingMode
        }
        if target.symbolVariants != source.symbolVariants { target.symbolVariants = source.symbolVariants }
        if target.imageResizingMode != source.imageResizingMode { target.imageResizingMode = source.imageResizingMode }
        if target.imageCapInsets != source.imageCapInsets { target.imageCapInsets = source.imageCapInsets }
        if target.imageRenderingMode != source.imageRenderingMode {
            target.imageRenderingMode = source.imageRenderingMode
        }
        if target.imageInterpolation != source.imageInterpolation {
            target.imageInterpolation = source.imageInterpolation
        }
        if target.imageAntialiased != source.imageAntialiased { target.imageAntialiased = source.imageAntialiased }
        if target.keyboardShortcuts != source.keyboardShortcuts { target.keyboardShortcuts = source.keyboardShortcuts }
        if target.interceptsVerticalArrowKeys != source.interceptsVerticalArrowKeys {
            target.interceptsVerticalArrowKeys = source.interceptsVerticalArrowKeys
        }
        if target.textInputSubmitLabel != source.textInputSubmitLabel {
            target.textInputSubmitLabel = source.textInputSubmitLabel
        }
        if let controller = source.textInputController {
            let previous = target.textInputController
            target.textInputController = controller
            controller.reconcile(from: previous, onto: target)
        } else {
            target.textInputController?.detach(from: target)
            target.textInputController = nil
            if target.textInputCaretOffset != source.textInputCaretOffset {
                target.textInputCaretOffset = source.textInputCaretOffset
            }
            if target.textInputSelection != source.textInputSelection {
                target.textInputSelection = source.textInputSelection
            }
        }
        if target.textSelectability != source.textSelectability { target.textSelectability = source.textSelectability }
        if target.textSelectionAffinity != source.textSelectionAffinity {
            target.textSelectionAffinity = source.textSelectionAffinity
        }
        if target.textContentType != source.textContentType { target.textContentType = source.textContentType }
        if target.textInputKeyboardType != source.textInputKeyboardType {
            target.textInputKeyboardType = source.textInputKeyboardType
        }
        if target.textInputCompletion != source.textInputCompletion {
            target.textInputCompletion = source.textInputCompletion
        }
        if target.textInputSuggestions != source.textInputSuggestions {
            target.textInputSuggestions = source.textInputSuggestions
        }
        if target.writingToolsBehavior != source.writingToolsBehavior {
            target.writingToolsBehavior = source.writingToolsBehavior
        }
        if target.writingToolsAffordanceVisibility != source.writingToolsAffordanceVisibility {
            target.writingToolsAffordanceVisibility = source.writingToolsAffordanceVisibility
        }
        if target.textInputDictationBehavior != source.textInputDictationBehavior {
            target.textInputDictationBehavior = source.textInputDictationBehavior
        }
        if target.isFindDisabled != source.isFindDisabled { target.isFindDisabled = source.isFindDisabled }
        if target.isReplaceDisabled != source.isReplaceDisabled { target.isReplaceDisabled = source.isReplaceDisabled }
        if target.isFindNavigatorPresented != source.isFindNavigatorPresented {
            target.isFindNavigatorPresented = source.isFindNavigatorPresented
        }
        if target.isSubmitScopeBoundary != source.isSubmitScopeBoundary {
            target.isSubmitScopeBoundary = source.isSubmitScopeBoundary
        }
        if target.submitScopeTriggersRawValue != source.submitScopeTriggersRawValue {
            target.submitScopeTriggersRawValue = source.submitScopeTriggersRawValue
        }
        if target.isFocusSection != source.isFocusSection { target.isFocusSection = source.isFocusSection }
        if target.prefersDefaultFocus != source.prefersDefaultFocus {
            target.prefersDefaultFocus = source.prefersDefaultFocus
        }
        if target.focusNamespace != source.focusNamespace { target.focusNamespace = source.focusNamespace }
        if target.isGeometryGroup != source.isGeometryGroup { target.isGeometryGroup = source.isGeometryGroup }
        if target.hoverEffect != source.hoverEffect { target.hoverEffect = source.hoverEffect }
        if target.isHoverEffectDisabled != source.isHoverEffectDisabled {
            target.isHoverEffectDisabled = source.isHoverEffectDisabled
        }
        if target.isFocusEffectDisabled != source.isFocusEffectDisabled {
            target.isFocusEffectDisabled = source.isFocusEffectDisabled
        }
        if target.isFocusDestination != source.isFocusDestination {
            target.isFocusDestination = source.isFocusDestination
        }
        if target.isFocusActive != source.isFocusActive { target.isFocusActive = source.isFocusActive }
        if target.isFocusEnabled != source.isFocusEnabled { target.isFocusEnabled = source.isFocusEnabled }
        if target.pointerStyle != source.pointerStyle { target.pointerStyle = source.pointerStyle }
        if target.pointerVisibility != source.pointerVisibility { target.pointerVisibility = source.pointerVisibility }
        if target.digitalCrownRotation != source.digitalCrownRotation {
            target.digitalCrownRotation = source.digitalCrownRotation
        }
        if target.windowDragInteraction != source.windowDragInteraction {
            target.windowDragInteraction = source.windowDragInteraction
        }
        if target.windowResizeInteraction != source.windowResizeInteraction {
            target.windowResizeInteraction = source.windowResizeInteraction
        }
        if target.windowDismissBehavior != source.windowDismissBehavior {
            target.windowDismissBehavior = source.windowDismissBehavior
        }
        if target.windowFullScreenBehavior != source.windowFullScreenBehavior {
            target.windowFullScreenBehavior = source.windowFullScreenBehavior
        }
        if target.windowMinimizeBehavior != source.windowMinimizeBehavior {
            target.windowMinimizeBehavior = source.windowMinimizeBehavior
        }
        if target.windowResizeBehavior != source.windowResizeBehavior {
            target.windowResizeBehavior = source.windowResizeBehavior
        }
        if target.windowCornerRadius != source.windowCornerRadius {
            target.windowCornerRadius = source.windowCornerRadius
        }
        if target.contentShapes != source.contentShapes { target.contentShapes = source.contentShapes }
        if target.buttonRepeatBehavior != source.buttonRepeatBehavior {
            target.buttonRepeatBehavior = source.buttonRepeatBehavior
        }
        if target.redactionReasons != source.redactionReasons { target.redactionReasons = source.redactionReasons }
        if target.isPrivacySensitive != source.isPrivacySensitive {
            target.isPrivacySensitive = source.isPrivacySensitive
        }
        if target.isAccessibilityShowsLargeContentViewer != source.isAccessibilityShowsLargeContentViewer {
            target.isAccessibilityShowsLargeContentViewer = source.isAccessibilityShowsLargeContentViewer
        }
        if target.isAccessibilityQuickActionEnabled != source.isAccessibilityQuickActionEnabled {
            target.isAccessibilityQuickActionEnabled = source.isAccessibilityQuickActionEnabled
        }
        if target.accessibilityQuickActionStyle != source.accessibilityQuickActionStyle {
            target.accessibilityQuickActionStyle = source.accessibilityQuickActionStyle
        }
        if target.isAccessibilityZoomActionEnabled != source.isAccessibilityZoomActionEnabled {
            target.isAccessibilityZoomActionEnabled = source.isAccessibilityZoomActionEnabled
        }
        if target.isAccessibilityScrollActionEnabled != source.isAccessibilityScrollActionEnabled {
            target.isAccessibilityScrollActionEnabled = source.isAccessibilityScrollActionEnabled
        }
        if target.isAccessibilityFocusSection != source.isAccessibilityFocusSection {
            target.isAccessibilityFocusSection = source.isAccessibilityFocusSection
        }
        if target.isAccessibilityImage != source.isAccessibilityImage {
            target.isAccessibilityImage = source.isAccessibilityImage
        }
        if target.accessibilityLinkDestination != source.accessibilityLinkDestination {
            target.accessibilityLinkDestination = source.accessibilityLinkDestination
        }
        if target.accessibilityLinkedGroup != source.accessibilityLinkedGroup {
            target.accessibilityLinkedGroup = source.accessibilityLinkedGroup
        }
        if target.accessibilityPage != source.accessibilityPage { target.accessibilityPage = source.accessibilityPage }
        if target.contextMenuForSelectionType != source.contextMenuForSelectionType {
            target.contextMenuForSelectionType = source.contextMenuForSelectionType
        }
        if target.widgetURL != source.widgetURL { target.widgetURL = source.widgetURL }
        if target.isWidgetAccentable != source.isWidgetAccentable {
            target.isWidgetAccentable = source.isWidgetAccentable
        }
        if target.widgetAccentedRenderingMode != source.widgetAccentedRenderingMode {
            target.widgetAccentedRenderingMode = source.widgetAccentedRenderingMode
        }
        if target.widgetBackgroundStyle != source.widgetBackgroundStyle {
            target.widgetBackgroundStyle = source.widgetBackgroundStyle
        }
        if target.widgetBackgroundPlacement != source.widgetBackgroundPlacement {
            target.widgetBackgroundPlacement = source.widgetBackgroundPlacement
        }
        if target.widgetRelevancy != source.widgetRelevancy { target.widgetRelevancy = source.widgetRelevancy }
        if target.paletteSelectionEffect != source.paletteSelectionEffect {
            target.paletteSelectionEffect = source.paletteSelectionEffect
        }
        if target.paintsInDeferredPhase != source.paintsInDeferredPhase {
            target.paintsInDeferredPhase = source.paintsInDeferredPhase
        }
        if target.matchedGeometryEffect != source.matchedGeometryEffect {
            target.matchedGeometryEffect = source.matchedGeometryEffect
        }
        if target.matchedTransitionSource != source.matchedTransitionSource {
            target.matchedTransitionSource = source.matchedTransitionSource
        }
        if target.navigationTransition != source.navigationTransition {
            target.navigationTransition = source.navigationTransition
        }
        if target.hasAllocatedChartMetadata || source.hasAllocatedChartMetadata {
            if target.chartXAxis != source.chartXAxis { target.chartXAxis = source.chartXAxis }
            if target.chartXScale != source.chartXScale { target.chartXScale = source.chartXScale }
            if target.chartYScale != source.chartYScale { target.chartYScale = source.chartYScale }
            if target.meshGradient != source.meshGradient { target.meshGradient = source.meshGradient }
            if target.chartYAxis != source.chartYAxis { target.chartYAxis = source.chartYAxis }
            if target.chartLegend != source.chartLegend { target.chartLegend = source.chartLegend }
            if target.chartBackground != source.chartBackground { target.chartBackground = source.chartBackground }
            if target.chartPlotStyle != source.chartPlotStyle { target.chartPlotStyle = source.chartPlotStyle }
            if target.chartOverlay != source.chartOverlay { target.chartOverlay = source.chartOverlay }
            if target.chartSelection != source.chartSelection { target.chartSelection = source.chartSelection }
            if target.chartScrollableAxes != source.chartScrollableAxes {
                target.chartScrollableAxes = source.chartScrollableAxes
            }
            if target.chartForegroundStyleScale != source.chartForegroundStyleScale {
                target.chartForegroundStyleScale = source.chartForegroundStyleScale
            }
            if target.chartSymbolSize != source.chartSymbolSize { target.chartSymbolSize = source.chartSymbolSize }
            if target.chartSymbol != source.chartSymbol { target.chartSymbol = source.chartSymbol }
            if target.chartAngleScale != source.chartAngleScale { target.chartAngleScale = source.chartAngleScale }
            if target.chartBackgroundStyleScale != source.chartBackgroundStyleScale {
                target.chartBackgroundStyleScale = source.chartBackgroundStyleScale
            }
            if target.chartSymbolScale != source.chartSymbolScale { target.chartSymbolScale = source.chartSymbolScale }
            if target.chartXVisibleDomain != source.chartXVisibleDomain {
                target.chartXVisibleDomain = source.chartXVisibleDomain
            }
            if target.chartYVisibleDomain != source.chartYVisibleDomain {
                target.chartYVisibleDomain = source.chartYVisibleDomain
            }
            if target.chartXSelection != source.chartXSelection { target.chartXSelection = source.chartXSelection }
            if target.chartYSelection != source.chartYSelection { target.chartYSelection = source.chartYSelection }
            if target.chartAngleSelection != source.chartAngleSelection {
                target.chartAngleSelection = source.chartAngleSelection
            }
            if target.chartScrollPositionX != source.chartScrollPositionX {
                target.chartScrollPositionX = source.chartScrollPositionX
            }
            if target.chartScrollPositionY != source.chartScrollPositionY {
                target.chartScrollPositionY = source.chartScrollPositionY
            }
        }
        if target.tableColumnHeadersVisible != source.tableColumnHeadersVisible {
            target.tableColumnHeadersVisible = source.tableColumnHeadersVisible
        }
        if target.isContentInvalidatable != source.isContentInvalidatable {
            target.isContentInvalidatable = source.isContentInvalidatable
        }
        if target.isLineSelectable != source.isLineSelectable { target.isLineSelectable = source.isLineSelectable }
        if target.accessibilityActivationPoint != source.accessibilityActivationPoint {
            target.accessibilityActivationPoint = source.accessibilityActivationPoint
        }
        if target.accessibilityTextContentType != source.accessibilityTextContentType {
            target.accessibilityTextContentType = source.accessibilityTextContentType
        }
        if target.accessibilityMagicTapAction != nil || source.accessibilityMagicTapAction != nil {
            target.accessibilityMagicTapAction = source.accessibilityMagicTapAction
        }
        if target.presentationChrome != source.presentationChrome {
            target.presentationChrome = source.presentationChrome
        }
        if target.isToolbarContainer != source.isToolbarContainer {
            target.isToolbarContainer = source.isToolbarContainer
        }
        if target.toolbarPlacementTags != source.toolbarPlacementTags {
            target.toolbarPlacementTags = source.toolbarPlacementTags
        }
        if target.menuOrder != source.menuOrder { target.menuOrder = source.menuOrder }
        if target.toolbarTitleMenuChildren != nil || source.toolbarTitleMenuChildren != nil {
            target.toolbarTitleMenuChildren = source.toolbarTitleMenuChildren
        }
        if target.toolbarTitleActionsChildren != nil || source.toolbarTitleActionsChildren != nil {
            target.toolbarTitleActionsChildren = source.toolbarTitleActionsChildren
        }
        if target.accessibilityRepresentationChildren != nil || source.accessibilityRepresentationChildren != nil {
            target.accessibilityRepresentationChildren = source.accessibilityRepresentationChildren
        }
        if target.gestureName != source.gestureName { target.gestureName = source.gestureName }
        if target.textRenderer != nil || source.textRenderer != nil { target.textRenderer = source.textRenderer }
        if target.scenePaddingEdges != source.scenePaddingEdges { target.scenePaddingEdges = source.scenePaddingEdges }
        if target.coordinateSpaceName != source.coordinateSpaceName {
            target.coordinateSpaceName = source.coordinateSpaceName
        }
        if target.sectionHeaderChildCount != source.sectionHeaderChildCount {
            target.sectionHeaderChildCount = source.sectionHeaderChildCount
        }
        if target.sectionFooterChildCount != source.sectionFooterChildCount {
            target.sectionFooterChildCount = source.sectionFooterChildCount
        }
        if !(target.retainedPreferenceValues.isEmpty && source.retainedPreferenceValues.isEmpty) {
            target.retainedPreferenceValues = source.retainedPreferenceValues
        }
        if !(target.retainedPreferenceTransformBoundaries.isEmpty
            && source.retainedPreferenceTransformBoundaries.isEmpty)
        {
            target.retainedPreferenceTransformBoundaries = source.retainedPreferenceTransformBoundaries
        }
        if !(target.retainedLayoutValues.isEmpty && source.retainedLayoutValues.isEmpty) {
            target.retainedLayoutValues = source.retainedLayoutValues
        }
        if !(target.retainedContainerValues.isEmpty && source.retainedContainerValues.isEmpty) {
            target.retainedContainerValues = source.retainedContainerValues
        }
        if target.nodeTag != source.nodeTag { target.nodeTag = source.nodeTag }
        if target.retainedViewIdentity != source.retainedViewIdentity {
            target.retainedViewIdentity = source.retainedViewIdentity
        }
        if target.retainedSubtreeBuildLease != nil || source.retainedSubtreeBuildLease != nil {
            target.retainedSubtreeBuildLease = source.retainedSubtreeBuildLease
        }
        let targetLayoutTag = layoutModeTag(target.layoutMode)
        let sourceLayoutTag = layoutModeTag(source.layoutMode)
        if targetLayoutTag != sourceLayoutTag {
            target.layoutMode = source.layoutMode
        }
        if target.previousPropertyValues != nil || source.previousPropertyValues != nil {
            target.previousPropertyValues = source.previousPropertyValues
        }

        if target.hasAllocatedInteractionHandlers || source.hasAllocatedInteractionHandlers {
            if target.onPointerEnter != nil || source.onPointerEnter != nil {
                target.onPointerEnter = source.onPointerEnter
            }
            if target.onPointerExit != nil || source.onPointerExit != nil {
                target.onPointerExit = source.onPointerExit
            }
            if target.onPointerMove != nil || source.onPointerMove != nil {
                target.onPointerMove = source.onPointerMove
            }
            if target.onPointerDown != nil || source.onPointerDown != nil {
                target.onPointerDown = source.onPointerDown
            }
            if target.onPointerUpInside != nil || source.onPointerUpInside != nil {
                target.onPointerUpInside = source.onPointerUpInside
            }
            if target.onPointerUpInsideAt != nil || source.onPointerUpInsideAt != nil {
                target.onPointerUpInsideAt = source.onPointerUpInsideAt
            }
            if target.onPointerUpOutside != nil || source.onPointerUpOutside != nil {
                target.onPointerUpOutside = source.onPointerUpOutside
            }
            if target.onContextMenu != nil || source.onContextMenu != nil {
                target.onContextMenu = source.onContextMenu
            }
            if target.onFocusEnter != nil || source.onFocusEnter != nil { target.onFocusEnter = source.onFocusEnter }
            if target.onFocusExit != nil || source.onFocusExit != nil { target.onFocusExit = source.onFocusExit }
            if target.onKeyDown != nil || source.onKeyDown != nil { target.onKeyDown = source.onKeyDown }
            if target.onIMEComposition != nil || source.onIMEComposition != nil {
                target.onIMEComposition = source.onIMEComposition
            }
            if target.textInputCaretRectProvider != nil || source.textInputCaretRectProvider != nil {
                target.textInputCaretRectProvider = source.textInputCaretRectProvider
            }
            if target.onKeyUp != nil || source.onKeyUp != nil { target.onKeyUp = source.onKeyUp }
            if target.onActivate != nil || source.onActivate != nil { target.onActivate = source.onActivate }
            if target.onRepeatActivate != nil || source.onRepeatActivate != nil {
                target.onRepeatActivate = source.onRepeatActivate
            }
            if target.longPressGesture != nil || source.longPressGesture != nil {
                target.longPressGesture = source.longPressGesture
            }
        }

        if target.hasAllocatedDropHandlers || source.hasAllocatedDropHandlers {
            if target.onDeleteRows != nil || source.onDeleteRows != nil { target.onDeleteRows = source.onDeleteRows }
            if target.onMoveRows != nil || source.onMoveRows != nil { target.onMoveRows = source.onMoveRows }
            if target.onInsertRows != nil || source.onInsertRows != nil { target.onInsertRows = source.onInsertRows }
            if target.onDropRows != nil || source.onDropRows != nil { target.onDropRows = source.onDropRows }
            if target.onValidateDrop != nil || source.onValidateDrop != nil {
                target.onValidateDrop = source.onValidateDrop
            }
            if target.onDropEntered != nil || source.onDropEntered != nil {
                target.onDropEntered = source.onDropEntered
            }
            if target.onDropUpdated != nil || source.onDropUpdated != nil {
                target.onDropUpdated = source.onDropUpdated
            }
            if target.onDropExited != nil || source.onDropExited != nil { target.onDropExited = source.onDropExited }
            if target.onDropProviders != nil || source.onDropProviders != nil {
                target.onDropProviders = source.onDropProviders
            }
            if target.onDropPayloads != nil || source.onDropPayloads != nil {
                target.onDropPayloads = source.onDropPayloads
            }
            if target.onMakeDropConfiguration != nil || source.onMakeDropConfiguration != nil {
                target.onMakeDropConfiguration = source.onMakeDropConfiguration
            }
            if target.onMakeDragPayload != nil || source.onMakeDragPayload != nil {
                target.onMakeDragPayload = source.onMakeDragPayload
            }
            if target.onMakeDragItemProvider != nil || source.onMakeDragItemProvider != nil {
                target.onMakeDragItemProvider = source.onMakeDragItemProvider
            }
            if target.onDragStart != nil || source.onDragStart != nil { target.onDragStart = source.onDragStart }
            if target.onDragChange != nil || source.onDragChange != nil { target.onDragChange = source.onDragChange }
            if target.onDragEnd != nil || source.onDragEnd != nil { target.onDragEnd = source.onDragEnd }
        }

        if target.hasAllocatedLifecycleHandlers || source.hasAllocatedLifecycleHandlers {
            if target.onLayout != nil || source.onLayout != nil { target.onLayout = source.onLayout }
            if target.onLayoutWithNode != nil || source.onLayoutWithNode != nil {
                target.onLayoutWithNode = source.onLayoutWithNode
            }
            if target.absoluteChildFrame != nil || source.absoluteChildFrame != nil {
                target.absoluteChildFrame = source.absoluteChildFrame
            }
            if target.onAppear != nil || source.onAppear != nil { target.onAppear = source.onAppear }
            if target.onDisappear != nil || source.onDisappear != nil { target.onDisappear = source.onDisappear }
            if target.onAppearWithNode != nil || source.onAppearWithNode != nil {
                target.onAppearWithNode = source.onAppearWithNode
            }
            if target.onDisappearWithNode != nil || source.onDisappearWithNode != nil {
                target.onDisappearWithNode = source.onDisappearWithNode
            }
            if target.onSizeChange != nil || source.onSizeChange != nil { target.onSizeChange = source.onSizeChange }
            // The reader's body and the slot it was built from travel together:
            // `target` has just adopted `source`'s children, so it has also
            // adopted the size they were built against. Splitting them would
            // leave the convergence loop comparing a slot against a body it did
            // not produce, and it would rebuild forever. Guarded as a pair for
            // the same reason: either both move or neither does.
            if target.geometryReaderBuild != nil || source.geometryReaderBuild != nil {
                target.geometryReaderBuild = source.geometryReaderBuild
                target.geometryReaderBuiltSize = source.geometryReaderBuiltSize
            }
        }
        if target.onUpdatePlatformView != nil || source.onUpdatePlatformView != nil {
            target.onUpdatePlatformView = source.onUpdatePlatformView
        }
        if target.onDismantlePlatformView != nil || source.onDismantlePlatformView != nil {
            target.onDismantlePlatformView = source.onDismantlePlatformView
        }
        if target.phaseAnimatorState != nil || source.phaseAnimatorState != nil {
            target.phaseAnimatorState = source.phaseAnimatorState
        }

        if target.hasAppeared, !target.hasPendingAppearanceCallbacks {
            for launch in source.pendingLifecycleTaskLaunches {
                target.launchLifecycleTask(launch)
            }
        } else {
            target.pendingLifecycleTaskLaunches = source.pendingLifecycleTaskLaunches
        }

        target.onUpdatePlatformView?(target)
    }
}
