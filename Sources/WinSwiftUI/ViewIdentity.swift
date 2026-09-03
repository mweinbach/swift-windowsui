import SwiftWindowsCore
import SwiftWindowsUI

/// Identity and the local installation receipt of one concrete occurrence.
struct ViewIdentityContext {
    var path = RetainedViewIdentity()
    var currentType: ObjectIdentifier?
    var installedOwner: StateMountOwner?
    // The active build owns this installation receipt through commit and
    // terminal callbacks. Deferred component contexts must not keep a
    // completed epoch alive after those owners have finished.
    weak var installedEpoch: StateMountEpoch?
    var lazyList: LazyListViewAttribution?
    var descriptorComponent: RetainedDescriptorComponentAttribution?
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
extension TupleView: TransparentStateMountView {}
extension _ViewBuilderArrayExpression: TransparentStateMountView {}
extension _ViewBuilderLoopContent: TransparentStateMountView {}

extension AnyView: ViewListProjectionProvider {}
extension TupleView: ViewListProjectionProvider {}

/// A declared, unevaluated alternative can preserve a previous mount without
/// running its body. Known modifier chains include their explicit identity.
@MainActor
protocol StateMountDeclarationView {
    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope]
}

extension AnyView: StateMountDeclarationView {}

extension TupleView: StateMountDeclarationView {
    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        declaredProjectedViewListScopes(viewListProjection(), context: context)
    }
}

extension _ViewBuilderArrayExpression: StateMountDeclarationView {
    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        declaredProjectedViewListScopes(viewListProjection(), context: context)
    }
}

extension _ViewBuilderLoopContent: StateMountDeclarationView {
    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        declaredProjectedViewListScopes(viewListProjection(), context: context)
    }
}

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
        guard
            let occurrences = viewIdentityOccurrences(
                self, lazyAttribution: context.viewIdentity.lazyList,
                descriptorAttribution: context.viewIdentity.descriptorComponent,
                coordinator: context.stateMountCoordinator)
        else { return [] }
        return [StateMountDeclarationScope(prefix: context.retainedViewIdentity, excluding: .arrayOccurrences)]
            + occurrences.flatMap { $0.declaredStateMountScopes(context: context) }
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
    if let attribution = context.viewIdentity.lazyList {
        guard context.viewIdentity.descriptorComponent == nil, attribution.isCurrent else {
            return unavailableLazyViewComponent()
        }
        if !isInstalledDelegate, !(Value.self is any TransparentStateMountView.Type) {
            guard let coordinator = context.stateMountCoordinator,
                let child = coordinator.childLazyAttribution(from: attribution), child.isCurrent
            else {
                return unavailableLazyViewComponent()
            }
            scopedContext.viewIdentity.lazyList = child
        }
        scopedContext.viewIdentity.descriptorComponent = nil
    } else if !(Value.self is any TransparentStateMountView.Type), let coordinator = context.stateMountCoordinator {
        guard
            let described = coordinator.contextForDescriptorComponent(
                from: scopedContext, isInstalledDelegate: isInstalledDelegate)
        else { return unavailableLazyViewComponent() }
        scopedContext = described
    }
    let installed: Value
    if !(Value.self is any TransparentStateMountView.Type), let coordinator = context.stateMountCoordinator {
        guard let copy = coordinator.install(source, context: &scopedContext, isInstalledDelegate: isInstalledDelegate)
        else {
            if scopedContext.viewIdentity.lazyList != nil || scopedContext.viewIdentity.descriptorComponent != nil {
                return rejectedRetainedViewComponent()
            }
            return Component { _ in Controls.panel(preferredSize: .zero, isHitTestVisible: false) }
        }
        installed = copy
    } else {
        installed = source
    }
    if let attribution = scopedContext.viewIdentity.lazyList, !attribution.isCurrent {
        return unavailableLazyViewComponent()
    }
    if let attribution = scopedContext.viewIdentity.descriptorComponent, !attribution.canConstruct {
        return unavailableLazyViewComponent()
    }
    let component = ViewBuildContextScope.withCurrent(scopedContext) { build(installed, scopedContext) }
    if let attribution = scopedContext.viewIdentity.lazyList, !attribution.isCurrent {
        return unavailableLazyViewComponent()
    }
    if let attribution = scopedContext.viewIdentity.descriptorComponent, !attribution.canConstruct {
        return unavailableLazyViewComponent()
    }
    return preservingViewIdentity(of: component, context: scopedContext)
}

@MainActor
private func unavailableLazyViewComponent() -> Component {
    rejectedRetainedViewComponent()
}

/// Transparent views may return their child's node. Keep its more specific
/// identity instead of replacing it with a parent path that omits a branch.
@MainActor
func preservingViewIdentity(of component: Component, context: ViewBuildContext) -> Component {
    if let attribution = context.viewIdentity.lazyList {
        return preservingAttributedViewIdentity(of: component, context: context, activity: .lazy(attribution))
    }
    if let attribution = context.viewIdentity.descriptorComponent {
        return preservingAttributedViewIdentity(of: component, context: context, activity: .descriptor(attribution))
    }
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

@MainActor
private func preservingAttributedViewIdentity(
    of component: Component, context: ViewBuildContext, activity: ViewIdentitySourceActivity
) -> Component {
    let makeNode: @MainActor (RetainedViewRuntime) -> ViewNode = { runtime in
        guard activity.isCurrent, let group = activity.registerGroup(), activity.isCurrent
        else { return activity.rejectedNode() }
        let node = ViewBuildContextScope.withCurrent(context) { component.makeNode(runtime: runtime) }
        guard activity.isCurrent else { return activity.rejectedNode() }
        if node.retainedViewIdentity == nil { node.retainedViewIdentity = context.retainedViewIdentity }
        guard activity.recordSourceOutput(node, group: group), activity.isCurrent,
            activity.closeGroup(group), activity.isCurrent
        else { return activity.rejectedNode() }
        return node
    }
    guard component.hasStructuralChildren else { return Component(makeViewNode: makeNode) }
    return Component(
        makeViewNode: makeNode,
        appendStructuralChildren: { runtime, nodes in
            guard activity.isCurrent, let group = activity.registerGroup(), activity.isCurrent
            else {
                nodes.append(activity.rejectedNode())
                return
            }
            // A rejected component cannot leave already appended outputs in
            // its parent's array while that independent parent is still live.
            var produced: [ViewNode] = []
            ViewBuildContextScope.withCurrent(context) {
                component.appendChildNodes(runtime: runtime, to: &produced)
            }
            guard activity.isCurrent else {
                nodes.append(activity.rejectedNode())
                return
            }
            for index in produced.indices where produced[index].retainedViewIdentity == nil {
                let scope = context.retainedViewIdentity.appending(.role(.content))
                if let tag = produced[index].nodeTag {
                    produced[index].retainedViewIdentity = scope.appending(.keyed(.init(tag)))
                } else {
                    produced[index].retainedViewIdentity = scope.appending(.slot(index))
                }
            }
            for node in produced {
                guard activity.recordSourceOutput(node, group: group), activity.isCurrent else {
                    nodes.append(activity.rejectedNode())
                    return
                }
            }
            guard activity.closeGroup(group), activity.isCurrent else {
                nodes.append(activity.rejectedNode())
                return
            }
            nodes.append(contentsOf: produced)
        }
    )
}

@MainActor
private enum ViewIdentitySourceActivity {
    case lazy(LazyListViewAttribution)
    case descriptor(RetainedDescriptorComponentAttribution)

    var isCurrent: Bool {
        switch self {
        case .lazy(let attribution): return attribution.isCurrent
        case .descriptor(let attribution): return attribution.canConstruct
        }
    }

    func rejectedNode() -> ViewNode {
        reject()
        return rejectedRetainedViewNode()
    }

    func reject() {
        switch self {
        case .lazy(let attribution):
            attribution.admission.reject()
            attribution.native.rejectComponent()
        case .descriptor(let attribution): attribution.rejectComponent()
        }
    }

    func registerGroup() -> ViewIdentitySourceGroup? {
        switch self {
        case .lazy(let attribution):
            return attribution.native.registerGroup(kind: .structure).map(ViewIdentitySourceGroup.lazy)
        case .descriptor(let attribution):
            return attribution.registerGroup(kind: .structure).map(ViewIdentitySourceGroup.descriptor)
        }
    }

    func recordSourceOutput(_ node: ViewNode, group: ViewIdentitySourceGroup) -> Bool {
        switch (self, group) {
        case (.lazy(let attribution), .lazy(let group)):
            return attribution.native.recordSourceOutput(node, group: group) != nil
        case (.descriptor(let attribution), .descriptor(let group)):
            return attribution.recordSourceOutput(node, group: group)
        default: return false
        }
    }

    func closeGroup(_ group: ViewIdentitySourceGroup) -> Bool {
        switch (self, group) {
        case (.lazy(let attribution), .lazy(let group)): return attribution.native.closeGroup(group) != nil
        case (.descriptor(let attribution), .descriptor(let group)): return attribution.closeGroup(group) != nil
        default: return false
        }
    }
}

private enum ViewIdentitySourceGroup {
    case lazy(RetainedLazyListGroupID)
    case descriptor(RetainedDescriptorGroupID)
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
    // Shallow framework projection helpers do not all take a context argument.
    // Their convenience entry must still inherit the original managed build,
    // rather than entering an unguarded dictionary from inside a guarded walk.
    if let context = ViewBuildContextScope.current,
        context.viewIdentity.lazyList != nil || context.viewIdentity.descriptorComponent != nil
    {
        return viewIdentityOccurrences(
            views, lazyAttribution: context.viewIdentity.lazyList,
            descriptorAttribution: context.viewIdentity.descriptorComponent,
            coordinator: context.stateMountCoordinator) ?? []
    }
    return ordinaryViewIdentityOccurrences(views)
}

@MainActor
private func ordinaryViewIdentityOccurrences(_ views: [AnyView]) -> [AnyView] {
    var occurrences: [RetainedViewIdentity: Int] = [:]
    return views.enumerated().map { index, view in
        let view = view.ensuringViewIdentitySlot(index)
        let identity = RetainedViewIdentity(segments: view.structuralIdentity)
        let occurrence = occurrences[identity, default: 0]
        occurrences[identity] = occurrence + 1
        return view.prefixedViewIdentity([.occurrence(occurrence)])
    }
}

/// Attributed composition retains one original operation receipt across authored
/// key hashing, equality and local-map cleanup. It cannot retry against a new
/// revision and publish over a nested installation performed by that lookup.
@MainActor
func viewIdentityOccurrences(
    _ views: [AnyView], lazyAttribution: LazyListViewAttribution?,
    descriptorAttribution: RetainedDescriptorComponentAttribution? = nil, coordinator: StateMountCoordinator? = nil
) -> [AnyView]? {
    let activity: ViewIdentitySourceActivity
    let lookup: LazyListLookupReceipt
    if let attribution = lazyAttribution {
        guard descriptorAttribution == nil else {
            attribution.admission.reject()
            descriptorAttribution?.rejectConstruction()
            return nil
        }
        activity = .lazy(attribution)
        guard attribution.isCurrent, let original = attribution.admission.beginLookup() else {
            activity.reject()
            return nil
        }
        lookup = original
    } else if let attribution = descriptorAttribution {
        activity = .descriptor(attribution)
        guard attribution.canConstruct, let original = coordinator?.descriptorLookupReceipt(for: attribution) else {
            activity.reject()
            return nil
        }
        lookup = original
    } else {
        return ordinaryViewIdentityOccurrences(views)
    }
    let result = makeAttributedViewIdentityOccurrences(views, lookup: lookup)
    guard let result, lookup.isCurrent, activity.isCurrent else {
        activity.reject()
        return nil
    }
    return result
}

@MainActor
@inline(never)
private func makeAttributedViewIdentityOccurrences(
    _ views: [AnyView], lookup: LazyListLookupReceipt
) -> [AnyView]? {
    var occurrences: ManagedKeyedMap<RetainedViewIdentity, Int> = [:]
    var result: [AnyView] = []
    result.reserveCapacity(views.count)
    defer { withExtendedLifetime((views, occurrences)) {} }
    for (index, source) in views.enumerated() {
        guard lookup.isCurrent else { return nil }
        let view = source.ensuringViewIdentitySlot(index)
        let identity = RetainedViewIdentity(segments: view.structuralIdentity)
        let occurrence = occurrences[identity, while: { lookup.isCurrent }] ?? 0
        guard lookup.isCurrent else { return nil }
        occurrences[identity, while: { lookup.isCurrent }] = occurrence + 1
        guard lookup.isCurrent else { return nil }
        result.append(view.prefixedViewIdentity([.occurrence(occurrence)]))
    }
    return result
}
