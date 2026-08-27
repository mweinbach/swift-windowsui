import SwiftWindowsCore
import SwiftWindowsUI

/// Identity carried by one concrete build occurrence. This contains no state
/// cells or lifetime registry; a later installation stage can use the same path.
struct ViewIdentityContext {
    var path = RetainedViewIdentity()
    var currentType: ObjectIdentifier?
}

extension ViewBuildContext {
    var retainedViewIdentity: RetainedViewIdentity { viewIdentity.path }

    func withViewIdentityType<Value>(_ type: Value.Type) -> ViewBuildContext {
        let identifier = ObjectIdentifier(type)
        guard identifier != ObjectIdentifier(AnyView.self) else { return self }
        guard viewIdentity.currentType != identifier else { return self }
        var context = self
        context.viewIdentity.path = viewIdentity.path.appending(.view(identifier))
        context.viewIdentity.currentType = identifier
        return context
    }

    func withViewIdentityRole(_ role: RetainedViewIdentity.Role) -> ViewBuildContext {
        withViewIdentityPrefix([.role(role)])
    }

    func withViewIdentityPrefix(_ prefix: [RetainedViewIdentity.Segment]) -> ViewBuildContext {
        guard !prefix.isEmpty else { return self }
        var context = self
        context.viewIdentity.path = viewIdentity.path.appending(contentsOf: prefix)
        context.viewIdentity.currentType = nil
        return context
    }
}

/// The common typed dispatch point for erased views and ordinary body traversal.
/// Installation is deliberately not enabled here yet.
@MainActor
func makeViewComponent<Value: View>(_ view: Value, context: ViewBuildContext) -> Component {
    let scopedContext = context.withViewIdentityType(Value.self)
    let component = ViewBuildContextScope.withCurrent(scopedContext) {
        view.makeComponent(context: scopedContext)
    }
    return preservingViewIdentity(of: component, context: scopedContext)
}

/// Transparent views may return their child's node. Keep its more specific
/// identity instead of replacing it with a parent path that omits a branch.
@MainActor
func preservingViewIdentity(of component: Component, context: ViewBuildContext) -> Component {
    Component { runtime in
        let node = component.makeNode(runtime: runtime)
        if node.retainedViewIdentity == nil {
            node.retainedViewIdentity = context.retainedViewIdentity
        }
        return node
    }
}

extension AnyView {
    func prefixedViewIdentity(_ prefix: [RetainedViewIdentity.Segment]) -> AnyView {
        var view = self
        view.structuralIdentity = prefix + structuralIdentity
        return view
    }

    /// Explicitly supplied arrays do not necessarily pass through buildBlock.
    /// Supply their positional slot only when a builder/key has not done so.
    func ensuringViewIdentitySlot(_ index: Int) -> AnyView {
        structuralIdentity.isEmpty ? prefixedViewIdentity([.slot(index)]) : self
    }

    /// Framework decoration must keep the fragment's identity at its outer
    /// occurrence boundary, where an enclosing builder can distinguish rows.
    func mappingViewIdentity(_ transform: (AnyView) -> AnyView) -> AnyView {
        var content = self
        content.structuralIdentity = []
        return transform(content).prefixedViewIdentity(structuralIdentity)
    }
}

/// Distinguish repeated prebuilt fragments without adding a flattened row index
/// to unique keyed entries. An ordinal is local to the complete relative path.
@MainActor
func viewIdentityOccurrences(_ views: [AnyView]) -> [AnyView] {
    var occurrences: [RetainedViewIdentity: Int] = [:]
    return views.enumerated().map { index, view in
        let view = view.ensuringViewIdentitySlot(index)
        let identity = RetainedViewIdentity(segments: view.structuralIdentity)
        let occurrence = occurrences[identity, default: 0]
        occurrences[identity] = occurrence + 1
        return view.prefixedViewIdentity([.occurrence(occurrence)])
    }
}
