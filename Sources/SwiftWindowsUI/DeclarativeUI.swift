import SwiftWindowsCore
import SwiftWindowsLayout

@MainActor
public struct Component {
    private let makeViewNode: (RetainedViewRuntime) -> ViewNode

    public init(makeViewNode: @escaping @MainActor (RetainedViewRuntime) -> ViewNode) {
        self.makeViewNode = makeViewNode
    }

    public func makeNode(runtime: RetainedViewRuntime) -> ViewNode {
        makeViewNode(runtime)
    }
}

@resultBuilder
public enum ComponentBuilder {
    public static func buildExpression(_ component: Component) -> [Component] {
        [component]
    }

    public static func buildBlock(_ components: [Component]...) -> [Component] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ components: [Component]?) -> [Component] {
        components ?? []
    }

    public static func buildEither(first components: [Component]) -> [Component] {
        components
    }

    public static func buildEither(second components: [Component]) -> [Component] {
        components
    }

    public static func buildArray(_ components: [[Component]]) -> [Component] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ components: [Component]) -> [Component] {
        components
    }
}

@MainActor
public enum UI {
    public static func group(@ComponentBuilder _ content: () -> [Component]) -> [Component] {
        content()
    }

    public static func panel(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        backgroundColor: Color? = nil,
        text: String? = nil,
        textStyle: PixelTextStyle = PixelTextStyle(color: .white),
        borderColor: Color = .clear,
        borderWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        clipsToBounds: Bool = false,
        layoutMode: ViewLayoutMode = .absolute,
        isHitTestVisible: Bool = true,
        @ComponentBuilder content: () -> [Component] = { [] }
    ) -> Component {
        let childComponents = content()
        return Component { runtime in
            Controls.panel(
                frame: frame,
                preferredSize: preferredSize,
                backgroundColor: backgroundColor,
                text: text,
                textStyle: textStyle,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowColor: shadowColor,
                shadowOffset: shadowOffset,
                shadowSpread: shadowSpread,
                cornerRadius: cornerRadius,
                clipsToBounds: clipsToBounds,
                layoutMode: layoutMode,
                isHitTestVisible: isHitTestVisible,
                children: childComponents.map { $0.makeNode(runtime: runtime) }
            )
        }
    }

    public static func stackPanel(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        backgroundColor: Color? = nil,
        borderColor: Color = .clear,
        borderWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        clipsToBounds: Bool = false,
        stackLayout: StackLayout,
        isHitTestVisible: Bool = true,
        @ComponentBuilder content: () -> [Component]
    ) -> Component {
        let childComponents = content()
        return Component { runtime in
            Controls.stackPanel(
                frame: frame,
                preferredSize: preferredSize,
                backgroundColor: backgroundColor,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowColor: shadowColor,
                shadowOffset: shadowOffset,
                shadowSpread: shadowSpread,
                cornerRadius: cornerRadius,
                clipsToBounds: clipsToBounds,
                stackLayout: stackLayout,
                isHitTestVisible: isHitTestVisible,
                children: childComponents.map { $0.makeNode(runtime: runtime) }
            )
        }
    }

    public static func scrollPanel(
        axis: ScrollAxis,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        backgroundColor: Color? = nil,
        borderColor: Color = .clear,
        borderWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        stackLayout: StackLayout,
        scrollStep: Double = 64,
        scrollIndicatorColor: Color = Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.26),
        isHitTestVisible: Bool = true,
        @ComponentBuilder content: () -> [Component]
    ) -> Component {
        let childComponents = content()
        return Component { runtime in
            Controls.scrollPanel(
                axis: axis,
                frame: frame,
                preferredSize: preferredSize,
                backgroundColor: backgroundColor,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowColor: shadowColor,
                shadowOffset: shadowOffset,
                shadowSpread: shadowSpread,
                cornerRadius: cornerRadius,
                stackLayout: stackLayout,
                scrollStep: scrollStep,
                scrollIndicatorColor: scrollIndicatorColor,
                isHitTestVisible: isHitTestVisible,
                children: childComponents.map { $0.makeNode(runtime: runtime) }
            )
        }
    }

    public static func label(
        _ text: String,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        color: Color = .white,
        scale: Double = 2,
        alignment: TextHorizontalAlignment = .center,
        insets: EdgeInsets = .zero
    ) -> Component {
        Component { _ in
            Controls.label(
                text,
                frame: frame,
                preferredSize: preferredSize,
                color: color,
                scale: scale,
                alignment: alignment,
                insets: insets
            )
        }
    }

    public static func button(
        title: String,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        cornerRadius: Double,
        palette: SurfacePalette,
        chrome: SurfaceChrome = .elevatedButton,
        titleColor: Color = .white,
        titleScale: Double = 2,
        clipsToBounds: Bool = true,
        animation: ControlAnimationStyle = .default,
        action: (() -> Void)? = nil
    ) -> Component {
        return Component { runtime in
            Controls.button(
                runtime: runtime,
                title: title,
                frame: frame,
                preferredSize: preferredSize,
                cornerRadius: cornerRadius,
                palette: palette,
                chrome: chrome,
                titleColor: titleColor,
                titleScale: titleScale,
                clipsToBounds: clipsToBounds,
                animation: animation,
                action: action
            )
        }
    }

    public static func buttonPanel(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        cornerRadius: Double,
        palette: SurfacePalette,
        chrome: SurfaceChrome = .elevatedButton,
        clipsToBounds: Bool = true,
        layoutMode: ViewLayoutMode = .absolute,
        animation: ControlAnimationStyle = .default,
        action: (() -> Void)? = nil,
        @ComponentBuilder content: () -> [Component]
    ) -> Component {
        let childComponents = content()
        return Component { runtime in
            Controls.button(
                runtime: runtime,
                frame: frame,
                preferredSize: preferredSize,
                cornerRadius: cornerRadius,
                palette: palette,
                chrome: chrome,
                clipsToBounds: clipsToBounds,
                layoutMode: layoutMode,
                animation: animation,
                action: action,
                children: childComponents.map { $0.makeNode(runtime: runtime) }
            )
        }
    }
}
