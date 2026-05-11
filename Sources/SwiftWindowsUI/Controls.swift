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
        clipsToBounds: Bool = false,
        layoutMode: ViewLayoutMode = .absolute,
        isEnabled: Bool = true,
        repeatBehavior: RetainedButtonRepeatBehavior = .automatic,
        animation: ControlAnimationStyle = .default,
        action: (() -> Void)? = nil,
        children: [ViewNode] = []
    ) -> ViewNode {
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
            isHitTestVisible: isEnabled,
            children: children
        )

        guard isEnabled else {
            return node
        }

        node.buttonRepeatBehavior = repeatBehavior
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
        node.onRepeatActivate = {
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
        nativeFontSize: Double? = nil,
        alignment: TextHorizontalAlignment = .center,
        insets: EdgeInsets = .zero,
        letterSpacing: Double = 1,
        lineSpacing: Double = 2,
        lineBreakMode: TextLineBreakMode = .truncateTail,
        maximumNumberOfLines: Int? = nil,
        minimumScaleFactor: Double = 1,
        reservesLineLimitSpace: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        enableKerning: Bool = true
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
                letterSpacing: letterSpacing,
                lineSpacing: lineSpacing,
                insets: insets,
                fontFamily: fontFamily,
                nativeFontSize: nativeFontSize,
                weight: weight,
                lineBreakMode: lineBreakMode,
                maximumNumberOfLines: maximumNumberOfLines,
                minimumScaleFactor: minimumScaleFactor,
                reservesLineLimitSpace: reservesLineLimitSpace,
                underline: underline,
                strikethrough: strikethrough,
                enableKerning: enableKerning
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

    public static func image(
        _ bitmap: BitmapSurface,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        isHitTestVisible: Bool = false
    ) -> ViewNode {
        ViewNode(
            frame: frame,
            bitmapSurface: bitmap,
            preferredSize: preferredSize,
            isHitTestVisible: isHitTestVisible
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
        clipsToBounds: Bool = true,
        isEnabled: Bool = true,
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
            clipsToBounds: clipsToBounds,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isEnabled: isEnabled,
            animation: animation,
            action: action,
            children: [labelNode]
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
            clipsToBounds: true,
            layoutMode: .stack(.horizontal(spacing: 10, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8), alignment: .center)),
            isEnabled: isEnabled,
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
            clipsToBounds: false,
            layoutMode: .stack(.horizontal(padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), alignment: .center, mainAlignment: .center)),
            isEnabled: isEnabled,
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
        onValueChanged: ((Double) -> Void)? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
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
                onEditingChanged?(true)
            }
            sliderRoot.onDragChange = { _, delta in
                let deltaRatio = delta.x / max(1, usableTrackWidth)
                let rangeSpan = range.upperBound - range.lowerBound
                let newValue = min(max(state.startValue + deltaRatio * rangeSpan, range.lowerBound), range.upperBound)
                onValueChanged?(newValue)
            }
            sliderRoot.onDragEnd = { _, _ in
                onEditingChanged?(false)
            }
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
            clipsToBounds: true,
            layoutMode: .stack(.horizontal(spacing: 10, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8), alignment: .center)),
            isEnabled: isEnabled,
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
            clipsToBounds: false,
            layoutMode: .stack(.vertical(spacing: 4, padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12), alignment: .stretch)),
            isEnabled: isEnabled,
            animation: animation,
            action: isEnabled ? {
                dropdownState.isOpen = !dropdownState.isOpen
                optionsList.isHidden = !dropdownState.isOpen
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
                clipsToBounds: true,
                isEnabled: isEnabled,
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

private final class SliderDragState {
    var startX: Double = 0
    var startValue: Double = 0
}

private final class DropdownState {
    var isOpen = false
}
