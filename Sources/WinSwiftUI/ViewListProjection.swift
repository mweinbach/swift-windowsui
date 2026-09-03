import SwiftWindowsCore
import SwiftWindowsUI

/// Only framework structure exposes stored children here. Custom bodies remain
/// ordinary leaves until the installed-value construction gateway visits them.
@MainActor
protocol ViewListProjectionProvider: View {
    func viewListProjection() -> ViewListProjection
}

enum ViewListIdentityTransition {
    case type(ObjectIdentifier)
    case prefix([RetainedViewIdentity.Segment])
}

@MainActor
indirect enum ViewListProjection {
    case leaf(AnyView)
    case value(AnyView)
    case deferredData(DeferredViewListData)
    case retainedStructure(ViewListProjection, materialize: @MainActor () -> [AnyView])
    case scope(
        ViewListIdentityTransition, excluding: StateMountDeclarationScope.ExcludedChildren?,
        children: [ViewListProjection])
}

/// Projection needs identity data, not a complete environment or mount context.
/// The same transitions feed materialized leaves and current declarations.
struct ViewListIdentityCursor {
    var prefix: [RetainedViewIdentity.Segment] = []
    var currentType: ObjectIdentifier?

    func applying(_ transition: ViewListIdentityTransition) -> ViewListIdentityCursor {
        var result = self
        switch transition {
        case .type(let identifier):
            if identifier != ObjectIdentifier(AnyView.self), identifier != currentType {
                result.prefix.append(.view(identifier))
                result.currentType = identifier
            }
        case .prefix(let segments):
            if !segments.isEmpty {
                result.prefix.append(contentsOf: segments)
                result.currentType = nil
            }
        }
        return result
    }
}

/// A projection operation keeps its original lookup receipt across authored
/// hashing and equality. Reentrant construction cannot make an older walk
/// valid again by replacing the ambient context or advancing its revisions.
@MainActor
final class ViewListProjectionActivity {
    private let context: ViewBuildContext?
    private let lookup: LazyListLookupReceipt?
    private let requiresLookup: Bool
    private var rejected = false

    init(context: ViewBuildContext? = ViewBuildContextScope.current) {
        self.context = context
        if let lazy = context?.viewIdentity.lazyList {
            requiresLookup = true
            lookup = context?.viewIdentity.descriptorComponent == nil ? lazy.admission.beginLookup() : nil
        } else if let descriptor = context?.viewIdentity.descriptorComponent {
            requiresLookup = true
            lookup = context?.stateMountCoordinator?.descriptorLookupReceipt(for: descriptor)
        } else {
            requiresLookup = false
            lookup = nil
        }
    }

    var isCurrent: Bool {
        guard !rejected, context?.viewIdentity.lazyList?.isCurrent != false,
            context?.viewIdentity.descriptorComponent?.canConstruct != false,
            context?.viewIdentity.candidateConstruction?.canConstruct != false,
            !requiresLookup || lookup?.isCurrent == true
        else {
            reject()
            return false
        }
        return true
    }

    func reject() {
        guard !rejected else { return }
        rejected = true
        context?.viewIdentity.lazyList?.admission.reject()
        context?.viewIdentity.descriptorComponent?.rejectConstruction()
    }

    func occurrences(_ views: [AnyView]) -> [AnyView]? {
        let result = collectOccurrences(views)
        return isCurrent ? result : nil
    }

    @inline(never)
    private func collectOccurrences(_ views: [AnyView]) -> [AnyView]? {
        guard isCurrent else { return nil }
        var counts = ManagedKeyedMap<RetainedViewIdentity, Int>()
        var result: [AnyView] = []
        result.reserveCapacity(views.count)
        for (index, source) in views.enumerated() {
            guard isCurrent else { return nil }
            let view = source.ensuringViewIdentitySlot(index)
            let key = RetainedViewIdentity(segments: view.structuralIdentity)
            let occurrence = counts[key, while: { isCurrent }] ?? 0
            guard isCurrent else { return nil }
            counts[key, while: { isCurrent }] = occurrence + 1
            guard isCurrent else { return nil }
            result.append(view.prefixedViewIdentity([.occurrence(occurrence)]))
        }
        return isCurrent ? result : nil
    }
}

@MainActor
func projectedViewList<Value: View>(_ value: Value) -> ViewListProjection {
    // Expansion is shallow. The iterative walker opens each known value only
    // when it reaches that entry, rather than recursively building a full tree.
    .value(AnyView(value))
}

@MainActor
func materializedViewList(
    _ projection: ViewListProjection, startingType: ObjectIdentifier? = nil,
    activity: ViewListProjectionActivity = ViewListProjectionActivity()
) -> [AnyView] {
    var result: [AnyView] = []
    appendMaterializedViewList(projection, startingType: startingType, to: &result, activity: activity)
    return activity.isCurrent ? result : []
}

/// Array-returning canonical builders can retain one opaque framework segment
/// for an entire ForEach. Ordinary consumers expand that segment when they
/// actually construct it; List can inspect its metadata without constructing
/// any model row. Explicit WindowsArrayViewBuilder expressions remain eager.
@MainActor
func projectedViewListPreservingDeferred(_ projection: ViewListProjection) -> [AnyView] {
    let activity = ViewListProjectionActivity()
    let result = collectViewListPreservingDeferred(projection, activity: activity)
    return activity.isCurrent ? result : []
}

@MainActor
@inline(never)
private func collectViewListPreservingDeferred(
    _ projection: ViewListProjection, activity: ViewListProjectionActivity
) -> [AnyView] {
    var result: [AnyView] = []
    var pending = [(projection, ViewListIdentityCursor())]
    while let (next, identity) = pending.popLast() {
        guard activity.isCurrent else { return [] }
        switch next {
        case .leaf(let view):
            result.append(view.prefixedViewIdentity(identity.prefix))
        case .value(let view):
            pending.append((view.viewListProjection(), identity))
        case .deferredData:
            result.append(AnyView(projected: next).prefixedViewIdentity(identity.prefix))
        case .retainedStructure(let deferred, let materialize):
            if viewListProjectionContainsDeferredData(deferred, activity: activity) {
                result.append(AnyView(projected: next).prefixedViewIdentity(identity.prefix))
            } else {
                guard activity.isCurrent, let views = activity.occurrences(materialize()) else { return [] }
                for view in views.reversed() {
                    pending.append((.value(view), identity))
                }
            }
        case .scope(let transition, _, let children):
            let childIdentity = identity.applying(transition)
            for child in children.reversed() { pending.append((child, childIdentity)) }
        }
    }
    return activity.isCurrent ? result : []
}

@MainActor
private func viewListProjectionContainsDeferredData(
    _ projection: ViewListProjection, activity: ViewListProjectionActivity
) -> Bool {
    var pending = [projection]
    while let next = pending.popLast() {
        guard activity.isCurrent else { return false }
        switch next {
        case .leaf:
            break
        case .value(let view):
            pending.append(view.viewListProjection())
        case .deferredData:
            return true
        case .retainedStructure(let deferred, _):
            pending.append(deferred)
        case .scope(_, _, let children):
            pending.append(contentsOf: children)
        }
    }
    return false
}

@MainActor
@inline(never)
private func appendMaterializedViewList(
    _ projection: ViewListProjection, startingType: ObjectIdentifier? = nil, to result: inout [AnyView],
    activity: ViewListProjectionActivity = ViewListProjectionActivity()
) {
    var pending = [(projection, ViewListIdentityCursor(currentType: startingType))]
    while let (next, identity) = pending.popLast() {
        guard activity.isCurrent else {
            result.removeAll()
            return
        }
        switch next {
        case .leaf(let view):
            result.append(view.prefixedViewIdentity(identity.prefix))
        case .value(let view):
            pending.append((view.viewListProjection(), identity))
        case .deferredData(let data):
            guard data.isCurrent, let views = activity.occurrences(data.materializedRows()) else {
                activity.reject()
                result.removeAll()
                return
            }
            for view in views.reversed() {
                pending.append((.value(view), identity))
            }
        case .retainedStructure(_, let materialize):
            guard let views = activity.occurrences(materialize()) else {
                activity.reject()
                result.removeAll()
                return
            }
            for view in views.reversed() {
                pending.append((.value(view), identity))
            }
        case .scope(let transition, _, let children):
            let childIdentity = identity.applying(transition)
            for child in children.reversed() { pending.append((child, childIdentity)) }
        }
    }
    if !activity.isCurrent { result.removeAll() }
}

/// Eager semantic consumers (options, tabs, grid cells, and composition)
/// expand canonical builder carriers at consumption time. Authored arrays and
/// static leaves keep their exact prefixes; this does not normalize them a
/// second time or open arbitrary custom View bodies.
@MainActor
func materializedDeferredViewList(_ views: [AnyView], context: ViewBuildContext) -> [AnyView]? {
    let activity = ViewListProjectionActivity(context: context)
    let result = ViewBuildContextScope.withCurrent(context) {
        collectMaterializedDeferredViewList(views, activity: activity)
    }
    return activity.isCurrent ? result : nil
}

@MainActor
func materializedViewListOccurrences(_ views: [AnyView], context: ViewBuildContext) -> [AnyView]? {
    let activity = ViewListProjectionActivity(context: context)
    let expanded = ViewBuildContextScope.withCurrent(context) {
        collectMaterializedDeferredViewList(views, activity: activity)
    }
    guard activity.isCurrent, let expanded else { return nil }
    let result = activity.occurrences(expanded)
    return activity.isCurrent ? result : nil
}

@MainActor
@inline(never)
private func collectMaterializedDeferredViewList(
    _ views: [AnyView], activity: ViewListProjectionActivity
) -> [AnyView]? {
    var result: [AnyView] = []
    result.reserveCapacity(views.count)
    for view in views {
        guard activity.isCurrent else { return nil }
        if view.isDeferredViewListProjection {
            appendMaterializedViewList(.value(view), to: &result, activity: activity)
        } else {
            result.append(view)
        }
    }
    return activity.isCurrent ? result : nil
}

/// Explicit-return/prebuilt arrays bypass result-builder finalization. Anchor
/// original slots and repeated-fragment occurrences before expanding known
/// values or assigning row metadata. Dropping an empty entry must not renumber
/// a following child's identity, including when both already carry a prefix.
@MainActor
func normalizedProjectedViewList(_ views: [AnyView]) -> [AnyView] {
    let activity = ViewListProjectionActivity()
    guard let views = activity.occurrences(views) else { return [] }
    var result: [AnyView] = []
    result.reserveCapacity(views.count)
    for view in views {
        guard activity.isCurrent else { return [] }
        appendMaterializedViewList(.value(view), to: &result, activity: activity)
    }
    return activity.isCurrent ? result : []
}

/// Explicit-return arrays already bypassed builder finalization. A typed
/// closure uses the same materialization as the historical array result;
/// evaluating either form is deferred until its consumer requests the rows.
@MainActor
func materializedViewBuilderContent<Content: View>(_ content: Content) -> [AnyView] {
    if let views = content as? [AnyView] { return views }
    return materializedViewList(projectedViewList(content))
}

@MainActor
func retainedViewBuilderContent<Content: View>(_ content: Content) -> ViewListProjection {
    if let views = content as? [AnyView] {
        let activity = ViewListProjectionActivity()
        guard let views = activity.occurrences(views), activity.isCurrent else {
            return .scope(.prefix([]), excluding: nil, children: [])
        }
        return .scope(
            .prefix([]), excluding: nil, children: views.map { .value($0) })
    }
    return projectedViewList(content)
}

@MainActor
func declaredProjectedViewListScopes(
    _ projection: ViewListProjection, context: ViewBuildContext
) -> [StateMountDeclarationScope] {
    let activity = ViewListProjectionActivity(context: context)
    let result = collectDeclaredProjectedViewListScopes(projection, context: context, activity: activity)
    return activity.isCurrent ? result : []
}

@MainActor
@inline(never)
private func collectDeclaredProjectedViewListScopes(
    _ projection: ViewListProjection, context: ViewBuildContext, activity: ViewListProjectionActivity
) -> [StateMountDeclarationScope] {
    var result: [StateMountDeclarationScope] = []
    var pending = [(projection, ViewListIdentityCursor(currentType: context.viewIdentity.currentType))]
    while let (next, identity) = pending.popLast() {
        guard activity.isCurrent else { return [] }
        switch next {
        case .leaf(let view):
            result.append(
                contentsOf: view.prefixedViewIdentity(identity.prefix).declaredStateMountScopes(context: context))
        case .value(let view):
            pending.append((view.viewListProjection(), identity))
        case .deferredData(let data):
            guard data.isCurrent else {
                activity.reject()
                return []
            }
            // Inactive alternatives declare model membership, not row bodies.
            // Selected rows contribute their more precise body declarations
            // through the ordinary installed-value construction gateway.
            for element in data.elements {
                guard activity.isCurrent else { return [] }
                result.append(
                    StateMountDeclarationScope(
                        prefix: context.retainedViewIdentity.appending(
                            contentsOf: identity.prefix + [.occurrence(element.occurrence), .keyed(element.key)])))
            }
        case .retainedStructure(let deferred, _):
            pending.append((deferred, identity.applying(.prefix([.occurrence(0)]))))
        case .scope(let transition, let exclusion, let children):
            let childIdentity = identity.applying(transition)
            if let exclusion {
                result.append(
                    StateMountDeclarationScope(
                        prefix: context.retainedViewIdentity.appending(contentsOf: childIdentity.prefix),
                        excluding: exclusion))
            }
            for child in children.reversed() { pending.append((child, childIdentity)) }
        }
    }
    return activity.isCurrent ? result : []
}

/// These leaves already carry their complete relative structural paths. Do not
/// prepend another occurrence edge before their content-role boundary: that
/// would make the declaration exclusion disagree with construction.
@MainActor
func makeProjectedViewListComponent(_ projection: ViewListProjection, context: ViewBuildContext) -> Component {
    let activity = ViewListProjectionActivity(context: context)
    let children = materializedViewList(projection, startingType: context.viewIdentity.currentType, activity: activity)
    guard activity.isCurrent else { return rejectedRetainedViewComponent() }
    if children.count == 1, let child = children.first { return child.makeComponent(context: context) }
    return Component(
        makeViewNode: { runtime in
            Controls.panel(
                isHitTestVisible: false,
                children: children.map { $0.makeComponent(context: context).makeNode(runtime: runtime) })
        },
        appendStructuralChildren: { runtime, nodes in
            for child in children {
                child.makeComponent(context: context).appendChildNodes(runtime: runtime, to: &nodes)
            }
        }
    )
}

extension Array: ViewListProjectionProvider where Element == AnyView {
    func viewListProjection() -> ViewListProjection {
        let activity = ViewListProjectionActivity()
        guard let views = activity.occurrences(self), activity.isCurrent else {
            return .scope(.type(ObjectIdentifier(Self.self)), excluding: .arrayOccurrences, children: [])
        }
        return .scope(
            .type(ObjectIdentifier(Self.self)), excluding: .arrayOccurrences,
            children: views.map { .value($0) })
    }
}

extension Optional: ViewListProjectionProvider where Wrapped: View {
    func viewListProjection() -> ViewListProjection {
        let children: [ViewListProjection]
        switch self {
        case .some(let value):
            children = [.scope(.prefix([.branch(true)]), excluding: nil, children: [projectedViewList(value)])]
        case .none:
            children = []
        }
        return .scope(.type(ObjectIdentifier(Self.self)), excluding: .conditionalBranches, children: children)
    }
}

extension _ConditionalContent: ViewListProjectionProvider {
    func viewListProjection() -> ViewListProjection {
        let child: ViewListProjection
        switch storage {
        case .trueContent(let content):
            child = .scope(.prefix([.branch(true)]), excluding: nil, children: [projectedViewList(content)])
        case .falseContent(let content):
            child = .scope(.prefix([.branch(false)]), excluding: nil, children: [projectedViewList(content)])
        }
        return .scope(.type(ObjectIdentifier(Self.self)), excluding: .conditionalBranches, children: [child])
    }
}

extension EmptyView: ViewListProjectionProvider {
    func viewListProjection() -> ViewListProjection {
        .scope(.type(ObjectIdentifier(Self.self)), excluding: nil, children: [])
    }
}

/// Windows compatibility for a raw [AnyView] expression in a typed builder.
/// Ordinary SwiftUI-shaped expressions do not require this adapter.
@MainActor
public struct _ViewBuilderArrayExpression: View {
    public typealias Body = Never
    let value: [AnyView]

    init(_ value: [AnyView]) { self.value = value }

    public var body: Never { fatalError("The array expression adapter has no body") }

    public func makeComponent(context: ViewBuildContext) -> Component {
        makeProjectedViewListComponent(viewListProjection(), context: context)
    }
}

extension _ViewBuilderArrayExpression: ViewListProjectionProvider {
    func viewListProjection() -> ViewListProjection {
        .scope(
            .type(ObjectIdentifier(Self.self)), excluding: .modifierContent,
            children: [
                .scope(.prefix([.role(.content)]), excluding: nil, children: [value.viewListProjection()])
            ])
    }
}

/// Windows compatibility for the existing ViewBuilder for-loop extension.
@MainActor
public struct _ViewBuilderLoopContent<Content: View>: View {
    public typealias Body = Never
    let value: [Content]

    init(_ value: [Content]) { self.value = value }

    public var body: Never { fatalError("The loop content adapter has no body") }

    public func makeComponent(context: ViewBuildContext) -> Component {
        makeProjectedViewListComponent(viewListProjection(), context: context)
    }
}

extension _ViewBuilderLoopContent: ViewListProjectionProvider {
    func viewListProjection() -> ViewListProjection {
        let children = value.enumerated().map { index, child in
            ViewListProjection.scope(
                .prefix([.iteration(index)]), excluding: nil, children: [projectedViewList(child)])
        }
        return .scope(
            .type(ObjectIdentifier(Self.self)), excluding: .modifierContent,
            children: [.scope(.prefix([.role(.content)]), excluding: nil, children: children)])
    }
}

/// Return-context compatibility for the historical raw-array expression helper.
/// This underscored protocol is a Windows extension, not a native SwiftUI API.
@MainActor
public protocol _ViewBuilderArrayExpressionResult {
    static func _fromViewBuilderArrayExpression(_ value: [AnyView]) -> Self
}

extension Array: _ViewBuilderArrayExpressionResult where Element == AnyView {
    public static func _fromViewBuilderArrayExpression(_ value: [AnyView]) -> [AnyView] {
        viewIdentityOccurrences(value)
    }
}
