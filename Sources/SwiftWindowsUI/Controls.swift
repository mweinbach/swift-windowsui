import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsPlatform

public struct ControlAnimationStyle: Sendable {
    public var focusDuration: Double
    public var pressDuration: Double
    public var activationDuration: Double

    public init(focusDuration: Double = 0.18, pressDuration: Double = 0.14, activationDuration: Double = 0.18) {
        self.focusDuration = focusDuration
        self.pressDuration = pressDuration
        self.activationDuration = activationDuration
    }

    public static let `default` = ControlAnimationStyle()
}

public struct SurfacePalette: Sendable {
    public var idle: Color
    public var hovered: Color
    public var focused: Color
    public var pressed: Color
    public var activated: Color
    public var disabledBackground: Color
    public var disabledForeground: Color
    public var disabledBorder: Color
    public var errorBorder: Color

    public init(
        idle: Color,
        hovered: Color? = nil,
        focused: Color,
        pressed: Color,
        activated: Color? = nil,
        disabledBackground: Color = Color(red: 0.22, green: 0.24, blue: 0.28, alpha: 0.60),
        disabledForeground: Color = Color(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.70),
        disabledBorder: Color = Color(red: 0.40, green: 0.42, blue: 0.46, alpha: 0.30),
        errorBorder: Color = Color(red: 0.90, green: 0.22, blue: 0.20, alpha: 0.90)
    ) {
        self.idle = idle
        self.hovered = hovered ?? focused
        self.focused = focused
        self.pressed = pressed
        self.activated = activated ?? focused
        self.disabledBackground = disabledBackground
        self.disabledForeground = disabledForeground
        self.disabledBorder = disabledBorder
        self.errorBorder = errorBorder
    }
}

public enum BorderStyle: Sendable, Equatable {
    case solid
    case dashed
    case dotted
    case double_
}

public struct CornerRadii: Sendable, Equatable {
    public var topLeft: Double
    public var topRight: Double
    public var bottomLeft: Double
    public var bottomRight: Double

    public init(topLeft: Double = 0, topRight: Double = 0, bottomLeft: Double = 0, bottomRight: Double = 0) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    public init(uniform radius: Double) {
        self.topLeft = radius
        self.topRight = radius
        self.bottomLeft = radius
        self.bottomRight = radius
    }
}

public struct SurfaceChrome: Sendable {
    public var borderColor: Color
    public var borderHoveredColor: Color
    public var borderFocusedColor: Color
    public var borderPressedColor: Color
    public var borderActivatedColor: Color
    public var borderWidth: Double
    public var borderTopWidth: Double?
    public var borderRightWidth: Double?
    public var borderBottomWidth: Double?
    public var borderLeftWidth: Double?
    public var borderStyle: BorderStyle
    public var cornerRadii: CornerRadii?
    public var focusRingColor: Color
    public var focusRingWidth: Double
    public var shadowColor: Color
    public var shadowHoveredColor: Color
    public var shadowFocusedColor: Color
    public var shadowPressedColor: Color
    public var shadowActivatedColor: Color
    public var shadowOffset: Point
    public var shadowSpread: Double

    public init(
        borderColor: Color = .clear,
        borderHoveredColor: Color? = nil,
        borderFocusedColor: Color? = nil,
        borderPressedColor: Color? = nil,
        borderActivatedColor: Color? = nil,
        borderWidth: Double = 0,
        borderTopWidth: Double? = nil,
        borderRightWidth: Double? = nil,
        borderBottomWidth: Double? = nil,
        borderLeftWidth: Double? = nil,
        borderStyle: BorderStyle = .solid,
        cornerRadii: CornerRadii? = nil,
        focusRingColor: Color = .clear,
        focusRingWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowHoveredColor: Color? = nil,
        shadowFocusedColor: Color? = nil,
        shadowPressedColor: Color? = nil,
        shadowActivatedColor: Color? = nil,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0
    ) {
        self.borderColor = borderColor
        self.borderHoveredColor = borderHoveredColor ?? borderColor
        self.borderFocusedColor = borderFocusedColor ?? borderHoveredColor ?? borderColor
        self.borderPressedColor = borderPressedColor ?? borderFocusedColor ?? borderColor
        self.borderActivatedColor = borderActivatedColor ?? borderFocusedColor ?? borderColor
        self.borderWidth = borderWidth
        self.borderTopWidth = borderTopWidth
        self.borderRightWidth = borderRightWidth
        self.borderBottomWidth = borderBottomWidth
        self.borderLeftWidth = borderLeftWidth
        self.borderStyle = borderStyle
        self.cornerRadii = cornerRadii
        self.focusRingColor = focusRingColor
        self.focusRingWidth = focusRingWidth
        self.shadowColor = shadowColor
        self.shadowHoveredColor = shadowHoveredColor ?? shadowColor
        self.shadowFocusedColor = shadowFocusedColor ?? shadowHoveredColor ?? shadowColor
        self.shadowPressedColor = shadowPressedColor ?? shadowFocusedColor ?? shadowColor
        self.shadowActivatedColor = shadowActivatedColor ?? shadowFocusedColor ?? shadowColor
        self.shadowOffset = shadowOffset
        self.shadowSpread = shadowSpread
    }

    /// Returns whether per-side border widths are set, overriding the uniform `borderWidth`.
    public var hasPerSideBorders: Bool {
        borderTopWidth != nil || borderRightWidth != nil || borderBottomWidth != nil || borderLeftWidth != nil
    }

    /// Resolved width for a given side, falling back to uniform `borderWidth`.
    public func resolvedBorderWidth(top: Bool = false, right: Bool = false, bottom: Bool = false, left: Bool = false) -> Double {
        if top, let w = borderTopWidth { return w }
        if right, let w = borderRightWidth { return w }
        if bottom, let w = borderBottomWidth { return w }
        if left, let w = borderLeftWidth { return w }
        return borderWidth
    }

    public static let elevatedButton = SurfaceChrome(
        borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.10),
        borderHoveredColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.18),
        borderFocusedColor: Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.26),
        borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.34),
        borderWidth: 1,
        focusRingColor: Color(red: 0.82, green: 0.90, blue: 1.0, alpha: 0.28),
        focusRingWidth: 2,
        shadowColor: Color(red: 0.02, green: 0.05, blue: 0.10, alpha: 0.14),
        shadowHoveredColor: Color(red: 0.02, green: 0.06, blue: 0.12, alpha: 0.18),
        shadowFocusedColor: Color(red: 0.04, green: 0.10, blue: 0.18, alpha: 0.24),
        shadowPressedColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.10),
        shadowOffset: Point(x: 0, y: 16),
        shadowSpread: 10
    )
}

public enum SplitAxis: Sendable {
    case horizontal
    case vertical
}

public enum SymbolIcon: String, Sendable {
    case search = "\u{E721}"
    case folder = "\u{E8B7}"
    case settings = "\u{E713}"
    case lightning = "\u{E945}"
    case layout = "\u{ECA5}"
    case keyboard = "\u{E765}"
    case sparkle = "\u{EAAC}"
    case info = "\u{E946}"
    case activity = "\u{E7C3}"
    case document = "\u{E8A5}"
    case split = "\u{E7FD}"
    case trash = "\u{E74D}"
    case checkmark = "\u{E73E}"
    case chevronDown = "\u{E70D}"
    case radioSelected = "\u{E915}"
    case radioUnselected = "\u{E916}"
}

@MainActor
public enum Controls {
    public static func panel(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        backgroundColor: Color? = nil,
        backgroundGradient: LinearGradient? = nil,
        text: String? = nil,
        textStyle: PixelTextStyle = PixelTextStyle(color: .white),
        borderColor: Color = .clear,
        borderWidth: Double = 0,
        outlineColor: Color = .clear,
        outlineWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        clipsToBounds: Bool = false,
        layoutMode: ViewLayoutMode = .absolute,
        isHitTestVisible: Bool = true,
        children: [ViewNode] = []
    ) -> ViewNode {
        ViewNode(
            frame: frame,
            backgroundColor: backgroundColor,
            backgroundGradient: backgroundGradient,
            text: text,
            textStyle: textStyle,
            borderColor: borderColor,
            borderWidth: borderWidth,
            outlineColor: outlineColor,
            outlineWidth: outlineWidth,
            shadowColor: shadowColor,
            shadowOffset: shadowOffset,
            shadowSpread: shadowSpread,
            cornerRadius: cornerRadius,
            clipsToBounds: clipsToBounds,
            layoutMode: layoutMode,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            isHitTestVisible: isHitTestVisible,
            children: children
        )
    }

    public static func stackPanel(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        backgroundColor: Color? = nil,
        backgroundGradient: LinearGradient? = nil,
        text: String? = nil,
        textStyle: PixelTextStyle = PixelTextStyle(color: .white),
        borderColor: Color = .clear,
        borderWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        clipsToBounds: Bool = false,
        stackLayout: StackLayout,
        isHitTestVisible: Bool = true,
        children: [ViewNode] = []
    ) -> ViewNode {
        panel(
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
            layoutMode: .stack(stackLayout),
            isHitTestVisible: isHitTestVisible,
            children: children
        )
    }

    public static func gridPanel(
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
        clipsToBounds: Bool = false,
        gridLayout: GridLayout,
        isHitTestVisible: Bool = true,
        children: [ViewNode] = []
    ) -> ViewNode {
        panel(
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
            clipsToBounds: clipsToBounds,
            layoutMode: .grid(gridLayout),
            isHitTestVisible: isHitTestVisible,
            children: children
        )
    }

    public static func path(
        _ path: RenderPath,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        fillColor: Color,
        strokeColor: Color = .clear,
        strokeStyle: StrokeStyle? = nil,
        isHitTestVisible: Bool = false
    ) -> ViewNode {
        ViewNode(
            frame: frame,
            renderPath: path,
            pathFillColor: fillColor,
            pathStrokeColor: strokeColor,
            pathStrokeStyle: strokeStyle,
            preferredSize: preferredSize,
            isHitTestVisible: isHitTestVisible
        )
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
        children: [ViewNode] = []
    ) -> ViewNode {
        panel(
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
            clipsToBounds: true,
            layoutMode: .stack(stackLayout),
            isHitTestVisible: isHitTestVisible,
            children: children
        ).configured { node in
            node.scrollAxis = axis
            node.scrollStep = scrollStep
            node.showsScrollIndicator = true
            node.scrollIndicatorColor = scrollIndicatorColor
            node.scrollIndicatorIdleColor = scrollIndicatorColor
            node.scrollIndicatorHoverColor = scrollIndicatorHoverColor
            node.scrollIndicatorActiveColor = scrollIndicatorActiveColor
            node.scrollIndicatorThickness = scrollIndicatorThickness
        }
    }

    public static func splitView(
        runtime: RetainedViewRuntime,
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
        primary: [ViewNode],
        secondary: [ViewNode]
    ) -> ViewNode {
        let primaryContainer = panel(clipsToBounds: true, layoutMode: .absolute, isHitTestVisible: false, children: primary)
        let secondaryContainer = panel(clipsToBounds: true, layoutMode: .absolute, isHitTestVisible: false, children: secondary)
        let dividerHandle = panel(
            backgroundColor: dividerIdleColor,
            cornerRadius: dividerThickness * 0.5,
            isHitTestVisible: true
        )

        let splitRoot = panel(
            frame: frame,
            preferredSize: preferredSize,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [primaryContainer, secondaryContainer, dividerHandle]
        )

        let state = SplitViewState(ratio: ratio)

        func applyLayout(in bounds: Rect) {
            state.bounds = bounds

            let totalExtent = axis == .horizontal ? bounds.size.width : bounds.size.height
            let availableExtent = max(0, totalExtent - dividerThickness)
            let clampedPrimary = min(max(availableExtent * state.ratio, minPrimaryExtent), max(minPrimaryExtent, availableExtent - minSecondaryExtent))
            let resolvedPrimary = availableExtent <= 0 ? 0 : min(max(clampedPrimary, 0), availableExtent)
            let resolvedRatio = availableExtent <= 0 ? state.ratio : resolvedPrimary / availableExtent
            state.ratio = resolvedRatio
            onRatioChanged?(resolvedRatio)

            let primaryFrame: Rect
            let secondaryFrame: Rect
            let dividerFrame: Rect

            switch axis {
            case .horizontal:
                primaryFrame = Rect(x: 0, y: 0, width: resolvedPrimary, height: bounds.size.height)
                dividerFrame = Rect(x: resolvedPrimary, y: 0, width: dividerThickness, height: bounds.size.height)
                secondaryFrame = Rect(x: resolvedPrimary + dividerThickness, y: 0, width: max(0, bounds.size.width - resolvedPrimary - dividerThickness), height: bounds.size.height)
            case .vertical:
                primaryFrame = Rect(x: 0, y: 0, width: bounds.size.width, height: resolvedPrimary)
                dividerFrame = Rect(x: 0, y: resolvedPrimary, width: bounds.size.width, height: dividerThickness)
                secondaryFrame = Rect(x: 0, y: resolvedPrimary + dividerThickness, width: bounds.size.width, height: max(0, bounds.size.height - resolvedPrimary - dividerThickness))
            }

            if primaryContainer.frame != primaryFrame {
                primaryContainer.frame = primaryFrame
            }
            if secondaryContainer.frame != secondaryFrame {
                secondaryContainer.frame = secondaryFrame
            }
            if dividerHandle.frame != dividerFrame {
                dividerHandle.frame = dividerFrame
            }

            if primaryContainer.children.count == 1 {
                let primaryChildFrame = Rect(x: 0, y: 0, width: primaryFrame.size.width, height: primaryFrame.size.height)
                if primaryContainer.children[0].frame != primaryChildFrame {
                    primaryContainer.children[0].frame = primaryChildFrame
                }
            }

            if secondaryContainer.children.count == 1 {
                let secondaryChildFrame = Rect(x: 0, y: 0, width: secondaryFrame.size.width, height: secondaryFrame.size.height)
                if secondaryContainer.children[0].frame != secondaryChildFrame {
                    secondaryContainer.children[0].frame = secondaryChildFrame
                }
            }
        }

        splitRoot.onLayout = { bounds in
            applyLayout(in: bounds)
        }

        dividerHandle.onPointerEnter = { [weak dividerHandle] in
            animate(.background, dividerHandle, in: runtime, to: dividerHoverColor, duration: 0.12)
        }
        dividerHandle.onPointerExit = { [weak dividerHandle] in
            animate(.background, dividerHandle, in: runtime, to: dividerIdleColor, duration: 0.12)
        }
        dividerHandle.onDragStart = { [weak dividerHandle] _ in
            state.dragStartRatio = state.ratio
            animate(.background, dividerHandle, in: runtime, to: dividerActiveColor, duration: 0.08)
        }
        dividerHandle.onDragChange = { _, delta in
            let totalExtent = axis == .horizontal ? state.bounds.size.width : state.bounds.size.height
            let availableExtent = max(1, totalExtent - dividerThickness)
            let deltaExtent = axis == .horizontal ? delta.x : delta.y
            state.ratio = state.dragStartRatio + deltaExtent / availableExtent
            applyLayout(in: state.bounds)
        }
        dividerHandle.onDragEnd = { _, _ in
            animate(.background, dividerHandle, in: runtime, to: dividerHoverColor, duration: 0.12)
        }

        return splitRoot
    }

    public static func toolbar(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        backgroundColor: Color = Color(red: 0.09, green: 0.12, blue: 0.19, alpha: 0.76),
        backgroundGradient: LinearGradient? = nil,
        borderColor: Color = Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.11),
        shadowColor: Color = Color(red: 0.02, green: 0.05, blue: 0.10, alpha: 0.18),
        cornerRadius: Double = 28,
        stackLayout: StackLayout = .horizontal(
            spacing: 14,
            padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18),
            alignment: .center,
            mainAlignment: .start
        ),
        isHitTestVisible: Bool = false,
        children: [ViewNode] = []
    ) -> ViewNode {
        stackPanel(
            frame: frame,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            backgroundColor: backgroundColor,
            backgroundGradient: backgroundGradient,
            borderColor: borderColor,
            borderWidth: 1,
            shadowColor: shadowColor,
            shadowOffset: Point(x: 0, y: 18),
            shadowSpread: 10,
            cornerRadius: cornerRadius,
            clipsToBounds: true,
            stackLayout: stackLayout,
            isHitTestVisible: isHitTestVisible,
            children: children
        )
    }

    public static func section(
        title: String,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        backgroundColor: Color = Color(red: 0.10, green: 0.14, blue: 0.22, alpha: 0.78),
        backgroundGradient: LinearGradient? = nil,
        borderColor: Color = Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
        shadowColor: Color = Color(red: 0.02, green: 0.05, blue: 0.10, alpha: 0.16),
        cornerRadius: Double = 28,
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
        children: [ViewNode] = []
    ) -> ViewNode {
        let content = [label(title, color: headerColor, scale: headerScale, weight: .semibold, alignment: .leading, lineBreakMode: .truncateTail, maximumNumberOfLines: 1)] + children
        return stackPanel(
            frame: frame,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            backgroundColor: backgroundColor,
            backgroundGradient: backgroundGradient,
            borderColor: borderColor,
            borderWidth: 1,
            shadowColor: shadowColor,
            shadowOffset: Point(x: 0, y: 20),
            shadowSpread: 10,
            cornerRadius: cornerRadius,
            clipsToBounds: true,
            stackLayout: stackLayout,
            isHitTestVisible: isHitTestVisible,
            children: content
        ).configured { node in
            guard let scrollAxis else {
                return
            }

            node.scrollAxis = scrollAxis
            node.scrollStep = scrollStep
            node.showsScrollIndicator = true
            node.scrollIndicatorColor = scrollIndicatorColor
            node.scrollIndicatorIdleColor = scrollIndicatorColor
            node.scrollIndicatorHoverColor = scrollIndicatorHoverColor
            node.scrollIndicatorActiveColor = scrollIndicatorActiveColor
            node.scrollIndicatorThickness = scrollIndicatorThickness
        }
    }

    public static func listRow(
        runtime: RetainedViewRuntime,
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
    ) -> ViewNode {
        let leadingBar = panel(
            preferredSize: Size(width: 8, height: 44),
            backgroundColor: accentColor,
            cornerRadius: 4,
            isHitTestVisible: false
        )

        let labels = stackPanel(
            preferredSize: Size(width: 0, height: 44),
            layoutPriority: 1,
            stackLayout: .vertical(spacing: 6, alignment: .leading, mainAlignment: .center),
            isHitTestVisible: false,
            children: [
                label(title, color: .white, scale: 1.8, weight: .semibold, alignment: .leading, lineBreakMode: .truncateTail, maximumNumberOfLines: 1),
                label(detail, color: Color(red: 0.76, green: 0.86, blue: 0.95, alpha: 0.86), scale: 1.2, alignment: .leading, lineBreakMode: .truncateTail, maximumNumberOfLines: 1),
            ]
        )

        var contentChildren: [ViewNode] = [leadingBar]
        if let symbol {
            contentChildren.append(
                panel(
                    preferredSize: Size(width: 28, height: 44),
                    backgroundColor: nil,
                    layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
                    isHitTestVisible: false,
                    children: [Self.icon(symbol, preferredSize: Size(width: 24, height: 24), color: accentColor, scale: 1.5)]
                )
            )
        }
        contentChildren.append(labels)

        return button(
            runtime: runtime,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            cornerRadius: 18,
            palette: palette,
            chrome: chrome,
            layoutMode: .stack(.horizontal(spacing: 14, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), alignment: .center)),
            action: action,
            children: contentChildren
        )
    }

    public static func button(
        runtime: RetainedViewRuntime,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        cornerRadius: Double,
        palette: SurfacePalette,
        chrome: SurfaceChrome = .elevatedButton,
        isEnabled: Bool = true,
        clipsToBounds: Bool = false,
        layoutMode: ViewLayoutMode = .absolute,
        animation: ControlAnimationStyle = .default,
        action: (() -> Void)? = nil,
        children: [ViewNode] = []
    ) -> ViewNode {
        let isInteractive = isEnabled
        let node = panel(
            frame: frame,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            backgroundColor: isEnabled ? palette.idle : palette.disabledBackground,
            borderColor: isEnabled ? chrome.borderColor : palette.disabledBorder,
            borderWidth: chrome.borderWidth,
            outlineColor: .clear,
            outlineWidth: chrome.focusRingWidth,
            shadowColor: isEnabled ? chrome.shadowColor : .clear,
            shadowOffset: chrome.shadowOffset,
            shadowSpread: chrome.shadowSpread,
            cornerRadius: cornerRadius,
            clipsToBounds: clipsToBounds,
            layoutMode: layoutMode,
            isHitTestVisible: isInteractive,
            children: children
        )

        guard isInteractive else {
            node.isFocusable = false
            return node
        }

        let interactionState = ButtonInteractionState()

        func applySurfaceState(duration: Double) {
            let backgroundColor: Color
            let borderColor: Color
            let shadowColor: Color

            if interactionState.isPressed {
                backgroundColor = palette.pressed
                borderColor = chrome.borderPressedColor
                shadowColor = chrome.shadowPressedColor
            } else if interactionState.isFocused {
                backgroundColor = palette.focused
                borderColor = chrome.borderFocusedColor
                shadowColor = chrome.shadowFocusedColor
            } else if interactionState.isHovered {
                backgroundColor = palette.hovered
                borderColor = chrome.borderHoveredColor
                shadowColor = chrome.shadowHoveredColor
            } else {
                backgroundColor = palette.idle
                borderColor = chrome.borderColor
                shadowColor = chrome.shadowColor
            }

            animate(.background, node, in: runtime, to: backgroundColor, duration: duration)
            animate(.border, node, in: runtime, to: borderColor, duration: duration)
            animate(.shadow, node, in: runtime, to: shadowColor, duration: duration)
        }

        node.onPointerEnter = {
            interactionState.isHovered = true
            applySurfaceState(duration: animation.focusDuration)
        }
        node.onPointerExit = {
            interactionState.isHovered = false
            interactionState.isPressed = false
            applySurfaceState(duration: animation.focusDuration)
        }
        node.isFocusable = true
        node.onFocusEnter = { [weak node] in
            interactionState.isFocused = true
            applySurfaceState(duration: animation.focusDuration)
            animate(.outline, node, in: runtime, to: chrome.focusRingColor, duration: animation.focusDuration)
        }
        node.onFocusExit = { [weak node] in
            interactionState.isFocused = false
            interactionState.isPressed = false
            applySurfaceState(duration: animation.focusDuration)
            animate(.outline, node, in: runtime, to: .clear, duration: animation.focusDuration)
        }
        node.onPointerDown = {
            interactionState.isPressed = true
            applySurfaceState(duration: animation.pressDuration)
        }
        node.onPointerUpInside = {
            interactionState.isPressed = false
            applySurfaceState(duration: animation.focusDuration)
        }
        node.onPointerUpOutside = {
            interactionState.isPressed = false
            applySurfaceState(duration: animation.focusDuration)
        }
        node.onActivate = { [weak node] in
            interactionState.isPressed = false
            animate(.background, node, in: runtime, to: palette.activated, duration: animation.activationDuration)
            animate(.border, node, in: runtime, to: chrome.borderActivatedColor, duration: animation.activationDuration)
            animate(.shadow, node, in: runtime, to: chrome.shadowActivatedColor, duration: animation.activationDuration)
            action?()
        }

        return node
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
        maximumNumberOfLines: Int? = nil
    ) -> ViewNode {
        panel(
            frame: frame,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            backgroundColor: nil,
            text: text,
            textStyle: PixelTextStyle(
                color: color,
                scale: scale,
                alignment: alignment,
                insets: insets,
                fontFamily: fontFamily,
                weight: weight,
                lineBreakMode: lineBreakMode,
                maximumNumberOfLines: maximumNumberOfLines
            ),
            isHitTestVisible: false
        )
    }

    public static func icon(
        _ symbol: SymbolIcon,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        color: Color = .white,
        scale: Double = 1.9,
        alignment: TextHorizontalAlignment = .center,
        fontFamily: String = "Segoe Fluent Icons"
    ) -> ViewNode {
        label(
            symbol.rawValue,
            frame: frame,
            preferredSize: preferredSize,
            color: color,
            scale: scale,
            weight: .regular,
            fontFamily: fontFamily,
            alignment: alignment
        )
    }

    public static func button(
        runtime: RetainedViewRuntime,
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
        isEnabled: Bool = true,
        clipsToBounds: Bool = true,
        animation: ControlAnimationStyle = .default,
        action: (() -> Void)? = nil
    ) -> ViewNode {
        let labelNode = label(
            title,
            layoutPriority: 1,
            color: isEnabled ? titleColor : palette.disabledForeground,
            scale: titleScale,
            weight: titleWeight,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )
        return button(
            runtime: runtime,
            frame: frame,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            cornerRadius: cornerRadius,
            palette: palette,
            chrome: chrome,
            isEnabled: isEnabled,
            clipsToBounds: clipsToBounds,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            animation: animation,
            action: action,
            children: [labelNode]
        )
    }

    // MARK: - Text Field

    public static func textField(
        runtime: RetainedViewRuntime,
        text: String,
        placeholder: String = "",
        isEnabled: Bool = true,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        palette: SurfacePalette = SurfacePalette(
            idle: Color(red: 0.15, green: 0.19, blue: 0.27, alpha: 0.92),
            hovered: Color(red: 0.18, green: 0.23, blue: 0.32, alpha: 0.96),
            focused: Color(red: 0.20, green: 0.27, blue: 0.38, alpha: 0.98),
            pressed: Color(red: 0.20, green: 0.27, blue: 0.38, alpha: 0.98)
        ),
        chrome: SurfaceChrome = SurfaceChrome(
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
            borderHoveredColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22),
            borderFocusedColor: Color(red: 0.48, green: 0.72, blue: 1.0, alpha: 0.58),
            borderWidth: 1,
            focusRingColor: Color(red: 0.50, green: 0.74, blue: 1.0, alpha: 0.20),
            focusRingWidth: 2
        ),
        textColor: Color = Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0),
        placeholderColor: Color = Color(red: 0.64, green: 0.70, blue: 0.78, alpha: 0.72),
        animation: ControlAnimationStyle = .default,
        isSecure: Bool = false,
        isMultiline: Bool = false,
        onTextChanged: ((String) -> Void)? = nil,
        onSubmit: (() -> Void)? = nil
    ) -> ViewNode {
        let state = TextFieldState(text: text)
        let resolvedTextColor = isEnabled ? textColor : palette.disabledForeground
        let resolvedPlaceholderColor = isEnabled ? placeholderColor : palette.disabledForeground
        let contentInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        let textStyle = PixelTextStyle(
            color: state.text.isEmpty ? resolvedPlaceholderColor : resolvedTextColor,
            scale: 1.6,
            alignment: .leading,
            fontFamily: "Segoe UI",
            weight: .regular,
            lineBreakMode: isMultiline ? .wrap : .truncateTail,
            maximumNumberOfLines: isMultiline ? nil : 1
        )

        let textLabel = label(
            state.displayText(placeholder: placeholder, isSecure: isSecure),
            layoutPriority: 1,
            color: state.text.isEmpty ? resolvedPlaceholderColor : resolvedTextColor,
            scale: 1.6,
            weight: .regular,
            alignment: .leading,
            lineBreakMode: isMultiline ? .wrap : .truncateTail,
            maximumNumberOfLines: isMultiline ? nil : 1
        )

        let selectionHighlight = panel(
            backgroundColor: Color(red: 0.36, green: 0.62, blue: 1.0, alpha: 0.34),
            cornerRadius: 4,
            isHitTestVisible: false
        )
        selectionHighlight.isHidden = true
        selectionHighlight.zIndex = -1

        let caret = panel(
            preferredSize: Size(width: 1.5, height: 18),
            backgroundColor: resolvedTextColor,
            cornerRadius: 0.75,
            isHitTestVisible: false
        )
        caret.isHidden = true

        let root = panel(
            preferredSize: preferredSize ?? Size(width: isMultiline ? 320 : 220, height: isMultiline ? 120 : 38),
            layoutPriority: layoutPriority,
            backgroundColor: isEnabled ? palette.idle : palette.disabledBackground,
            borderColor: isEnabled ? chrome.borderColor : palette.disabledBorder,
            borderWidth: chrome.borderWidth,
            outlineColor: .clear,
            outlineWidth: chrome.focusRingWidth,
            cornerRadius: 12,
            clipsToBounds: true,
            layoutMode: .absolute,
            isHitTestVisible: true,
            children: [textLabel, caret, selectionHighlight]
        )

        func refreshText() {
            textLabel.text = state.displayText(placeholder: placeholder, isSecure: isSecure)
            var style = textLabel.textStyle
            style.color = state.text.isEmpty ? resolvedPlaceholderColor : resolvedTextColor
            textLabel.textStyle = style
        }

        func measuredTextWidth(_ text: String) -> Double {
            guard !text.isEmpty else {
                return 0
            }

            return NativeTextRenderer.measure(text, style: textStyle, scaleFactor: runtime.displayScale)?.width
                ?? PixelFont.measure(text, style: textStyle).width
        }

        func measuredPrefixWidth() -> Double {
            measuredTextWidth(state.prefixBeforeCaret(isSecure: isSecure, currentLineOnly: isMultiline))
        }

        func layoutSelectionHighlight(
            contentX: Double,
            contentY: Double,
            contentWidth: Double,
            contentHeight: Double,
            lineHeight: Double
        ) {
            guard let selectedText = state.selectedDisplayText(isSecure: isSecure), !selectedText.isEmpty else {
                selectionHighlight.isHidden = true
                selectionHighlight.frame = .zero
                return
            }

            if isMultiline {
                let selectedLineCount = selectedText.reduce(1) { count, character in
                    character == "\n" ? count + 1 : count
                }
                let rawSelectionY = Double(state.lineIndexBeforeSelection()) * lineHeight
                let selectionHeight = min(
                    max(0, contentHeight),
                    max(lineHeight, Double(selectedLineCount) * lineHeight)
                )
                let selectionY = contentY + min(max(0, contentHeight - selectionHeight), rawSelectionY)
                selectionHighlight.frame = Rect(
                    x: contentX,
                    y: selectionY,
                    width: contentWidth,
                    height: selectionHeight
                )
            } else {
                let prefixWidth = min(
                    contentWidth,
                    measuredTextWidth(state.prefixBeforeSelection(isSecure: isSecure))
                )
                let availableWidth = max(0, contentWidth - prefixWidth)
                let selectionWidth = min(availableWidth, measuredTextWidth(selectedText))
                let selectionHeight = min(max(0, contentHeight), max(2, lineHeight))
                selectionHighlight.frame = Rect(
                    x: contentX + prefixWidth,
                    y: contentY + max(0, (contentHeight - selectionHeight) * 0.5),
                    width: selectionWidth,
                    height: selectionHeight
                )
            }

            selectionHighlight.isHidden = selectionHighlight.frame.size.width <= 0
                || selectionHighlight.frame.size.height <= 0
        }

        func layoutTextAndCaret(in bounds: Rect) {
            let contentX = contentInsets.leading
            let contentY = contentInsets.top
            let contentWidth = max(0, bounds.size.width - contentInsets.leading - contentInsets.trailing)
            let contentHeight = max(0, bounds.size.height - contentInsets.top - contentInsets.bottom)
            textLabel.frame = isMultiline
                ? Rect(x: contentX, y: contentY, width: contentWidth, height: contentHeight)
                : Rect(x: contentX, y: 0, width: contentWidth, height: bounds.size.height)

            let caretX = min(contentX + measuredPrefixWidth(), contentX + contentWidth)
            let caretHeight = min(18, max(0, contentHeight))
            let lineHeight = measuredLineHeight()
            layoutSelectionHighlight(
                contentX: contentX,
                contentY: contentY,
                contentWidth: contentWidth,
                contentHeight: contentHeight,
                lineHeight: lineHeight
            )
            let caretY = isMultiline
                ? contentY + min(max(0, contentHeight - caretHeight), Double(state.lineIndexBeforeCaret()) * lineHeight)
                : contentY + max(0, (contentHeight - caretHeight) * 0.5)
            caret.frame = Rect(
                x: caretX,
                y: caretY,
                width: 1.5,
                height: caretHeight
            )
        }

        func measuredLineHeight() -> Double {
            NativeTextRenderer.measure("M", style: textStyle, scaleFactor: runtime.displayScale)?.height
                ?? PixelFont.measure("M", style: textStyle).height
        }

        func applyTextMutation(_ didMutate: Bool) {
            guard didMutate else {
                return
            }

            refreshText()
            layoutTextAndCaret(in: root.resolvedFrame)
            onTextChanged?(state.text)
        }

        func applyCaretMove(_ didMove: Bool) {
            guard didMove else {
                return
            }

            layoutTextAndCaret(in: root.resolvedFrame)
        }

        func applySelectionChange(_ didChange: Bool) {
            guard didChange else {
                return
            }

            layoutTextAndCaret(in: root.resolvedFrame)
        }

        root.onLayout = { bounds in
            layoutTextAndCaret(in: bounds)
        }

        if isEnabled {
            let interactionState = ButtonInteractionState()

            root.isFocusable = true
            root.onPointerEnter = { [weak root] in
                interactionState.isHovered = true
                guard !interactionState.isFocused else {
                    return
                }
                animate(.background, root, in: runtime, to: palette.hovered, duration: animation.focusDuration)
                animate(.border, root, in: runtime, to: chrome.borderHoveredColor, duration: animation.focusDuration)
            }
            root.onPointerExit = { [weak root] in
                interactionState.isHovered = false
                guard !interactionState.isFocused else {
                    return
                }
                animate(.background, root, in: runtime, to: palette.idle, duration: animation.focusDuration)
                animate(.border, root, in: runtime, to: chrome.borderColor, duration: animation.focusDuration)
            }
            root.onFocusEnter = { [weak root, weak caret] in
                interactionState.isFocused = true
                caret?.isHidden = false
                animate(.background, root, in: runtime, to: palette.focused, duration: animation.focusDuration)
                animate(.border, root, in: runtime, to: chrome.borderFocusedColor, duration: animation.focusDuration)
                animate(.outline, root, in: runtime, to: chrome.focusRingColor, duration: animation.focusDuration)
            }
            root.onFocusExit = { [weak root, weak caret] in
                interactionState.isFocused = false
                caret?.isHidden = true
                let background = interactionState.isHovered ? palette.hovered : palette.idle
                let border = interactionState.isHovered ? chrome.borderHoveredColor : chrome.borderColor
                animate(.background, root, in: runtime, to: background, duration: animation.focusDuration)
                animate(.border, root, in: runtime, to: border, duration: animation.focusDuration)
                animate(.outline, root, in: runtime, to: .clear, duration: animation.focusDuration)
            }
            root.onTextInput = { input in
                let sanitizedInput = sanitizedTextInput(input, allowsNewlines: isMultiline)
                guard !sanitizedInput.isEmpty else {
                    return
                }

                applyTextMutation(state.insert(sanitizedInput))
            }
            root.onPointerDownAt = { point in
                let offset = caretOffset(at: point)
                applyCaretMove(state.moveCaret(toTextOffset: offset))
            }
            root.onDragStartAt = { point in
                applySelectionChange(state.beginSelection(atTextOffset: caretOffset(at: point)))
            }
            root.onDragChangeAt = { point, _ in
                applySelectionChange(state.extendSelection(toTextOffset: caretOffset(at: point)))
            }
            root.onDragEndAt = { point, _ in
                applySelectionChange(state.extendSelection(toTextOffset: caretOffset(at: point)))
            }
            root.onKeyDown = { event in
                if event.modifiers.contains(.control) {
                    switch event.keyCode {
                    case 0x41:
                        applySelectionChange(state.selectAll())
                    case 0x43:
                        if let clipboardText = state.selectedClipboardText(isSecure: isSecure) {
                            runtime.textClipboard?.writeString(clipboardText)
                        }
                    case 0x58:
                        guard let textClipboard = runtime.textClipboard else {
                            break
                        }

                        if let clipboardText = state.cutSelectedText(isSecure: isSecure) {
                            textClipboard.writeString(clipboardText)
                            applyTextMutation(true)
                        }
                    case 0x56:
                        guard let clipboardText = runtime.textClipboard?.readString() else {
                            break
                        }

                        let sanitizedClipboardText = sanitizedTextInput(clipboardText, allowsNewlines: isMultiline)
                        guard !sanitizedClipboardText.isEmpty else {
                            break
                        }

                        applyTextMutation(state.insert(sanitizedClipboardText))
                    default:
                        break
                    }
                    return
                }

                switch event.key {
                case .backspace:
                    applyTextMutation(state.backspace())
                case .delete:
                    applyTextMutation(state.deleteForward())
                case .leftArrow:
                    applyCaretMove(state.moveCaretLeft(extendSelection: event.modifiers.contains(.shift)))
                case .rightArrow:
                    applyCaretMove(state.moveCaretRight(extendSelection: event.modifiers.contains(.shift)))
                case .upArrow:
                    guard isMultiline else {
                        break
                    }
                    applyCaretMove(state.moveCaretUp(extendSelection: event.modifiers.contains(.shift)))
                case .downArrow:
                    guard isMultiline else {
                        break
                    }
                    applyCaretMove(state.moveCaretDown(extendSelection: event.modifiers.contains(.shift)))
                case .home:
                    applyCaretMove(state.moveCaretToStart(extendSelection: event.modifiers.contains(.shift)))
                case .end:
                    applyCaretMove(state.moveCaretToEnd(extendSelection: event.modifiers.contains(.shift)))
                case .enter:
                    if isMultiline {
                        applyTextMutation(state.insert("\n"))
                    } else {
                        onSubmit?()
                    }
                default:
                    break
                }
            }
        }

        func caretOffset(at point: Point) -> Int {
            let contentPoint = Point(
                x: point.x - contentInsets.leading,
                y: point.y - contentInsets.top
            )
            return state.caretOffset(
                closestTo: contentPoint,
                isSecure: isSecure,
                isMultiline: isMultiline,
                lineHeight: measuredLineHeight(),
                measureTextWidth: measuredTextWidth
            )
        }

        return root
    }

    public static func textEditor(
        runtime: RetainedViewRuntime,
        text: String,
        isEnabled: Bool = true,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        textColor: Color = Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0),
        placeholderColor: Color = Color(red: 0.64, green: 0.70, blue: 0.78, alpha: 0.72),
        animation: ControlAnimationStyle = .default,
        onTextChanged: ((String) -> Void)? = nil
    ) -> ViewNode {
        textField(
            runtime: runtime,
            text: text,
            placeholder: "",
            isEnabled: isEnabled,
            preferredSize: preferredSize ?? Size(width: 320, height: 120),
            layoutPriority: layoutPriority,
            textColor: textColor,
            placeholderColor: placeholderColor,
            animation: animation,
            isMultiline: true,
            onTextChanged: onTextChanged
        )
    }

    // MARK: - Checkbox

    public static func checkbox(
        runtime: RetainedViewRuntime,
        label labelText: String,
        isChecked: Bool,
        isEnabled: Bool = true,
        isError: Bool = false,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        palette: SurfacePalette = SurfacePalette(
            idle: Color(red: 0.18, green: 0.23, blue: 0.31, alpha: 0.98),
            focused: Color(red: 0.26, green: 0.33, blue: 0.42, alpha: 1.0),
            pressed: Color(red: 0.72, green: 0.82, blue: 0.92, alpha: 1.0)
        ),
        chrome: SurfaceChrome = .elevatedButton,
        animation: ControlAnimationStyle = .default,
        onToggle: ((Bool) -> Void)? = nil
    ) -> ViewNode {
        let boxSize: Double = 20
        let resolvedBorderColor = isError ? palette.errorBorder : (isEnabled ? chrome.borderColor : palette.disabledBorder)
        let resolvedBackgroundColor = isEnabled ? palette.idle : palette.disabledBackground
        let resolvedForeground = isEnabled ? Color.white : palette.disabledForeground

        let checkIcon = isChecked
            ? icon(.checkmark, preferredSize: Size(width: boxSize - 4, height: boxSize - 4), color: resolvedForeground, scale: 1.2)
            : panel(preferredSize: Size(width: boxSize - 4, height: boxSize - 4), isHitTestVisible: false)

        let box = panel(
            preferredSize: Size(width: boxSize, height: boxSize),
            backgroundColor: resolvedBackgroundColor,
            borderColor: resolvedBorderColor,
            borderWidth: isError ? 2 : chrome.borderWidth,
            cornerRadius: 4,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isHitTestVisible: false,
            children: [checkIcon]
        )

        let labelNode = label(
            labelText,
            layoutPriority: 1,
            color: resolvedForeground,
            scale: 1.6,
            weight: .regular,
            alignment: .leading,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )

        let action: (() -> Void)? = isEnabled ? { onToggle?(!isChecked) } : nil

        return button(
            runtime: runtime,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            cornerRadius: 8,
            palette: palette,
            chrome: chrome,
            isEnabled: isEnabled,
            clipsToBounds: true,
            layoutMode: .stack(.horizontal(spacing: 10, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8), alignment: .center)),
            animation: animation,
            action: action,
            children: [box, labelNode]
        )
    }

    // MARK: - Toggle / Switch

    public static func toggle(
        runtime: RetainedViewRuntime,
        isOn: Bool,
        isEnabled: Bool = true,
        isError: Bool = false,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        onColor: Color = Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0),
        offColor: Color = Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0),
        palette: SurfacePalette = SurfacePalette(
            idle: .clear,
            focused: Color(red: 0.26, green: 0.33, blue: 0.42, alpha: 1.0),
            pressed: Color(red: 0.72, green: 0.82, blue: 0.92, alpha: 1.0)
        ),
        chrome: SurfaceChrome = SurfaceChrome(borderWidth: 0, focusRingColor: Color(red: 0.82, green: 0.90, blue: 1.0, alpha: 0.28), focusRingWidth: 2),
        animation: ControlAnimationStyle = .default,
        onToggle: ((Bool) -> Void)? = nil
    ) -> ViewNode {
        let trackWidth: Double = 44
        let trackHeight: Double = 24
        let thumbSize: Double = 16
        let thumbInset: Double = 4

        let resolvedTrackColor: Color
        if !isEnabled {
            resolvedTrackColor = palette.disabledBackground
        } else {
            resolvedTrackColor = isOn ? onColor : offColor
        }

        let thumbX = isOn ? trackWidth - thumbSize - thumbInset : thumbInset
        let thumbColor = isEnabled ? Color.white : palette.disabledForeground

        let thumb = panel(
            frame: Rect(x: thumbX, y: thumbInset, width: thumbSize, height: thumbSize),
            backgroundColor: thumbColor,
            cornerRadius: thumbSize * 0.5,
            isHitTestVisible: false
        )

        let resolvedBorderColor = isError ? palette.errorBorder : .clear
        let track = panel(
            preferredSize: Size(width: trackWidth, height: trackHeight),
            backgroundColor: resolvedTrackColor,
            borderColor: resolvedBorderColor,
            borderWidth: isError ? 2 : 0,
            cornerRadius: trackHeight * 0.5,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [thumb]
        )

        let action: (() -> Void)? = isEnabled ? { onToggle?(!isOn) } : nil

        return button(
            runtime: runtime,
            preferredSize: preferredSize ?? Size(width: trackWidth + 8, height: trackHeight + 8),
            layoutPriority: layoutPriority,
            cornerRadius: (trackHeight + 8) * 0.5,
            palette: palette,
            chrome: chrome,
            isEnabled: isEnabled,
            clipsToBounds: false,
            layoutMode: .stack(.horizontal(padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), alignment: .center, mainAlignment: .center)),
            animation: animation,
            action: action,
            children: [track]
        )
    }

    // MARK: - Slider

    public static func slider(
        runtime: RetainedViewRuntime,
        value: Double,
        range: ClosedRange<Double> = 0...1,
        isEnabled: Bool = true,
        isError: Bool = false,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        trackColor: Color = Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0),
        filledColor: Color = Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0),
        thumbColor: Color = .white,
        palette: SurfacePalette = SurfacePalette(
            idle: .clear,
            focused: .clear,
            pressed: .clear
        ),
        chrome: SurfaceChrome = SurfaceChrome(focusRingColor: Color(red: 0.82, green: 0.90, blue: 1.0, alpha: 0.28), focusRingWidth: 2),
        onValueChanged: ((Double) -> Void)? = nil
    ) -> ViewNode {
        let sliderWidth = preferredSize?.width ?? 200
        let trackHeight: Double = 6
        let thumbSize: Double = 18
        let totalHeight: Double = max(thumbSize + 8, preferredSize?.height ?? 28)

        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        let progress = range.upperBound > range.lowerBound
            ? (clampedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            : 0

        let usableTrackWidth = max(0, sliderWidth - thumbSize)
        let thumbX = usableTrackWidth * progress
        let filledWidth = thumbX + thumbSize * 0.5

        let resolvedTrackColor = isEnabled ? trackColor : palette.disabledBackground
        let resolvedFilledColor = isEnabled ? filledColor : palette.disabledForeground
        let resolvedThumbColor = isEnabled ? thumbColor : palette.disabledForeground

        let trackY = (totalHeight - trackHeight) * 0.5
        let trackNode = panel(
            frame: Rect(x: 0, y: trackY, width: sliderWidth, height: trackHeight),
            backgroundColor: resolvedTrackColor,
            cornerRadius: trackHeight * 0.5,
            isHitTestVisible: false
        )

        let filledNode = panel(
            frame: Rect(x: 0, y: trackY, width: filledWidth, height: trackHeight),
            backgroundColor: resolvedFilledColor,
            cornerRadius: trackHeight * 0.5,
            isHitTestVisible: false
        )

        let thumbY = (totalHeight - thumbSize) * 0.5
        let thumbNode = panel(
            frame: Rect(x: thumbX, y: thumbY, width: thumbSize, height: thumbSize),
            backgroundColor: resolvedThumbColor,
            borderColor: isError ? palette.errorBorder : Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.18),
            borderWidth: isError ? 2 : 1,
            cornerRadius: thumbSize * 0.5,
            isHitTestVisible: false
        )

        let sliderRoot = panel(
            preferredSize: Size(width: sliderWidth, height: totalHeight),
            layoutPriority: layoutPriority,
            layoutMode: .absolute,
            isHitTestVisible: true,
            children: [trackNode, filledNode, thumbNode]
        )

        if isEnabled {
            let state = SliderDragState()

            sliderRoot.isFocusable = true
            sliderRoot.onFocusEnter = { [weak sliderRoot] in
                animate(.outline, sliderRoot, in: runtime, to: chrome.focusRingColor, duration: 0.12)
            }
            sliderRoot.onFocusExit = { [weak sliderRoot] in
                animate(.outline, sliderRoot, in: runtime, to: .clear, duration: 0.12)
            }
            sliderRoot.onDragStart = { point in
                state.startX = point.x
                state.startValue = clampedValue
            }
            sliderRoot.onDragChange = { _, delta in
                let deltaRatio = delta.x / max(1, usableTrackWidth)
                let rangeSpan = range.upperBound - range.lowerBound
                let newValue = min(max(state.startValue + deltaRatio * rangeSpan, range.lowerBound), range.upperBound)
                onValueChanged?(newValue)
            }
            sliderRoot.onDragEnd = { _, _ in }
        }

        return sliderRoot
    }

    // MARK: - Progress Bar

    public static func progressBar(
        value: Double,
        total: Double = 1.0,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        trackColor: Color = Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0),
        filledColor: Color = Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0),
        cornerRadius: Double = 4
    ) -> ViewNode {
        let barWidth = preferredSize?.width ?? 200
        let barHeight = preferredSize?.height ?? 8

        let progress = total > 0 ? min(max(value / total, 0), 1) : 0
        let filledWidth = barWidth * progress

        let trackNode = panel(
            frame: Rect(x: 0, y: 0, width: barWidth, height: barHeight),
            backgroundColor: trackColor,
            cornerRadius: cornerRadius,
            isHitTestVisible: false
        )

        let filledNode = panel(
            frame: Rect(x: 0, y: 0, width: filledWidth, height: barHeight),
            backgroundColor: filledColor,
            cornerRadius: cornerRadius,
            isHitTestVisible: false
        )

        return panel(
            preferredSize: Size(width: barWidth, height: barHeight),
            layoutPriority: layoutPriority,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [trackNode, filledNode]
        )
    }

    // MARK: - Radio Button

    public static func radioButton(
        runtime: RetainedViewRuntime,
        label labelText: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        isError: Bool = false,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        palette: SurfacePalette = SurfacePalette(
            idle: Color(red: 0.18, green: 0.23, blue: 0.31, alpha: 0.98),
            focused: Color(red: 0.26, green: 0.33, blue: 0.42, alpha: 1.0),
            pressed: Color(red: 0.72, green: 0.82, blue: 0.92, alpha: 1.0)
        ),
        chrome: SurfaceChrome = .elevatedButton,
        selectedColor: Color = Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0),
        animation: ControlAnimationStyle = .default,
        onSelect: (() -> Void)? = nil
    ) -> ViewNode {
        let outerSize: Double = 20
        let innerSize: Double = 10

        let resolvedBorderColor = isError ? palette.errorBorder : (isEnabled ? chrome.borderColor : palette.disabledBorder)
        let resolvedOuterBg = isEnabled ? palette.idle : palette.disabledBackground
        let resolvedForeground = isEnabled ? selectedColor : palette.disabledForeground

        var outerChildren: [ViewNode] = []
        if isSelected {
            outerChildren.append(
                panel(
                    preferredSize: Size(width: innerSize, height: innerSize),
                    backgroundColor: resolvedForeground,
                    cornerRadius: innerSize * 0.5,
                    isHitTestVisible: false
                )
            )
        }

        let outerCircle = panel(
            preferredSize: Size(width: outerSize, height: outerSize),
            backgroundColor: resolvedOuterBg,
            borderColor: resolvedBorderColor,
            borderWidth: isError ? 2 : chrome.borderWidth,
            cornerRadius: outerSize * 0.5,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isHitTestVisible: false,
            children: outerChildren
        )

        let resolvedTextColor = isEnabled ? Color.white : palette.disabledForeground
        let labelNode = label(
            labelText,
            layoutPriority: 1,
            color: resolvedTextColor,
            scale: 1.6,
            weight: .regular,
            alignment: .leading,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )

        let action: (() -> Void)? = isEnabled ? onSelect : nil

        return button(
            runtime: runtime,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            cornerRadius: 8,
            palette: palette,
            chrome: chrome,
            isEnabled: isEnabled,
            clipsToBounds: true,
            layoutMode: .stack(.horizontal(spacing: 10, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8), alignment: .center)),
            animation: animation,
            action: action,
            children: [outerCircle, labelNode]
        )
    }

    // MARK: - Dropdown

    public static func dropdown(
        runtime: RetainedViewRuntime,
        options: [String],
        selectedIndex: Int,
        isEnabled: Bool = true,
        isError: Bool = false,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        palette: SurfacePalette = SurfacePalette(
            idle: Color(red: 0.18, green: 0.23, blue: 0.31, alpha: 0.98),
            focused: Color(red: 0.26, green: 0.33, blue: 0.42, alpha: 1.0),
            pressed: Color(red: 0.72, green: 0.82, blue: 0.92, alpha: 1.0)
        ),
        chrome: SurfaceChrome = .elevatedButton,
        animation: ControlAnimationStyle = .default,
        onSelect: ((Int) -> Void)? = nil
    ) -> ViewNode {
        let resolvedForeground = isEnabled ? Color.white : palette.disabledForeground
        let selectedText = options.indices.contains(selectedIndex) ? options[selectedIndex] : ""
        let dropdownState = DropdownState()

        let titleLabel = label(
            selectedText,
            layoutPriority: 1,
            color: resolvedForeground,
            scale: 1.6,
            weight: .regular,
            alignment: .leading,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )

        let chevron = icon(
            .chevronDown,
            preferredSize: Size(width: 16, height: 16),
            color: resolvedForeground,
            scale: 1.2
        )

        let headerRow = stackPanel(
            layoutPriority: 1,
            stackLayout: .horizontal(spacing: 8, padding: .zero, alignment: .center),
            isHitTestVisible: false,
            children: [titleLabel, chevron]
        )

        var rootChildren: [ViewNode] = [headerRow]

        weak var optionsListReference: ViewNode?
        let optionNodes: [ViewNode] = options.enumerated().map { index, option in
            let isCurrentSelection = index == selectedIndex
            let optionColor = isCurrentSelection
                ? Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0)
                : resolvedForeground
            return button(
                runtime: runtime,
                title: option,
                cornerRadius: 6,
                palette: SurfacePalette(
                    idle: Color(red: 0.14, green: 0.18, blue: 0.26, alpha: 0.98),
                    focused: Color(red: 0.22, green: 0.28, blue: 0.38, alpha: 1.0),
                    pressed: Color(red: 0.60, green: 0.72, blue: 0.84, alpha: 1.0)
                ),
                chrome: SurfaceChrome(borderWidth: 0),
                titleColor: optionColor,
                titleScale: 1.5,
                titleWeight: isCurrentSelection ? .semibold : .regular,
                isEnabled: isEnabled,
                action: {
                    dropdownState.isOpen = false
                    optionsListReference?.isHidden = true
                    onSelect?(index)
                }
            )
        }

        let optionsList = stackPanel(
            backgroundColor: Color(red: 0.12, green: 0.16, blue: 0.24, alpha: 0.98),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
            borderWidth: 1,
            cornerRadius: 8,
            clipsToBounds: true,
            stackLayout: .vertical(spacing: 2, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), alignment: .stretch),
            isHitTestVisible: false,
            children: optionNodes
        )
        optionsList.isHidden = !dropdownState.isOpen
        optionsListReference = optionsList

        rootChildren.append(optionsList)

        let resolvedBorderColor = isError ? palette.errorBorder : chrome.borderColor

        let dropdownRoot = button(
            runtime: runtime,
            preferredSize: preferredSize ?? Size(width: 200, height: 36),
            layoutPriority: layoutPriority,
            cornerRadius: 10,
            palette: palette,
            chrome: SurfaceChrome(
                borderColor: resolvedBorderColor,
                borderHoveredColor: chrome.borderHoveredColor,
                borderFocusedColor: chrome.borderFocusedColor,
                borderPressedColor: chrome.borderPressedColor,
                borderWidth: isError ? 2 : chrome.borderWidth,
                focusRingColor: chrome.focusRingColor,
                focusRingWidth: chrome.focusRingWidth
            ),
            isEnabled: isEnabled,
            clipsToBounds: false,
            layoutMode: .stack(.vertical(spacing: 4, padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12), alignment: .stretch)),
            animation: animation,
            action: isEnabled ? { [weak optionsList] in
                dropdownState.isOpen = !dropdownState.isOpen
                optionsList?.isHidden = !dropdownState.isOpen
            } : nil,
            children: rootChildren
        )

        return dropdownRoot
    }

    // MARK: - Tab Bar

    public static func tabBar(
        runtime: RetainedViewRuntime,
        tabs: [String],
        selectedIndex: Int,
        isEnabled: Bool = true,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        selectedPalette: SurfacePalette = SurfacePalette(
            idle: Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0),
            focused: Color(red: 0.28, green: 0.66, blue: 1.0, alpha: 1.0),
            pressed: Color(red: 0.50, green: 0.78, blue: 1.0, alpha: 1.0)
        ),
        unselectedPalette: SurfacePalette = SurfacePalette(
            idle: Color(red: 0.18, green: 0.23, blue: 0.31, alpha: 0.98),
            focused: Color(red: 0.26, green: 0.33, blue: 0.42, alpha: 1.0),
            pressed: Color(red: 0.72, green: 0.82, blue: 0.92, alpha: 1.0)
        ),
        chrome: SurfaceChrome = .elevatedButton,
        animation: ControlAnimationStyle = .default,
        onSelect: ((Int) -> Void)? = nil
    ) -> ViewNode {
        let tabNodes: [ViewNode] = tabs.enumerated().map { index, title in
            let isSelected = index == selectedIndex
            let tabPalette = isSelected ? selectedPalette : unselectedPalette
            let titleColor = isEnabled ? Color.white : tabPalette.disabledForeground
            return button(
                runtime: runtime,
                title: title,
                layoutPriority: 1,
                cornerRadius: 8,
                palette: isEnabled ? tabPalette : SurfacePalette(
                    idle: tabPalette.disabledBackground,
                    focused: tabPalette.disabledBackground,
                    pressed: tabPalette.disabledBackground
                ),
                chrome: chrome,
                titleColor: titleColor,
                titleScale: 1.5,
                titleWeight: isSelected ? .semibold : .regular,
                isEnabled: isEnabled,
                clipsToBounds: true,
                animation: animation,
                action: isEnabled ? { onSelect?(index) } : nil
            )
        }

        return stackPanel(
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.90),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 12,
            clipsToBounds: true,
            stackLayout: .horizontal(spacing: 4, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), alignment: .stretch),
            isHitTestVisible: false,
            children: tabNodes
        )
    }

    private static func animate(
        _ property: AnimatedColorProperty,
        _ node: ViewNode?,
        in runtime: RetainedViewRuntime,
        to color: Color,
        duration: Double
    ) {
        guard let node else {
            return
        }

        runtime.animateColor(
            property,
            of: node,
            to: color,
            duration: duration,
            at: Win32Window.currentTimestampSeconds()
        )
    }
}

private extension ViewNode {
    func configured(_ update: (ViewNode) -> Void) -> ViewNode {
        update(self)
        return self
    }
}

private final class SplitViewState {
    var ratio: Double
    var dragStartRatio: Double
    var bounds: Rect

    init(ratio: Double) {
        self.ratio = ratio
        self.dragStartRatio = ratio
        self.bounds = .zero
    }
}

private final class ButtonInteractionState {
    var isHovered = false
    var isFocused = false
    var isPressed = false
}

private final class TextFieldState {
    var text: String
    var caretOffset: Int
    private var selectionRange: Range<Int>?
    private var selectionAnchorOffset: Int?

    init(text: String) {
        self.text = text
        self.caretOffset = text.count
    }

    func displayText(placeholder: String, isSecure: Bool = false) -> String {
        guard !text.isEmpty else {
            return placeholder
        }

        return isSecure ? String(repeating: "*", count: text.count) : text
    }

    func prefixBeforeCaret(isSecure: Bool = false, currentLineOnly: Bool = false) -> String {
        let prefixLength = clampedCaretOffset
        let prefix = String(text.prefix(prefixLength))
        let currentPrefix = currentLineOnly ? String(prefix.split(separator: "\n", omittingEmptySubsequences: false).last ?? "") : prefix
        return isSecure ? String(repeating: "*", count: currentPrefix.count) : currentPrefix
    }

    func prefixBeforeSelection(isSecure: Bool = false) -> String {
        guard let selectionRange = normalizedSelectionRange else {
            return ""
        }

        let prefix = String(text.prefix(selectionRange.lowerBound))
        return isSecure ? String(repeating: "*", count: prefix.count) : prefix
    }

    func selectedDisplayText(isSecure: Bool = false) -> String? {
        guard let selectionRange = normalizedSelectionRange else {
            return nil
        }

        let selectedText = String(text.dropFirst(selectionRange.lowerBound).prefix(selectionRange.count))
        return isSecure ? String(repeating: "*", count: selectedText.count) : selectedText
    }

    func selectedClipboardText(isSecure: Bool = false) -> String? {
        guard !isSecure, let selectionRange = normalizedSelectionRange else {
            return nil
        }

        return String(text.dropFirst(selectionRange.lowerBound).prefix(selectionRange.count))
    }

    func lineIndexBeforeCaret() -> Int {
        let prefix = text.prefix(clampedCaretOffset)
        return prefix.reduce(0) { count, character in
            character == "\n" ? count + 1 : count
        }
    }

    func lineIndexBeforeSelection() -> Int {
        guard let selectionRange = normalizedSelectionRange else {
            return lineIndexBeforeCaret()
        }

        let prefix = text.prefix(selectionRange.lowerBound)
        return prefix.reduce(0) { count, character in
            character == "\n" ? count + 1 : count
        }
    }

    func replace(with newText: String) -> Bool {
        let hadSelection = selectionRange != nil
        selectionRange = nil
        selectionAnchorOffset = nil
        guard text != newText else {
            caretOffset = min(caretOffset, text.count)
            return hadSelection
        }

        text = newText
        caretOffset = text.count
        return true
    }

    func selectAll() -> Bool {
        let previousSelection = normalizedSelectionRange
        let previousCaretOffset = caretOffset
        let previousSelectionAnchorOffset = selectionAnchorOffset

        guard !text.isEmpty else {
            selectionRange = nil
            selectionAnchorOffset = nil
            caretOffset = 0
            return previousSelection != nil || previousSelectionAnchorOffset != nil || previousCaretOffset != 0
        }

        selectionRange = 0..<text.count
        selectionAnchorOffset = 0
        caretOffset = text.count
        let wasAlreadySelectedAll = previousSelection?.lowerBound == 0
            && previousSelection?.upperBound == text.count
        return !wasAlreadySelectedAll
            || previousSelectionAnchorOffset != 0
            || previousCaretOffset != text.count
    }

    func insert(_ input: String) -> Bool {
        guard !input.isEmpty else {
            return false
        }

        if let selectionRange = normalizedSelectionRange {
            let replacementRange = stringRange(for: selectionRange)
            text.replaceSubrange(replacementRange, with: input)
            caretOffset = selectionRange.lowerBound + input.count
            self.selectionRange = nil
            selectionAnchorOffset = nil
            return true
        }

        let offset = clampedCaretOffset
        let insertionIndex = text.index(text.startIndex, offsetBy: offset)
        text.insert(contentsOf: input, at: insertionIndex)
        caretOffset = offset + input.count
        selectionAnchorOffset = nil
        return true
    }

    func backspace() -> Bool {
        if removeSelection() {
            return true
        }

        let offset = clampedCaretOffset
        guard offset > 0 else {
            return false
        }

        let removeEnd = text.index(text.startIndex, offsetBy: offset)
        let removeStart = text.index(before: removeEnd)
        text.removeSubrange(removeStart..<removeEnd)
        caretOffset = offset - 1
        return true
    }

    func deleteForward() -> Bool {
        if removeSelection() {
            return true
        }

        let offset = clampedCaretOffset
        guard offset < text.count else {
            return false
        }

        let removeStart = text.index(text.startIndex, offsetBy: offset)
        let removeEnd = text.index(after: removeStart)
        text.removeSubrange(removeStart..<removeEnd)
        caretOffset = offset
        return true
    }

    func cutSelectedText(isSecure: Bool = false) -> String? {
        guard let selectedText = selectedClipboardText(isSecure: isSecure), removeSelection() else {
            return nil
        }

        return selectedText
    }

    func moveCaretLeft(extendSelection: Bool = false) -> Bool {
        if extendSelection {
            return self.extendSelection(to: max(0, clampedCaretOffset - 1))
        }

        if let selectionRange = normalizedSelectionRange {
            return moveCaret(to: selectionRange.lowerBound)
        }

        let nextOffset = max(0, clampedCaretOffset - 1)
        return moveCaret(to: nextOffset)
    }

    func moveCaretRight(extendSelection: Bool = false) -> Bool {
        if extendSelection {
            return self.extendSelection(to: min(text.count, clampedCaretOffset + 1))
        }

        if let selectionRange = normalizedSelectionRange {
            return moveCaret(to: selectionRange.upperBound)
        }

        let nextOffset = min(text.count, clampedCaretOffset + 1)
        return moveCaret(to: nextOffset)
    }

    func moveCaretToStart(extendSelection: Bool = false) -> Bool {
        extendSelection ? self.extendSelection(to: 0) : moveCaret(to: 0)
    }

    func moveCaretToEnd(extendSelection: Bool = false) -> Bool {
        extendSelection ? self.extendSelection(to: text.count) : moveCaret(to: text.count)
    }

    func moveCaretUp(extendSelection: Bool = false) -> Bool {
        moveCaretVertically(delta: -1, extendSelection: extendSelection)
    }

    func moveCaretDown(extendSelection: Bool = false) -> Bool {
        moveCaretVertically(delta: 1, extendSelection: extendSelection)
    }

    func moveCaret(toTextOffset offset: Int) -> Bool {
        moveCaret(to: offset)
    }

    func beginSelection(atTextOffset offset: Int) -> Bool {
        let nextOffset = min(max(0, offset), text.count)
        let didChange = normalizedSelectionRange != nil
            || selectionAnchorOffset != nextOffset
            || caretOffset != nextOffset
        caretOffset = nextOffset
        selectionAnchorOffset = nextOffset
        selectionRange = nil
        return didChange
    }

    func extendSelection(toTextOffset offset: Int) -> Bool {
        extendSelection(to: offset)
    }

    func caretOffset(
        closestTo point: Point,
        isSecure: Bool = false,
        isMultiline: Bool = false,
        lineHeight: Double,
        measureTextWidth: (String) -> Double
    ) -> Int {
        guard !text.isEmpty else {
            return 0
        }

        let ranges = lineRanges()
        let lineIndex: Int
        if isMultiline {
            let safeLineHeight = max(1, lineHeight)
            let rawLineIndex = Int((max(0, point.y) / safeLineHeight).rounded(.down))
            lineIndex = min(max(0, rawLineIndex), max(0, ranges.count - 1))
        } else {
            lineIndex = 0
        }

        let lineRange = ranges[lineIndex]
        let lineText = String(text.dropFirst(lineRange.start).prefix(lineRange.end - lineRange.start))
        let displayText = isSecure ? String(repeating: "*", count: lineText.count) : lineText
        let column = closestColumn(in: displayText, to: max(0, point.x), measureTextWidth: measureTextWidth)
        return lineRange.start + column
    }

    private func moveCaretVertically(delta: Int, extendSelection: Bool = false) -> Bool {
        let ranges = lineRanges()
        let offset = clampedCaretOffset
        guard let currentLineIndex = ranges.firstIndex(where: { offset >= $0.start && offset <= $0.end }) else {
            return false
        }

        let targetLineIndex = currentLineIndex + delta
        guard ranges.indices.contains(targetLineIndex) else {
            return false
        }

        let currentLine = ranges[currentLineIndex]
        let targetLine = ranges[targetLineIndex]
        let currentColumn = min(max(0, offset - currentLine.start), currentLine.end - currentLine.start)
        let targetColumn = min(currentColumn, targetLine.end - targetLine.start)
        let targetOffset = targetLine.start + targetColumn
        return extendSelection ? self.extendSelection(to: targetOffset) : moveCaret(to: targetOffset)
    }

    private func moveCaret(to offset: Int) -> Bool {
        let nextOffset = min(max(0, offset), text.count)
        let hadSelection = selectionRange != nil || selectionAnchorOffset != nil
        selectionRange = nil
        selectionAnchorOffset = nil
        guard nextOffset != caretOffset else {
            return hadSelection
        }

        caretOffset = nextOffset
        return true
    }

    private func extendSelection(to offset: Int) -> Bool {
        let nextOffset = min(max(0, offset), text.count)
        let anchorOffset = selectionAnchorForExtension
        let previousSelection = normalizedSelectionRange
        let previousCaretOffset = caretOffset
        let previousSelectionAnchorOffset = selectionAnchorOffset

        caretOffset = nextOffset
        selectionAnchorOffset = anchorOffset
        if anchorOffset == nextOffset {
            selectionRange = nil
        } else {
            selectionRange = min(anchorOffset, nextOffset)..<max(anchorOffset, nextOffset)
        }

        return previousSelection != normalizedSelectionRange
            || previousCaretOffset != caretOffset
            || previousSelectionAnchorOffset != selectionAnchorOffset
    }

    private var clampedCaretOffset: Int {
        min(max(0, caretOffset), text.count)
    }

    private var selectionAnchorForExtension: Int {
        if let selectionAnchorOffset {
            return min(max(0, selectionAnchorOffset), text.count)
        }

        if let selectionRange = normalizedSelectionRange {
            return clampedCaretOffset <= selectionRange.lowerBound ? selectionRange.upperBound : selectionRange.lowerBound
        }

        return clampedCaretOffset
    }

    private var normalizedSelectionRange: Range<Int>? {
        guard let selectionRange else {
            return nil
        }

        let lowerBound = min(max(0, selectionRange.lowerBound), text.count)
        let upperBound = min(max(lowerBound, selectionRange.upperBound), text.count)
        guard lowerBound < upperBound else {
            return nil
        }

        return lowerBound..<upperBound
    }

    private func removeSelection() -> Bool {
        guard let selectionRange = normalizedSelectionRange else {
            self.selectionRange = nil
            selectionAnchorOffset = nil
            return false
        }

        text.removeSubrange(stringRange(for: selectionRange))
        caretOffset = selectionRange.lowerBound
        self.selectionRange = nil
        selectionAnchorOffset = nil
        return true
    }

    private func stringRange(for range: Range<Int>) -> Range<String.Index> {
        let lowerBound = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upperBound = text.index(text.startIndex, offsetBy: range.upperBound)
        return lowerBound..<upperBound
    }

    private func closestColumn(
        in displayText: String,
        to x: Double,
        measureTextWidth: (String) -> Double
    ) -> Int {
        guard !displayText.isEmpty else {
            return 0
        }

        var bestColumn = 0
        var bestDistance = abs(x)

        for column in 1...displayText.count {
            let width = measureTextWidth(String(displayText.prefix(column)))
            let distance = abs(width - x)
            if distance < bestDistance {
                bestColumn = column
                bestDistance = distance
            }
        }

        return bestColumn
    }

    private func lineRanges() -> [(start: Int, end: Int)] {
        var ranges: [(start: Int, end: Int)] = []
        var lineStart = 0
        var offset = 0

        for character in text {
            if character == "\n" {
                ranges.append((start: lineStart, end: offset))
                lineStart = offset + 1
            }
            offset += 1
        }

        ranges.append((start: lineStart, end: offset))
        return ranges
    }
}

private func sanitizedTextInput(_ input: String, allowsNewlines: Bool) -> String {
    var sanitizedInput = ""
    var previousWasCarriageReturn = false

    for scalar in input.unicodeScalars {
        switch scalar.value {
        case 0x0D where allowsNewlines:
            sanitizedInput.append("\n")
            previousWasCarriageReturn = true
        case 0x0A where allowsNewlines:
            if !previousWasCarriageReturn {
                sanitizedInput.append("\n")
            }
            previousWasCarriageReturn = false
        case 0x20...0x10FFFF where scalar.value != 0x7F:
            sanitizedInput.unicodeScalars.append(scalar)
            previousWasCarriageReturn = false
        default:
            previousWasCarriageReturn = false
        }
    }

    return sanitizedInput
}

private final class SliderDragState {
    var startX: Double = 0
    var startValue: Double = 0
}

private final class DropdownState {
    var isOpen = false
}
