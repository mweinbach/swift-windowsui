/// A deferred keyboard controller needs the actual retained List, not the
/// temporary construction node that supplied its adapter. This native binding
/// captures that one attachment at claim publication and never follows a later
/// owner. It grants no construction, selection, focus, or provider authority.
@MainActor
package final class RetainedLazyListNavigationContainer {
    private weak var runtime: RetainedViewRuntime?
    private weak var adapter: RetainedLazyListRuntimeAdapter?
    private let closeWitness: RetainedLazyListLogicalHostLifetime.CloseWitness
    private var attachment: RetainedLazyListActualAttachment?
    private var wasRevoked = false

    init(runtime: RetainedViewRuntime, adapter: RetainedLazyListRuntimeAdapter) {
        self.runtime = runtime
        self.adapter = adapter
        closeWitness = runtime.lazyListLogicalHostLifetime.captureNavigationCloseWitness()
    }

    /// A provisional managed claim may precede membership. Its repeated native
    /// publication may complete this first capture, but never refresh an old
    /// actual attachment or accept a different runtime after weak expiry.
    func didClaimAttachment(to node: ViewNode) {
        guard !wasRevoked, attachment == nil, closeWitness.isOpen,
            let runtime, let adapter, runtime.permitsRetainedActionInvocation,
            node.retainedLazyListRuntime === runtime,
            node.retainedLazyListAdapter === adapter, adapter.ownsAttachment(node)
        else { return }
        let actual = node.lazyListActivityStorage().captureActualAttachment(of: node, in: runtime)
        guard actual.isAttached else { return }
        attachment = actual
    }

    /// Failed foreign or provisional claims have no accepted lifetime to
    /// revoke. Once accepted, even release/reinstall on the same node is final.
    func revokeAttachment(from node: ViewNode) {
        if attachment?.node === node { wasRevoked = true }
    }

    /// Only reads the original proof. Navigation receipts still validate the
    /// declaration, binding, and endpoints before any application callback.
    package var node: ViewNode? {
        guard !wasRevoked, closeWitness.isOpen, let adapter, let attachment,
            attachment.hasCurrentStandaloneNavigationIdentity, let node = attachment.node,
            adapter.ownsAttachment(node), node.retainedLazyListAdapter === adapter,
            adapter.permitsStandaloneNavigation
        else { return nil }
        if let runtime {
            guard runtime.permitsRetainedActionInvocation,
                node.retainedLazyListRuntime === runtime, attachment.isAttached
            else { return nil }
        } else {
            // Preserve realized returned-tree navigation after plain expiry.
            // The original proof and close witness still reject departure,
            // replacement, explicit closure, and a later runtime assignment.
            guard node.retainedLazyListRuntime == nil else { return nil }
        }
        return node
    }
}
