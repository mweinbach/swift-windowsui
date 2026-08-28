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
    case scope(
        ViewListIdentityTransition, excluding: StateMountDeclarationScope.ExcludedChildren?,
        children: [ViewListProjection])
}

/// Projection needs identity data, not a complete environment or mount context.
/// The same transitions feed materialized leaves and current declarations.
private struct ViewListIdentityCursor {
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

@MainActor
func projectedViewList<Value: View>(_ value: Value) -> ViewListProjection {
    // Expansion is shallow. The iterative walker opens each known value only
    // when it reaches that entry, rather than recursively building a full tree.
    .value(AnyView(value))
}

@MainActor
func materializedViewList(
    _ projection: ViewListProjection, startingType: ObjectIdentifier? = nil
) -> [AnyView] {
    var result: [AnyView] = []
    appendMaterializedViewList(projection, startingType: startingType, to: &result)
    return result
}

@MainActor
private func appendMaterializedViewList(
    _ projection: ViewListProjection, startingType: ObjectIdentifier? = nil, to result: inout [AnyView]
) {
    var pending = [(projection, ViewListIdentityCursor(currentType: startingType))]
    while let (next, identity) = pending.popLast() {
        switch next {
        case .leaf(let view):
            result.append(view.prefixedViewIdentity(identity.prefix))
        case .value(let view):
            pending.append((view.viewListProjection(), identity))
        case .scope(let transition, _, let children):
            let childIdentity = identity.applying(transition)
            for child in children.reversed() { pending.append((child, childIdentity)) }
        }
    }
}

/// Explicit-return/prebuilt arrays bypass result-builder finalization. Anchor
/// original slots and repeated-fragment occurrences before expanding known
/// values or assigning row metadata. Dropping an empty entry must not renumber
/// a following child's identity, including when both already carry a prefix.
@MainActor
func normalizedProjectedViewList(_ views: [AnyView]) -> [AnyView] {
    var result: [AnyView] = []
    result.reserveCapacity(views.count)
    for view in viewIdentityOccurrences(views) { appendMaterializedViewList(.value(view), to: &result) }
    return result
}

@MainActor
func declaredProjectedViewListScopes(
    _ projection: ViewListProjection, context: ViewBuildContext
) -> [StateMountDeclarationScope] {
    var result: [StateMountDeclarationScope] = []
    var pending = [(projection, ViewListIdentityCursor(currentType: context.viewIdentity.currentType))]
    while let (next, identity) = pending.popLast() {
        switch next {
        case .leaf(let view):
            result.append(
                contentsOf: view.prefixedViewIdentity(identity.prefix).declaredStateMountScopes(context: context))
        case .value(let view):
            pending.append((view.viewListProjection(), identity))
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
    return result
}

/// These leaves already carry their complete relative structural paths. Do not
/// prepend another occurrence edge before their content-role boundary: that
/// would make the declaration exclusion disagree with construction.
@MainActor
func makeProjectedViewListComponent(_ projection: ViewListProjection, context: ViewBuildContext) -> Component {
    let children = materializedViewList(projection, startingType: context.viewIdentity.currentType)
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
        .scope(
            .type(ObjectIdentifier(Self.self)), excluding: .arrayOccurrences,
            children: viewIdentityOccurrences(self).map { .value($0) })
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
