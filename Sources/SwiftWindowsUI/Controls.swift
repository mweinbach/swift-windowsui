import SwiftWindowsCore
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

@MainActor
public enum Controls {
    public static func panel(
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        backgroundColor: Color? = nil,
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
            isHitTestVisible: isHitTestVisible,
            children: children
        )
    }

    public static func stackPanel(
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
        stackLayout: StackLayout,
        isHitTestVisible: Bool = true,
        children: [ViewNode] = []
    ) -> ViewNode {
        panel(
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
            layoutMode: .stack(stackLayout),
            isHitTestVisible: isHitTestVisible,
            children: children
        )
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
        children: [ViewNode] = []
    ) -> ViewNode {
        panel(
            frame: frame,
            preferredSize: preferredSize,
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
        }
    }

    public static func button(
        runtime: RetainedViewRuntime,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
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
        color: Color = .white,
        scale: Double = 2,
        alignment: TextHorizontalAlignment = .center,
        insets: EdgeInsets = .zero
    ) -> ViewNode {
        panel(
            frame: frame,
            preferredSize: preferredSize,
            backgroundColor: nil,
            text: text,
            textStyle: PixelTextStyle(color: color, scale: scale, alignment: alignment, insets: insets),
            isHitTestVisible: false
        )
    }

    public static func button(
        runtime: RetainedViewRuntime,
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
    ) -> ViewNode {
        let labelNode = label(title, color: titleColor, scale: titleScale)
        return button(
            runtime: runtime,
            frame: frame,
            preferredSize: preferredSize,
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
