/// Explicit array authoring for the Windows compatibility layer.
///
/// Every expression becomes `[AnyView]` before block and loop assembly. This
/// preserves the Windows array builder's occurrence, slot, and iteration rules,
/// including loops whose content has an opaque `some View` type. This builder
/// is not a native SwiftUI API and does not change builders on nested controls.
@MainActor
@resultBuilder
public enum WindowsArrayViewBuilder {
    public static func buildExpression<V: View>(_ expression: V) -> [AnyView] {
        [AnyView(expression)]
    }

    public static func buildExpression<Data, ID>(
        _ expression: ForEach<Data, ID>
    ) -> [AnyView] {
        // This explicit array builder promises rows before block assembly.
        // ForEach itself keeps its factory deferred; requesting contentViews
        // opts this expression into the shared eager compatibility cache.
        expression.contentViews.map {
            $0.prefixedViewIdentity([.view(ObjectIdentifier(ForEach<Data, ID>.self)), .role(.content)])
        }
    }

    public static func buildExpression(_ expression: [AnyView]) -> [AnyView] {
        viewIdentityOccurrences(expression)
    }

    public static func buildExpression(_ expression: Void) -> [AnyView] {
        []
    }

    public static func buildBlock(_ components: [AnyView]...) -> [AnyView] {
        legacyViewBuilderBlock(components)
    }

    public static func buildOptional(_ components: [AnyView]?) -> [AnyView] {
        (components ?? []).map { $0.prefixedViewIdentity([.branch(true)]) }
    }

    public static func buildEither(first components: [AnyView]) -> [AnyView] {
        components.map { $0.prefixedViewIdentity([.branch(true)]) }
    }

    public static func buildEither(second components: [AnyView]) -> [AnyView] {
        components.map { $0.prefixedViewIdentity([.branch(false)]) }
    }

    public static func buildArray(_ components: [[AnyView]]) -> [AnyView] {
        components.enumerated().flatMap { index, views in
            views.map { $0.prefixedViewIdentity([.iteration(index)]) }
        }
    }

    public static func buildLimitedAvailability(_ components: [AnyView]) -> [AnyView] {
        components
    }
}
