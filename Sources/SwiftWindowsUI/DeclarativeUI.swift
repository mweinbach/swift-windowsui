import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout

@MainActor
public struct Component {
    private let makeViewNode: (RetainedViewRuntime) -> ViewNode

    /// Optional stable key for identity-based reconciliation.  When building
    /// child components from arrays or loops, assign a unique key so the
    /// diffing algorithm can match nodes by identity across rebuilds instead
    /// of relying on positional index alone.
    public var key: String?

    public init(
        key: String? = nil,
        makeViewNode: @escaping @MainActor (RetainedViewRuntime) -> ViewNode
    ) {
        self.key = key
        self.makeViewNode = makeViewNode
    }

    public func makeNode(runtime: RetainedViewRuntime) -> ViewNode {
        let node = makeViewNode(runtime)
        // Propagate the component key to the ViewNode's stable identity tag
        // so the diffing algorithm in ComponentHost can use it.
        if let key, node.nodeTag == nil {
            node.nodeTag = key
        }
        return node
    }

    /// Return a copy of this component with the given reconciliation key.
    public func keyed(_ key: String) -> Component {
        var copy = self
        copy.key = key
        return copy
    }

    public static let empty = Component { _ in ViewNode() }
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
        layoutPriority: Double = 0,
        backgroundColor: Color? = nil,
        backgroundGradient: GradientType? = nil,
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
                    layoutPriority: layoutPriority,
                    backgroundColor: backgroundColor,
                    backgroundGradient: backgroundGradient,
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
        layoutPriority: Double = 0,
        backgroundColor: Color? = nil,
        backgroundGradient: GradientType? = nil,
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
                    layoutPriority: layoutPriority,
                    backgroundColor: backgroundColor,
                    backgroundGradient: backgroundGradient,
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
        layoutPriority: Double = 0,
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
        scrollIndicatorHoverColor: Color = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
        scrollIndicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.72),
        scrollIndicatorThickness: Double = 6,
        isHitTestVisible: Bool = true,
        @ComponentBuilder content: () -> [Component]
    ) -> Component {
        let childComponents = content()
        return Component { runtime in
                Controls.scrollPanel(
                    axis: axis,
                    frame: frame,
                    preferredSize: preferredSize,
                    layoutPriority: layoutPriority,
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
                scrollIndicatorHoverColor: scrollIndicatorHoverColor,
                scrollIndicatorActiveColor: scrollIndicatorActiveColor,
                scrollIndicatorThickness: scrollIndicatorThickness,
                isHitTestVisible: isHitTestVisible,
                children: childComponents.map { $0.makeNode(runtime: runtime) }
            )
        }
    }

    public static func splitView(
        axis: SplitAxis,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        ratio: Double = 0.25,
        minPrimaryExtent: Double = 180,
        minSecondaryExtent: Double = 220,
        dividerThickness: Double = 16,
        dividerIdleColor: Color = Color(red: 0.36, green: 0.46, blue: 0.58, alpha: 0.10),
        dividerHoverColor: Color = Color(red: 0.50, green: 0.64, blue: 0.80, alpha: 0.28),
        dividerActiveColor: Color = Color(red: 0.70, green: 0.84, blue: 0.98, alpha: 0.48),
        onRatioChanged: ((Double) -> Void)? = nil,
        @ComponentBuilder primary: () -> [Component],
        @ComponentBuilder secondary: () -> [Component]
    ) -> Component {
        let primaryComponents = primary()
        let secondaryComponents = secondary()
        return Component { runtime in
            Controls.splitView(
                runtime: runtime,
                axis: axis,
                frame: frame,
                preferredSize: preferredSize,
                ratio: ratio,
                minPrimaryExtent: minPrimaryExtent,
                minSecondaryExtent: minSecondaryExtent,
                dividerThickness: dividerThickness,
                dividerIdleColor: dividerIdleColor,
                dividerHoverColor: dividerHoverColor,
                dividerActiveColor: dividerActiveColor,
                onRatioChanged: onRatioChanged,
                primary: primaryComponents.map { $0.makeNode(runtime: runtime) },
                secondary: secondaryComponents.map { $0.makeNode(runtime: runtime) }
            )
        }
    }

    public static func toolbar(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        backgroundColor: Color = Color(red: 0.11, green: 0.15, blue: 0.21, alpha: 0.98),
        backgroundGradient: GradientType? = nil,
        borderColor: Color = Color(red: 0.78, green: 0.86, blue: 0.95, alpha: 0.10),
        shadowColor: Color = Color(red: 0.01, green: 0.03, blue: 0.06, alpha: 0.22),
        cornerRadius: Double = 22,
        stackLayout: StackLayout = .horizontal(
            spacing: 14,
            padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18),
            alignment: .center,
            mainAlignment: .start
        ),
        isHitTestVisible: Bool = false,
        @ComponentBuilder content: () -> [Component]
    ) -> Component {
        let childComponents = content()
        return Component { runtime in
                Controls.toolbar(
                    frame: frame,
                    preferredSize: preferredSize,
                    layoutPriority: layoutPriority,
                    backgroundColor: backgroundColor,
                    backgroundGradient: backgroundGradient,
                    borderColor: borderColor,
                shadowColor: shadowColor,
                cornerRadius: cornerRadius,
                stackLayout: stackLayout,
                isHitTestVisible: isHitTestVisible,
                children: childComponents.map { $0.makeNode(runtime: runtime) }
            )
        }
    }

    public static func section(
        title: String,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        backgroundColor: Color = Color(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.98),
        backgroundGradient: GradientType? = nil,
        borderColor: Color = Color(red: 0.78, green: 0.86, blue: 0.95, alpha: 0.10),
        shadowColor: Color = Color(red: 0.01, green: 0.03, blue: 0.06, alpha: 0.24),
        cornerRadius: Double = 24,
        stackLayout: StackLayout = .vertical(
            spacing: 16,
            padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
            alignment: .stretch,
            mainAlignment: .start
        ),
        scrollAxis: ScrollAxis? = nil,
        scrollStep: Double = 64,
        scrollIndicatorColor: Color = Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.26),
        scrollIndicatorHoverColor: Color = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
        scrollIndicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.72),
        scrollIndicatorThickness: Double = 6,
        headerColor: Color = Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.96),
        headerScale: Double = 1.6,
        isHitTestVisible: Bool = false,
        @ComponentBuilder content: () -> [Component]
    ) -> Component {
        let childComponents = content()
        return Component { runtime in
                Controls.section(
                    title: title,
                    frame: frame,
                    preferredSize: preferredSize,
                    layoutPriority: layoutPriority,
                    backgroundColor: backgroundColor,
                backgroundGradient: backgroundGradient,
                borderColor: borderColor,
                shadowColor: shadowColor,
                cornerRadius: cornerRadius,
                stackLayout: stackLayout,
                scrollAxis: scrollAxis,
                scrollStep: scrollStep,
                scrollIndicatorColor: scrollIndicatorColor,
                scrollIndicatorHoverColor: scrollIndicatorHoverColor,
                scrollIndicatorActiveColor: scrollIndicatorActiveColor,
                scrollIndicatorThickness: scrollIndicatorThickness,
                headerColor: headerColor,
                headerScale: headerScale,
                isHitTestVisible: isHitTestVisible,
                children: childComponents.map { $0.makeNode(runtime: runtime) }
            )
        }
    }

    public static func label(
        _ text: String,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        color: Color = .white,
        scale: Double = 2,
        weight: TextWeight = .regular,
        fontFamily: String = "Segoe UI",
        alignment: TextHorizontalAlignment = .center,
        insets: EdgeInsets = .zero,
        lineBreakMode: TextLineBreakMode = .truncateTail,
        maximumNumberOfLines: Int? = nil,
        minimumNumberOfLines: Int? = nil
    ) -> Component {
        Component { _ in
            Controls.label(
                text,
                frame: frame,
                preferredSize: preferredSize,
                layoutPriority: layoutPriority,
                color: color,
                scale: scale,
                weight: weight,
                fontFamily: fontFamily,
                alignment: alignment,
                insets: insets,
                lineBreakMode: lineBreakMode,
                maximumNumberOfLines: maximumNumberOfLines,
                minimumNumberOfLines: minimumNumberOfLines
            )
        }
    }

    public static func icon(
        _ symbol: SymbolIcon,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        color: Color = .white,
        scale: Double = 1.9,
        alignment: TextHorizontalAlignment = .center,
        fontFamily: String = "Segoe Fluent Icons"
    ) -> Component {
        Component { _ in
            Controls.icon(
                symbol,
                frame: frame,
                preferredSize: preferredSize,
                color: color,
                scale: scale,
                alignment: alignment,
                fontFamily: fontFamily
            )
        }
    }

    public static func button(
        title: String,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        cornerRadius: Double,
        palette: SurfacePalette,
        chrome: SurfaceChrome = .elevatedButton,
        titleColor: Color = .white,
        titleScale: Double = 2,
        titleWeight: TextWeight = .semibold,
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
                    layoutPriority: layoutPriority,
                    cornerRadius: cornerRadius,
                    palette: palette,
                    chrome: chrome,
                titleColor: titleColor,
                titleScale: titleScale,
                titleWeight: titleWeight,
                clipsToBounds: clipsToBounds,
                animation: animation,
                action: action
            )
        }
    }

    public static func buttonPanel(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
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
                    layoutPriority: layoutPriority,
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

    public static func listRow(
        title: String,
        detail: String,
        accentColor: Color,
        symbol: SymbolIcon? = nil,
        preferredSize: Size = Size(width: 280, height: 68),
        layoutPriority: Double = 0,
        palette: SurfacePalette = SurfacePalette(
            idle: Color(red: 0.18, green: 0.23, blue: 0.31, alpha: 0.98),
            focused: Color(red: 0.26, green: 0.33, blue: 0.42, alpha: 1.0),
            pressed: Color(red: 0.72, green: 0.82, blue: 0.92, alpha: 1.0)
        ),
        chrome: SurfaceChrome = .elevatedButton,
        action: (() -> Void)? = nil
    ) -> Component {
        return Component { runtime in
            Controls.listRow(
                runtime: runtime,
                title: title,
                detail: detail,
                accentColor: accentColor,
                symbol: symbol,
                preferredSize: preferredSize,
                layoutPriority: layoutPriority,
                palette: palette,
                chrome: chrome,
                action: action
            )
        }
    }

    public static func canvas(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        renderer: @escaping @MainActor (inout CanvasGraphicsContext, Size) -> Void
    ) -> Component {
        Component { _ in
            ViewNode(
                frame: frame,
                canvasDraw: renderer,
                preferredSize: preferredSize,
                layoutPriority: layoutPriority
            )
        }
    }
}

extension Component {
    public func transform(_ transform: Transform2D) -> Component {
        Component(key: key) { runtime in
            let node = self.makeNode(runtime: runtime)
            node.transform = transform
            return node
        }
    }

    public func offset(x: Double = 0, y: Double = 0) -> Component {
        transform(Transform2D.translation(x: x, y: y))
    }

    public func scaleEffect(x: Double = 1, y: Double = 1) -> Component {
        transform(Transform2D.scale(x: x, y: y))
    }
}
