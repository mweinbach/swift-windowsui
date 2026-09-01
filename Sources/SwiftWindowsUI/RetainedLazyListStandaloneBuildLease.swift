/// Direct View construction has no mounted State owner. Its deferred rows
/// still need one exact accepted physical attachment, not a construction node
/// that reconciliation may discard while retaining a previous container.
@MainActor
final class RetainedLazyListStandaloneBuildLease: RetainedSubtreeBuildLease {
    private weak var runtime: RetainedViewRuntime?
    private weak var adapter: RetainedLazyListRuntimeAdapter?
    private var attachment: RetainedLazyListActualAttachment?
    private var wasRevoked = false

    init(runtime: RetainedViewRuntime, adapter: RetainedLazyListRuntimeAdapter) {
        self.runtime = runtime
        self.adapter = adapter
    }

    /// Called only by the adapter's native claim publication. That publication
    /// precedes the incoming lease property copy during reconciliation, so the
    /// identity of the installed lease is checked by canBuild, not assumed here.
    /// An accepted claim can never be retargeted after its attachment departs.
    func acceptFirstAttachment(to node: ViewNode) -> Bool {
        guard !wasRevoked, attachment == nil,
            let runtime, let adapter, runtime.permitsRetainedActionInvocation,
            node.retainedLazyListRuntime === runtime,
            node.retainedLazyListAdapter === adapter, adapter.ownsAttachment(node)
        else {
            return false
        }
        let actual = node.lazyListActivityStorage().captureActualAttachment(of: node, in: runtime)
        guard actual.isAttached else {
            return false
        }
        attachment = actual
        return true
    }

    /// Native revocation drops no application payload and invokes no callbacks.
    /// Keeping the original proof prevents same-node and same-adapter revival.
    func revoke() { wasRevoked = true }

    var hasCurrentAttachment: Bool {
        guard !wasRevoked, let runtime, let adapter, let attachment, attachment.isAttached,
            let node = attachment.node, runtime.permitsRetainedActionInvocation,
            node.retainedLazyListRuntime === runtime, adapter.ownsAttachment(node),
            node.retainedLazyListAdapter === adapter, node.retainedSubtreeBuildLease === self
        else { return false }
        return true
    }

    var canBuild: Bool { hasCurrentAttachment }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        canBuild ? RetainedLazyListStandaloneBuildEpoch(lease: self) : nil
    }
}

@MainActor
private final class RetainedLazyListStandaloneBuildEpoch: RetainedBuildEpoch {
    private weak var lease: RetainedLazyListStandaloneBuildLease?
    private var didPrepare = false
    private var didFinish = false
    private var wasSuperseded = false

    init(lease: RetainedLazyListStandaloneBuildLease) { self.lease = lease }
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
