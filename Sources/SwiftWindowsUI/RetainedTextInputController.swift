/// Reconciliation bridge for a retained text editor's interaction state.
/// The compatibility layer supplies current bindings and editing behavior;
/// the runtime owns the surviving node and its attachment lifetime.
@MainActor
public protocol RetainedTextInputController: AnyObject {
    /// Rebinds an existing controller when its node enters a runtime.
    func attach(to node: ViewNode)

    /// Adopts fresh configuration without replacing live editing state.
    /// Called before the new callbacks and child nodes are reconciled.
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode)

    /// Ends history ownership before focus-exit callbacks can replay a node
    /// that is about to leave the runtime, without suppressing those callbacks.
    func willDetach(from node: ViewNode)

    /// Prevents an interrupted callback from editing a removed control.
    func detach(from node: ViewNode)
}

extension RetainedTextInputController {
    public func willDetach(from node: ViewNode) {}
}
