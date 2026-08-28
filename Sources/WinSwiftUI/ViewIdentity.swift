import SwiftWindowsCore
import SwiftWindowsUI

/// Identity and the local installation receipt of one concrete occurrence.
struct ViewIdentityContext {
    var path = RetainedViewIdentity()
    var currentType: ObjectIdentifier?
    var installedOwner: StateMountOwner?
    var installedEpoch: StateMountEpoch?
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
        context.viewIdentity.installedOwner = nil
        context.viewIdentity.installedEpoch = nil
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
        context.viewIdentity.installedOwner = nil
        context.viewIdentity.installedEpoch = nil
        return context
    }
}

/// Known structural containers delegate to concrete occurrences. In particular,
/// an Optional enum is not itself an independently installed custom view.
protocol TransparentStateMountView {}
extension AnyView: TransparentStateMountView {}
extension Array: TransparentStateMountView where Element == AnyView {}
extension Optional: TransparentStateMountView where Wrapped: View {}

/// A declared, unevaluated alternative can preserve a previous mount without
/// running its body. Known modifier chains include their explicit identity.
@MainActor
protocol StateMountDeclarationView {
    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope]
}

extension AnyView: StateMountDeclarationView {}

extension ModifiedView: StateMountDeclarationView {
    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        var scopedContext = context.withViewIdentityType(Self.self)
        var scopes = [
            StateMountDeclarationScope(prefix: scopedContext.retainedViewIdentity, excluding: .modifierContent)
        ]
        if let explicitViewIdentity {
            scopedContext = scopedContext.withViewIdentityPrefix([.explicit(explicitViewIdentity)])
            scopes.append(
                StateMountDeclarationScope(prefix: scopedContext.retainedViewIdentity, excluding: .modifierContent))
        }
        return scopes
            + resolveDeclaredStateMountScopes(
                of: content, context: scopedContext.withViewIdentityRole(.content))
    }
}

extension Optional: StateMountDeclarationView where Wrapped: View {
    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        let context = context.withViewIdentityType(Self.self)
        let scope = StateMountDeclarationScope(prefix: context.retainedViewIdentity, excluding: .conditionalBranches)
        switch self {
        case .some(let wrapped):
            return [scope]
                + resolveDeclaredStateMountScopes(
                    of: wrapped, context: context.withViewIdentityPrefix([.branch(true)]))
        case .none:
            return [scope]
        }
    }
}

extension _ConditionalContent: StateMountDeclarationView {
    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        let context = context.withViewIdentityType(Self.self)
        let scope = StateMountDeclarationScope(prefix: context.retainedViewIdentity, excluding: .conditionalBranches)
        switch storage {
        case .trueContent(let content):
            return [scope]
                + resolveDeclaredStateMountScopes(
                    of: content, context: context.withViewIdentityPrefix([.branch(true)]))
        case .falseContent(let content):
            return [scope]
                + resolveDeclaredStateMountScopes(
                    of: content, context: context.withViewIdentityPrefix([.branch(false)]))
        }
    }
}

extension Array: StateMountDeclarationView where Element == AnyView {
    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        let context = context.withViewIdentityType(Self.self)
        return [StateMountDeclarationScope(prefix: context.retainedViewIdentity, excluding: .arrayOccurrences)]
            + viewIdentityOccurrences(self).flatMap { $0.declaredStateMountScopes(context: context) }
    }
}

@MainActor
func resolveDeclaredStateMountScopes<Value: View>(
    of view: Value, context: ViewBuildContext
) -> [StateMountDeclarationScope] {
    let scopedContext = context.withViewIdentityType(Value.self)
    if Value.self is any StateMountDeclarationView.Type, let declaration = view as? any StateMountDeclarationView {
        return declaration.declaredStateMountScopes(context: scopedContext)
    }
    return [StateMountDeclarationScope(prefix: scopedContext.retainedViewIdentity)]
}

/// The common typed dispatch point for erased views and ordinary body traversal.
@MainActor
func makeViewComponent<Value: View>(_ view: Value, context: ViewBuildContext) -> Component {
    withInstalledViewValue(view, context: context) { installed, scopedContext in
        installed.makeComponent(context: scopedContext)
    }
}

@MainActor
func withInstalledViewValue<Value>(
    _ source: Value, context: ViewBuildContext,
    isInstalledDelegate: Bool = false,
    build: (Value, ViewBuildContext) -> Component
) -> Component {
    var scopedContext = context.withViewIdentityType(Value.self)
    let installed: Value
    if !(Value.self is any TransparentStateMountView.Type), let coordinator = context.stateMountCoordinator {
        guard let copy = coordinator.install(source, context: &scopedContext, isInstalledDelegate: isInstalledDelegate)
        else {
            return Component { _ in Controls.panel(preferredSize: .zero, isHitTestVisible: false) }
        }
        installed = copy
    } else {
        installed = source
    }
    let component = ViewBuildContextScope.withCurrent(scopedContext) { build(installed, scopedContext) }
    return preservingViewIdentity(of: component, context: scopedContext)
}

/// Transparent views may return their child's node. Keep its more specific
/// identity instead of replacing it with a parent path that omits a branch.
@MainActor
func preservingViewIdentity(of component: Component, context: ViewBuildContext) -> Component {
    let makeNode: @MainActor (RetainedViewRuntime) -> ViewNode = { runtime in
        let node = ViewBuildContextScope.withCurrent(context) { component.makeNode(runtime: runtime) }
        if node.retainedViewIdentity == nil {
            node.retainedViewIdentity = context.retainedViewIdentity
        }
        return node
    }
    guard component.hasStructuralChildren else {
        return Component(makeViewNode: makeNode)
    }
    return Component(
        makeViewNode: makeNode,
        appendStructuralChildren: { runtime, nodes in
            let firstNewIndex = nodes.count
            ViewBuildContextScope.withCurrent(context) {
                component.appendChildNodes(runtime: runtime, to: &nodes)
            }
            for index in firstNewIndex..<nodes.count where nodes[index].retainedViewIdentity == nil {
                // Raw structural producers retain their keys within this
                // owner. Untagged children keep their local positional slot;
                // existing typed child identities never pass through here.
                let scope = context.retainedViewIdentity.appending(.role(.content))
                if let tag = nodes[index].nodeTag {
                    nodes[index].retainedViewIdentity = scope.appending(.keyed(.init(tag)))
                } else {
                    nodes[index].retainedViewIdentity = scope.appending(.slot(index - firstNewIndex))
                }
            }
        }
    )
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

extension AnyView: TaggedViewMetadata {
    var anySelectionTag: AnyHashable? { selectionTag }
    var anyTabItem: [AnyView]? { tabItem }
    var anyBadge: [AnyView]? { badge }
    var anyNavigationTitle: [AnyView]? { navigationTitle }
    var anyNavigationSubtitle: [AnyView]? { navigationSubtitle }
    var anyNavigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? { navigationTitleDisplayMode }
    var anyNavigationBarBackButtonHidden: Bool? { navigationBarBackButtonHidden }
    var anyNavigationBarHidden: Bool? { navigationBarHidden }
    var anyToolbarItemPlacement: ToolbarItemPlacement? { toolbarItemPlacement }
    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] {
        navigationDestinationRegistrations
    }
    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] { navigationPresentedDestinations }
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
