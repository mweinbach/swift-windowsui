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
    public var focused: Color
    public var pressed: Color
    public var activated: Color

    public init(idle: Color, focused: Color, pressed: Color, activated: Color? = nil) {
        self.idle = idle
        self.focused = focused
        self.pressed = pressed
        self.activated = activated ?? focused
    }
}

public struct SurfaceChrome: Sendable {
    public var borderColor: Color
    public var borderWidth: Double
    public var focusRingColor: Color
    public var focusRingWidth: Double
    public var shadowColor: Color
    public var shadowOffset: Point
    public var shadowSpread: Double

    public init(
        borderColor: Color = .clear,
        borderWidth: Double = 0,
        focusRingColor: Color = .clear,
        focusRingWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0
    ) {
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.focusRingColor = focusRingColor
        self.focusRingWidth = focusRingWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowSpread = shadowSpread
    }

    public static let elevatedButton = SurfaceChrome(
        borderColor: Color(red: 0.72, green: 0.81, blue: 0.90, alpha: 0.20),
        borderWidth: 1,
        focusRingColor: Color(red: 0.88, green: 0.96, blue: 1.0, alpha: 0.44),
        focusRingWidth: 3,
        shadowColor: Color(red: 0.01, green: 0.03, blue: 0.06, alpha: 0.30),
        shadowOffset: Point(x: 0, y: 10),
        shadowSpread: 6
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
        backgroundColor: Color = Color(red: 0.11, green: 0.15, blue: 0.21, alpha: 0.98),
        backgroundGradient: LinearGradient? = nil,
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
            shadowOffset: Point(x: 0, y: 12),
            shadowSpread: 6,
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
        backgroundColor: Color = Color(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.98),
        backgroundGradient: LinearGradient? = nil,
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
            shadowOffset: Point(x: 0, y: 14),
            shadowSpread: 7,
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
        animation: ControlAnimationStyle = .default,
        action: (() -> Void)? = nil,
        children: [ViewNode] = []
    ) -> ViewNode {
        let node = panel(
            frame: frame,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            backgroundColor: palette.idle,
            borderColor: chrome.borderColor,
            borderWidth: chrome.borderWidth,
            outlineColor: .clear,
            outlineWidth: chrome.focusRingWidth,
            shadowColor: chrome.shadowColor,
            shadowOffset: chrome.shadowOffset,
            shadowSpread: chrome.shadowSpread,
            cornerRadius: cornerRadius,
            clipsToBounds: clipsToBounds,
            layoutMode: layoutMode,
            isHitTestVisible: true,
            children: children
        )

        node.isFocusable = true
        node.onFocusEnter = { [weak node] in
            animate(.background, node, in: runtime, to: palette.focused, duration: animation.focusDuration)
            animate(.outline, node, in: runtime, to: chrome.focusRingColor, duration: animation.focusDuration)
        }
        node.onFocusExit = { [weak node] in
            animate(.background, node, in: runtime, to: palette.idle, duration: animation.focusDuration)
            animate(.outline, node, in: runtime, to: .clear, duration: animation.focusDuration)
        }
        node.onPointerDown = { [weak node] in
            animate(.background, node, in: runtime, to: palette.pressed, duration: animation.pressDuration)
        }
        node.onPointerUpInside = { [weak node] in
            animate(.background, node, in: runtime, to: palette.focused, duration: animation.focusDuration)
        }
        node.onPointerUpOutside = { [weak node] in
            animate(.background, node, in: runtime, to: palette.focused, duration: animation.focusDuration)
        }
        node.onActivate = { [weak node] in
            animate(.background, node, in: runtime, to: palette.activated, duration: animation.activationDuration)
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
        clipsToBounds: Bool = true,
        animation: ControlAnimationStyle = .default,
        action: (() -> Void)? = nil
    ) -> ViewNode {
        let labelNode = label(
            title,
            layoutPriority: 1,
            color: titleColor,
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
            animation: animation,
            action: action,
            children: [labelNode]
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
