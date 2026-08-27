extension RetainedViewRuntime {
    /// The enclosing declaration wins over declarations inside its subtree.
    /// Without one, use the first declaration in source tree order. This is
    /// deterministic for retained windows; conflicting sibling declarations
    /// still require native SwiftUI reference qualification.
    ///
    /// Read the live tree instead of caching the first built value: conditional
    /// removal and reconciliation must immediately restore the scene default.
    /// Removal-transition overlays are not part of this tree.
    public var windowDismissalBehavior: RetainedWindowInteractionBehavior {
        var pending = [root]
        while let node = pending.popLast() {
            if let behavior = node.windowDismissBehavior {
                return behavior
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return .automatic
    }
}
