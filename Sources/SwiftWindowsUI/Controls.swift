import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsLayout

import SwiftWindowsPlatform

public struct ControlAnimationStyle: Sendable {
    public var focusDuration: Double
    public var pressDuration: Double

    /// Uniform scale a control is drawn at while the pointer is held down.
    ///
    /// **`1` — no geometric change at all — is the macOS value, and the
    /// default.** An AppKit control's press feedback is a *fill* change and
    /// nothing else: `NSButtonCell` highlights (the bezel darkens in the
    /// light appearance, brightens in the dark one) and the cell is drawn in
    /// exactly the frame it had at rest. `NSSegmentedControl`,
    /// `NSPopUpButton`, `NSStepper` and `NSSwitch` all behave the same way.
    /// No AppKit control shrinks under the pointer, in any macOS from Big Sur
    /// through Sonoma.
    ///
    /// This stack shipped `0.97` as the default for a while, documented as
    /// "the Big Sur feel". That was wrong about the platform: a press shrink
    /// is an iOS / custom-`ButtonStyle` idiom
    /// (`scaleEffect(configuration.isPressed ? 0.97 : 1)`), and macOS parity
    /// is the standard this project is held to. It survived as long as it did
    /// because nothing rendered a pressed control until the gallery's
    /// interaction-state tier existed, and by then the shrink was reading as
    /// intentional.
    ///
    /// The machinery is still here, because a *style* may legitimately want
    /// it — see `ControlAnimationStyle.tactilePressedScale`. What changed is
    /// which behaviour a control gets when it does not ask.
    public var pressedScale: Double

    /// The shrink-on-press affordance, for a style that deliberately opts
    /// into it:
    /// `ControlAnimationStyle(pressedScale: ControlAnimationStyle.tactilePressedScale)`.
    ///
    /// Not a macOS control behaviour. Anything built for parity leaves
    /// `pressedScale` at its default of `1`.
    public static let tactilePressedScale: Double = 0.97

    public init(
        focusDuration: Double = 0.18,
        pressDuration: Double = 0.14,
        pressedScale: Double = 1
    ) {
        self.focusDuration = focusDuration
        self.pressDuration = pressDuration
        self.pressedScale = pressedScale
    }

    public static let `default` = ControlAnimationStyle()
}
public struct SurfacePalette: Sendable {
    public var idle: Color
    public var hovered: Color
    public var focused: Color
    public var pressed: Color
    public var disabledBackground: Color
    public var disabledForeground: Color
    public var disabledBorder: Color
    public var errorBorder: Color

    /// Opacity the control's content is drawn at while the pointer is held
    /// down. `1` — the default — leaves the content alone, which is right for
    /// every ramp above that answers a press with a fill.
    ///
    /// It exists for the ramps that have no fill to change. An AppKit
    /// borderless button (`isBordered == false`, i.e. `highlightsBy` of
    /// `contentsCellMask`) draws no bezel at all and answers a press by
    /// darkening its *contents*; SwiftUI's `.plain` / `.borderless` / `.link`
    /// styles are the same button. Those ramps are transparent in every
    /// state, so with the geometric press scale gone (see
    /// `ControlAnimationStyle.pressedScale`) they would otherwise have no
    /// press feedback whatsoever.
    public var pressedContentOpacity: Double

    public init(
        idle: Color,
        hovered: Color? = nil,
        focused: Color,
        pressed: Color,
        disabledBackground: Color = Color(red: 0.22, green: 0.24, blue: 0.28, alpha: 0.60),
        disabledForeground: Color = Color(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.70),
        disabledBorder: Color = Color(red: 0.40, green: 0.42, blue: 0.46, alpha: 0.30),
        errorBorder: Color = Color(red: 0.90, green: 0.22, blue: 0.20, alpha: 0.90),
        pressedContentOpacity: Double = 1
    ) {
        self.idle = idle
        self.hovered = hovered ?? focused
        self.focused = focused
        self.pressed = pressed
        self.disabledBackground = disabledBackground
        self.disabledForeground = disabledForeground
        self.disabledBorder = disabledBorder
        self.errorBorder = errorBorder
        self.pressedContentOpacity = pressedContentOpacity
    }

    public static let `default` = SurfacePalette(
        idle: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.92),
        hovered: Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 0.92),
        focused: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.92),
        pressed: Color(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.92)
    )
}
public enum BorderStyle: Sendable, Equatable {
    case solid
    case dashed
    case dotted
    // swift-format-ignore: AlwaysUseLowerCamelCase
    case double_  // trailing underscore avoids the `Double` type name conflict
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
    public var shadowOffset: Point
    public var shadowSpread: Double

    public init(
        borderColor: Color = .clear,
        borderHoveredColor: Color? = nil,
        borderFocusedColor: Color? = nil,
        borderPressedColor: Color? = nil,
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
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0
    ) {
        self.borderColor = borderColor
        self.borderHoveredColor = borderHoveredColor ?? borderColor
        self.borderFocusedColor = borderFocusedColor ?? borderHoveredColor ?? borderColor
        self.borderPressedColor = borderPressedColor ?? borderFocusedColor ?? borderColor
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
        self.shadowOffset = shadowOffset
        self.shadowSpread = shadowSpread
    }

    /// Returns whether per-side border widths are set, overriding the uniform `borderWidth`.
    public var hasPerSideBorders: Bool {
        borderTopWidth != nil || borderRightWidth != nil || borderBottomWidth != nil || borderLeftWidth != nil
    }

    /// Resolved width for a given side, falling back to uniform `borderWidth`.
    public func resolvedBorderWidth(top: Bool = false, right: Bool = false, bottom: Bool = false, left: Bool = false)
        -> Double
    {
        if top, let w = borderTopWidth { return w }
        if right, let w = borderRightWidth { return w }
        if bottom, let w = borderBottomWidth { return w }
        if left, let w = borderLeftWidth { return w }
        return borderWidth
    }

    /// Keyboard focus-ring stroke width. Mirrors
    /// `MacOSControlMetrics.FocusRing.strokeWidth`, which lives one target
    /// up in `WinSwiftUI` and so cannot be referenced from here — the two
    /// are asserted equal by `MacOSDesignParityTests`. They used to
    /// disagree (2 here, 4 there) with both pinned as "the" macOS value.
    ///
    /// A 2pt halo outside a 1px accent border. 4pt of ring around a 6pt
    /// corner swallows the corner, so the focused control loses the shape
    /// that identifies it at the moment you need to find it.
    public static let focusRingStrokeWidth: Double = 2

    /// Neutral contact shadow a raised control casts: 1pt down, black at low
    /// alpha. A control shadow is never tinted with the accent or role
    /// colour, and it is never larger than the gutter it sits in.
    public static let ambientShadowColor = Color(red: 0, green: 0, blue: 0, alpha: 0.06)

    /// The design accent as **ink**, at the focus-ring alpha. Mirrors
    /// `ControlPalette.accentRing`; the retained defaults cannot reach the
    /// palette, so this is the appearance-blind stand-in for chrome built
    /// without one.
    public static let focusRingAccentColor = Color(red: 0.357, green: 0.302, blue: 0.878, alpha: 0.45)

    public static let elevatedButton = SurfaceChrome(
        borderColor: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.09),
        borderHoveredColor: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.14),
        borderFocusedColor: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.14),
        borderPressedColor: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.14),
        borderWidth: 1,
        focusRingColor: SurfaceChrome.focusRingAccentColor,
        focusRingWidth: SurfaceChrome.focusRingStrokeWidth,
        shadowColor: SurfaceChrome.ambientShadowColor,
        shadowHoveredColor: SurfaceChrome.ambientShadowColor,
        shadowFocusedColor: SurfaceChrome.ambientShadowColor,
        shadowPressedColor: .clear,
        shadowOffset: Point(x: 0, y: 1),
        shadowSpread: 1
    )

    public static let `default` = SurfaceChrome(
        borderColor: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.09),
        borderWidth: 1,
        cornerRadii: CornerRadii(uniform: 6),
        focusRingColor: SurfaceChrome.focusRingAccentColor,
        focusRingWidth: SurfaceChrome.focusRingStrokeWidth
    )
}
public enum SplitAxis: Sendable {
    case horizontal
    case vertical
}
public enum SymbolIcon: String, Sendable, CaseIterable {
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
    case chevronUp = "\u{E70E}"
    case chevronLeft = "\u{E76B}"
    case chevronRight = "\u{E76C}"
    case plus = "\u{E710}"
    case minus = "\u{E738}"
    case xmark = "\u{E711}"
    case play = "\u{E768}"
    case pause = "\u{E769}"
    case arrowLeft = "\u{E72B}"
    case arrowRight = "\u{E72A}"
    case arrowUp = "\u{E74A}"
    case arrowDown = "\u{E74B}"
    case ellipsis = "\u{E712}"
    case trash = "\u{E74D}"
    case pencil = "\u{E70F}"
    case person = "\u{E77B7}"
    case house = "\u{E80F}"
    case star = "\u{E734}"
    case starFill = "\u{E735}"
    case heart = "\u{EB51}"
    case heartFill = "\u{EB52}"
    case bell = "\u{EA8F}"
    case camera = "\u{E722}"
    case globe = "\u{E774}"
    case mapPin = "\u{E707}"

    /// Icon font families in fallback order: Fluent Icons ships with
    /// Windows 11; Windows 10 only has MDL2 Assets (largely the same
    /// private-use codepoints).
    public static let fontFamilyFallbacks = ["Segoe Fluent Icons", "Segoe MDL2 Assets"]

    /// The single private-use character backing this symbol.
    public var character: Character {
        rawValue.first ?? " "
    }
}
@MainActor
public enum Controls {
    /// Darkened variant of a color with its alpha preserved. Used for the
    /// bottom stop of control-surface gradient sheens.
    public nonisolated static func shaded(_ color: Color, by factor: Float) -> Color {
        Color(
            red: color.red * factor,
            green: color.green * factor,
            blue: color.blue * factor,
            alpha: color.alpha
        )
    }

    /// Vertical gradient sheen for control surfaces. The painter resolves a
    /// gradient quad's top stop from the node's (animated) background color
    /// and the bottom stop from this gradient's end color, so state color
    /// animations stay fully visible while the surface reads as the subtle
    /// top-lighter gradient of macOS Big Sur+ controls.
    /// Luminance the bottom stop of a control sheen keeps.
    ///
    /// The glossy bevel is long retired; a surface here carries a travel at
    /// the *edge of perception* — a couple of levels of 255 between its top
    /// and its bottom — and that slight amount is the whole difference
    /// between a surface and a rectangle of paint. 0.82 (an 18% drop) made
    /// every control a styled div; 0.96 was still enough to see on a card
    /// the size of a settings box. 0.98 is the −0.02 composite step the
    /// design system specifies. Pinned in docs/MacOSDesignParity.md.
    public nonisolated static let surfaceSheenFactor: Float = 0.98

    /// Luminance the bottom stop of a *recessed* groove keeps — a slider or
    /// progress track, a segmented groove, a field well. Deeper than a
    /// surface, because a groove is genuinely shaded rather than lit, but
    /// near-flat all the same.
    public nonisolated static let grooveSheenFactor: Float = 0.95

    /// How far a control surface's bottom stop falls, in luminance the window
    /// actually shows rather than in the surface's own channels.
    ///
    /// It is the complement of `surfaceSheenFactor` — the same 0.04 step,
    /// stated as a distance instead of a ratio — because macOS's own bezels
    /// travel about the same *absolute* amount in both appearances: a light
    /// push button runs #FFFFFF → #F5F5F5 and a dark one #545456 → #48484A,
    /// 10 and 12 levels of 255.
    public nonisolated static var surfaceSheenDrop: Float { 1 - surfaceSheenFactor }

    /// Most of itself a surface may lose to its own sheen.
    ///
    /// The absolute step above is calibrated against a near-white bezel,
    /// where it is 4% of the surface. On a dim surface the same distance is
    /// most of what the surface has — a `white(0.10)` control over a black
    /// page is 25/255, and a 10-level drop dissolves its bottom edge into the
    /// window. macOS's dark push bezel travels 14% of itself; this ceiling is
    /// that, rounded, and it binds only where the absolute step would eat the
    /// control.
    public nonisolated static let surfaceSheenRelativeCeiling: Float = 0.16

    /// How much brightness a surface contributes to the window: its greatest
    /// channel, weighted by how much of the surface there is.
    ///
    /// The greatest channel rather than a luminance sum, because the sheen is
    /// a fall in the surface's *own* brightness. A weighted sum reads
    /// `#007AFF` as a dim colour (blue carries 11% of luminance), so an
    /// absolute step against it would shade a full-strength accent three
    /// times as hard as the near-white bezel beside it. Value says both are
    /// at full brightness, and both take the same 4% fall — which is what
    /// keeps this arithmetic identical to `shaded(_:by: surfaceSheenFactor)`
    /// for every opaque, full-value surface: white bezels, accent fills,
    /// destructive reds, slider and progress bars.
    public nonisolated static func compositeValue(_ color: Color) -> Float {
        max(color.red, max(color.green, color.blue)) * color.alpha
    }

    /// The bottom stop of a control-surface sheen.
    ///
    /// `shaded(_:by: surfaceSheenFactor)` scales the channels and leaves alpha
    /// alone. That is the right arithmetic for an opaque bezel and very nearly
    /// a no-op for a translucent one: a dark-appearance control surface is
    /// `white(0.10)`, a wash whose composite is `0.10 · 1 + 0.90 · window`, so
    /// scaling `(1,1,1)` to `(0.96,0.96,0.96)` moved a 25/255 button by a
    /// single level. Every bordered button in the dark appearance was a flat
    /// fill while the light one carried its gradient — out of one shared
    /// "sheen".
    ///
    /// Solving for the factor that lands the surface `drop` lower in what the
    /// window shows fixes that without giving up hue: the channels still scale
    /// together, so a grey stays grey and an accent stays its own colour. On
    /// any opaque full-value surface the factor comes out at exactly
    /// `surfaceSheenFactor`, which is why nothing already correct moves.
    public nonisolated static func sheenBottom(_ color: Color, drop: Float) -> Color {
        let value = compositeValue(color)
        guard color.alpha > 0, value > 0, drop > 0 else {
            return color
        }
        let effectiveDrop = min(drop, value * surfaceSheenRelativeCeiling)
        return shaded(color, by: max(0, (value - effectiveDrop) / value))
    }

    public static func backgroundSheen(for color: Color) -> GradientType? {
        guard color.alpha > 0 else {
            return nil
        }
        return .linear(LinearGradient(startColor: color, endColor: sheenBottom(color, drop: surfaceSheenDrop)))
    }

    /// How much of its strength a bezel's ring keeps at its far edge.
    public nonisolated static let borderSheenFadeFactor: Float = 0.55

    /// Vertical border gradient — the hairline a bezel is closed with.
    ///
    /// macOS lights a control from above, so its ring is *lightest* along the
    /// top edge in both appearances. That is not the same as strongest at the
    /// top, and the difference is the whole light appearance: a dark-mode ring
    /// is drawn in white, where lightest means full strength on top and a fade
    /// downward; a light-mode ring is drawn in black, where the identical
    /// lighting reads the other way round — the ring withdraws at the top and
    /// closes along the bottom, which is the faint under-line a macOS light
    /// push button carries. Fading downward regardless was a dark-mode idea,
    /// and in light mode it drew the shadow edge along the top of every
    /// control in the app.
    ///
    /// The ring's own colour says which it is: a ring you can see against a
    /// dark window is a highlight, a ring you can see against a light one is a
    /// shadow, and nothing else in the palette rings a control in a mid-tone.
    public static func borderSheen(for color: Color) -> GradientType? {
        guard color.alpha > 0 else {
            return nil
        }
        let faded = color.multipliedAlpha(by: borderSheenFadeFactor)
        let isHighlightRing = max(color.red, max(color.green, color.blue)) > 0.5
        return .linear(
            isHighlightRing
                ? LinearGradient(startColor: color, endColor: faded)
                : LinearGradient(startColor: faded, endColor: color)
        )
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
        borderGradient: GradientType? = nil,
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
            borderGradient: borderGradient,
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
        backgroundGradient: GradientType? = nil,
        text: String? = nil,
        textStyle: PixelTextStyle = PixelTextStyle(color: .white),
        borderColor: Color = .clear,
        borderGradient: GradientType? = nil,
        borderWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        clipsToBounds: Bool = false,
        blurRadius: Double = 0,
        stackLayout: StackLayout,
        isHitTestVisible: Bool = true,
        children: [ViewNode] = []
    ) -> ViewNode {
        let node = panel(
            frame: frame,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            backgroundColor: backgroundColor,
            backgroundGradient: backgroundGradient,
            text: text,
            textStyle: textStyle,
            borderColor: borderColor,
            borderGradient: borderGradient,
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
        if blurRadius > 0 {
            node.blurRadius = blurRadius
        }
        return node
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
        scrollStep: Double = ViewNode.defaultScrollLineHeight,
        scrollIndicatorColor: Color = Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.26),
        scrollIndicatorHoverColor: Color = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
        scrollIndicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.72),
        scrollIndicatorThickness: Double = 6,
        scrollIndicatorInsets: EdgeInsets = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
        scrollIndicatorAutoHides: Bool = false,
        initialScrollAnchor: RetainedScrollAnchor? = nil,
        scrollSizeChangeAnchor: RetainedScrollAnchor? = nil,
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
            node.scrollIndicatorAutoHides = scrollIndicatorAutoHides
            // The idle colour is the *revealed* tone in both modes; what the
            // thumb is painted with right now is the resting one.
            node.scrollIndicatorIdleColor = scrollIndicatorColor
            node.scrollIndicatorColor = scrollIndicatorAutoHides ? .clear : scrollIndicatorColor
            node.scrollIndicatorHoverColor = scrollIndicatorHoverColor
            node.scrollIndicatorActiveColor = scrollIndicatorActiveColor
            node.scrollIndicatorThickness = scrollIndicatorThickness
            node.scrollIndicatorInsets = scrollIndicatorInsets
            node.initialScrollAnchor = initialScrollAnchor
            node.scrollSizeChangeAnchor = scrollSizeChangeAnchor
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
        let primaryContainer = panel(
            clipsToBounds: true, layoutMode: .absolute, isHitTestVisible: false, children: primary)
        let secondaryContainer = panel(
            clipsToBounds: true, layoutMode: .absolute, isHitTestVisible: false, children: secondary)
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
            let clampedPrimary = min(
                max(availableExtent * state.ratio, minPrimaryExtent),
                max(minPrimaryExtent, availableExtent - minSecondaryExtent))
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
                secondaryFrame = Rect(
                    x: resolvedPrimary + dividerThickness, y: 0,
                    width: max(0, bounds.size.width - resolvedPrimary - dividerThickness), height: bounds.size.height)
            case .vertical:
                primaryFrame = Rect(x: 0, y: 0, width: bounds.size.width, height: resolvedPrimary)
                dividerFrame = Rect(x: 0, y: resolvedPrimary, width: bounds.size.width, height: dividerThickness)
                secondaryFrame = Rect(
                    x: 0, y: resolvedPrimary + dividerThickness, width: bounds.size.width,
                    height: max(0, bounds.size.height - resolvedPrimary - dividerThickness))
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
                let primaryChildFrame = Rect(
                    x: 0, y: 0, width: primaryFrame.size.width, height: primaryFrame.size.height)
                if primaryContainer.children[0].frame != primaryChildFrame {
                    primaryContainer.children[0].frame = primaryChildFrame
                }
            }

            if secondaryContainer.children.count == 1 {
                let secondaryChildFrame = Rect(
                    x: 0, y: 0, width: secondaryFrame.size.width, height: secondaryFrame.size.height)
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
        backgroundGradient: GradientType? = nil,
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
        backgroundGradient: GradientType? = nil,
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
        scrollStep: Double = ViewNode.defaultScrollLineHeight,
        scrollIndicatorColor: Color = Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.26),
        scrollIndicatorHoverColor: Color = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
        scrollIndicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.72),
        scrollIndicatorThickness: Double = 6,
        headerColor: Color = Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.96),
        headerScale: Double = 1.6,
        isHitTestVisible: Bool = false,
        children: [ViewNode] = []
    ) -> ViewNode {
        let content =
            [
                label(
                    title, color: headerColor, scale: headerScale, weight: .semibold, alignment: .leading,
                    lineBreakMode: .truncateTail, maximumNumberOfLines: 1)
            ] + children
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
                label(
                    title, color: .white, scale: 1.8, weight: .semibold, alignment: .leading,
                    lineBreakMode: .truncateTail, maximumNumberOfLines: 1),
                label(
                    detail, color: Color(red: 0.76, green: 0.86, blue: 0.95, alpha: 0.86), scale: 1.2,
                    alignment: .leading, lineBreakMode: .truncateTail, maximumNumberOfLines: 1),
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
                    children: [
                        Self.icon(symbol, preferredSize: Size(width: 24, height: 24), color: accentColor, scale: 1.5)
                    ]
                )
            )
        }
        contentChildren.append(labels)

        return button(
            runtime: runtime,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            // `Radius.lg` — a card-shaped button is still a card, and nothing
            // in this design system rounds past 12.
            cornerRadius: 10,
            palette: palette,
            chrome: chrome,
            layoutMode: .stack(
                .horizontal(
                    spacing: 16, padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16), alignment: .center
                )),
            appliesSurfaceSheen: true,
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
        appliesSurfaceSheen: Bool = false,
        action: (() -> Void)? = nil,
        children: [ViewNode] = []
    ) -> ViewNode {
        let node = panel(
            frame: frame,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            backgroundColor: isEnabled ? palette.idle : palette.disabledBackground,
            backgroundGradient: appliesSurfaceSheen
                ? backgroundSheen(for: isEnabled ? palette.idle : palette.disabledBackground) : nil,
            borderColor: isEnabled ? chrome.borderColor : palette.disabledBorder,
            borderGradient: appliesSurfaceSheen
                ? borderSheen(for: isEnabled ? chrome.borderColor : palette.disabledBorder) : nil,
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

        // Default accessibility metadata: every retained button is a button
        // element whose name folds in from its content. Explicit
        // accessibility modifiers apply after the builder and always win.
        node.accessibilityTraits.formUnion(.isButton)
        node.accessibilityChildBehavior = .combine

        guard isEnabled else {
            return node
        }

        node.buttonRepeatBehavior = repeatBehavior
        node.isFocusable = true

        // The ramp goes on the node as data; the runtime resolves it against
        // the pointer and focus state it alone knows, and re-applies it after
        // every rebuild. This used to be six closures over a build-scope
        // `ButtonInteractionState`, which had two defects a fill ramp cannot
        // survive: `updateNodeProperties` overwrote the animated colours with
        // the rebuilt *idle* values (so any `@State` change de-hovered every
        // control under the pointer, permanently — the pointer is already
        // inside, so `updateHoverTarget` never re-enters), and the closures
        // themselves were copied onto the retained node still holding the
        // discarded build's node, so after one rebuild they animated an
        // orphan and hover never worked on that control again.
        //
        // There is no separate "activated" colour any more. It was pinned to
        // `pressed` in every appearance-resolved ramp, so the activation tween
        // parked the control on its held-down fill and nothing was scheduled
        // to leave it: a clicked button stayed pressed until the pointer left.
        // AppKit has no such state — `NSButtonCell` releases its highlight on
        // mouseUp and *then* sends the action — so pointer-up resolves to
        // whatever the pointer is actually doing, which is hover.
        node.interactionSurface = RetainedInteractionSurface(
            idleBackground: palette.idle,
            hoveredBackground: palette.hovered,
            focusedBackground: palette.focused,
            pressedBackground: palette.pressed,
            idleBorder: chrome.borderColor,
            hoveredBorder: chrome.borderHoveredColor,
            focusedBorder: chrome.borderFocusedColor,
            pressedBorder: chrome.borderPressedColor,
            idleShadow: chrome.shadowColor,
            hoveredShadow: chrome.shadowHoveredColor,
            focusedShadow: chrome.shadowFocusedColor,
            pressedShadow: chrome.shadowPressedColor,
            focusRingColor: chrome.focusRingColor,
            focusRingWidth: chrome.focusRingWidth,
            pressedScale: animation.pressedScale,
            pressedContentOpacity: palette.pressedContentOpacity,
            appliesSurfaceSheen: appliesSurfaceSheen,
            hoverDuration: animation.focusDuration,
            pressDuration: animation.pressDuration,
            focusDuration: animation.focusDuration
        )
        // The ring grows out of the edge, so it starts with no width at all.
        node.outlineWidth = 0

        node.onActivate = {
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
        isItalic: Bool = false,
        monospacedDigits: Bool = false,
        lowercaseSmallCaps: Bool = false,
        uppercaseSmallCaps: Bool = false,
        fontFamily: String = "Segoe UI",
        nativeFontSize: Double? = nil,
        fontWidth: TextFontWidth = .standard,
        alignment: TextHorizontalAlignment = .center,
        insets: EdgeInsets = .zero,
        letterSpacing: Double = 1,
        nativeLetterSpacing: Double? = nil,
        lineSpacing: Double = 2,
        lineBreakMode: TextLineBreakMode = .truncateTail,
        maximumNumberOfLines: Int? = nil,
        minimumNumberOfLines: Int? = nil,
        minimumScaleFactor: Double = 1,
        reservesLineLimitSpace: Bool = false,
        underline: Bool = false,
        underlinePattern: TextDecorationPattern = .solid,
        underlineColor: Color? = nil,
        strikethrough: Bool = false,
        strikethroughPattern: TextDecorationPattern = .solid,
        strikethroughColor: Color? = nil,
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
                nativeLetterSpacing: nativeLetterSpacing,
                lineSpacing: lineSpacing,
                insets: insets,
                fontFamily: fontFamily,
                nativeFontSize: nativeFontSize,
                weight: weight,
                fontWidth: fontWidth,
                isItalic: isItalic,
                monospacedDigits: monospacedDigits,
                lowercaseSmallCaps: lowercaseSmallCaps,
                uppercaseSmallCaps: uppercaseSmallCaps,
                lineBreakMode: lineBreakMode,
                maximumNumberOfLines: maximumNumberOfLines,
                minimumNumberOfLines: minimumNumberOfLines,
                minimumScaleFactor: minimumScaleFactor,
                reservesLineLimitSpace: reservesLineLimitSpace,
                underline: underline,
                underlinePattern: underlinePattern,
                underlineColor: underlineColor,
                strikethrough: strikethrough,
                strikethroughPattern: strikethroughPattern,
                strikethroughColor: strikethroughColor,
                enableKerning: enableKerning
            ),
            isHitTestVisible: false
        )
    }

    /// Insets that empty the text content rect at paint time. Icon nodes keep
    /// their private-use glyph as `text` (measurement metadata, existing
    /// behavior), but the scene painter must never route that glyph to the
    /// pixel-font fallback, which can only draw a crude 5x7 pattern or '?'.
    /// With a non-positive content rect the text pass exits before emitting
    /// any glyph, leaving painting to the rasterized bitmap (or the drawn
    /// vector fallback).
    private static let iconTextSuppressionInsets = EdgeInsets(
        top: 0, leading: 1_000_000, bottom: 0, trailing: 1_000_000)

    public static func icon(
        _ symbol: SymbolIcon,
        frame: Rect = .zero,
        preferredSize: Size? = nil,
        color: Color = .white,
        scale: Double = 1.9,
        weight: TextWeight = .regular,
        alignment: TextHorizontalAlignment = .center,
        fontFamily: String = "Segoe Fluent Icons",
        // Last-resort default for callers with no view environment. `WinSwiftUI`
        // always passes `ViewBuildContext.iconRasterDisplayScale`; this global
        // is the first live window's scale, which is the wrong answer for every
        // other window in a multi-window mixed-DPI process. See
        // `NativeTextRenderer.claimDefaultIconDisplayScale(_:owner:)`.
        displayScale: Double = NativeTextRenderer.defaultIconDisplayScale
    ) -> ViewNode {
        let node = label(
            symbol.rawValue,
            frame: frame,
            preferredSize: preferredSize,
            color: color,
            scale: scale,
            weight: weight,
            fontFamily: fontFamily,
            alignment: alignment
        )
        // Symbol glyphs are decorative: their raw unicode text is meaningless
        // to assistive technology, so keep them out of the accessibility
        // tree by default (and out of folded button names).
        node.isAccessibilityHidden = true

        let pointSize = max(12, scale * 6 + 8)
        let targetSize = preferredSize ?? Size(width: pointSize, height: pointSize)

        // Pick the first installed icon font that actually contains this
        // glyph (Fluent Icons on Windows 11, MDL2 Assets on Windows 10).
        let resolvedFamily = NativeFontAvailability.resolvedFontFamily(
            for: symbol.character,
            preferred: [fontFamily] + SymbolIcon.fontFamilyFallbacks
        )
        if let resolvedFamily {
            var rasterStyle = node.textStyle
            rasterStyle.fontFamily = resolvedFamily
            rasterStyle.insets = .zero
            // Rasterize at the display scale so the bitmap stays crisp on
            // >100% DPI displays; the painter stretches it into the same
            // logical rect either way, and scale 1 keeps the deterministic
            // screenshot output byte-identical.
            let rasterScale = max(1, displayScale)
            // Icons are rebuilt with the view tree, so the same glyph goes
            // through DirectWrite again on every state change; the raster is a
            // pure function of (text, style, scale), which is exactly what the
            // key says. A cache miss is the only path that touches DirectWrite.
            let rasterKey = TextRasterCacheKey(
                text: symbol.rawValue, style: rasterStyle, size: targetSize, renderScale: rasterScale)
            if let cached = TextRasterCache.shared.get(for: rasterKey) {
                node.bitmapSurface = cached
            } else if let bitmap = NativeTextRenderer.rasterize(
                symbol.rawValue, style: rasterStyle, scaleFactor: rasterScale),
                bitmapHasVisiblePixels(bitmap)
            {
                TextRasterCache.shared.insert(bitmap, for: rasterKey)
                node.bitmapSurface = bitmap
            }
        }

        if node.bitmapSurface == nil {
            // No installed icon font carries this glyph: draw the symbol
            // through the path tessellator instead of showing '?'.
            node.canvasDraw = { context, size in
                SymbolIconVectorRenderer.draw(symbol, in: size, color: color, into: &context)
            }
        }

        node.textStyle.insets = iconTextSuppressionInsets
        node.preferredSize = targetSize
        return node
    }

    private static func bitmapHasVisiblePixels(_ bitmap: BitmapSurface) -> Bool {
        bitmap.pixels.contains { $0 != 0 }
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
        appliesSurfaceSheen: Bool = false,
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
            appliesSurfaceSheen: appliesSurfaceSheen,
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
        checkedColor: Color = Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0),
        animation: ControlAnimationStyle = .default,
        onToggle: ((Bool) -> Void)? = nil
    ) -> ViewNode {
        let boxSize: Double = 20
        // macOS checkbox: checked state is an accent-filled rounded box with
        // a white check; unchecked is a subtle raised dark surface with a
        // hairline edge.
        let resolvedBorderColor =
            isError
            ? palette.errorBorder
            : (isEnabled
                ? (isChecked ? shaded(checkedColor, by: 0.70) : chrome.borderColor)
                : palette.disabledBorder)
        let resolvedBackgroundColor =
            isEnabled
            ? (isChecked ? checkedColor : palette.idle)
            : palette.disabledBackground
        let resolvedForeground = isEnabled ? Color.white : palette.disabledForeground

        let checkIcon =
            isChecked
            ? icon(
                .checkmark, preferredSize: Size(width: boxSize - 4, height: boxSize - 4), color: resolvedForeground,
                scale: 1.2)
            : panel(preferredSize: Size(width: boxSize - 4, height: boxSize - 4), isHitTestVisible: false)

        let box = panel(
            preferredSize: Size(width: boxSize, height: boxSize),
            backgroundColor: resolvedBackgroundColor,
            backgroundGradient: isEnabled ? backgroundSheen(for: resolvedBackgroundColor) : nil,
            borderColor: resolvedBorderColor,
            borderWidth: isError ? 2 : chrome.borderWidth,
            cornerRadius: 5,
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

        let node = button(
            runtime: runtime,
            preferredSize: preferredSize,
            layoutPriority: layoutPriority,
            cornerRadius: 8,
            palette: palette,
            chrome: chrome,
            clipsToBounds: true,
            layoutMode: .stack(
                .horizontal(
                    spacing: 10, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8), alignment: .center)),
            isEnabled: isEnabled,
            animation: animation,
            appliesSurfaceSheen: true,
            action: action,
            children: [box, labelNode]
        )
        // Checkbox semantics: the isToggle trait maps to the UIA checkBox
        // control type; the checked state projects as isSelected.
        node.accessibilityTraits.formUnion(.isToggle)
        if isChecked {
            node.accessibilityTraits.formUnion(.isSelected)
        }
        return node
    }

    // MARK: - Toggle / Switch

    /// The knob's travel across the track: `Animation.snappy` itself —
    /// response 0.5, damping fraction 0.85 (bounce 0.15) — taken from the
    /// named spring rather than restated, so it cannot drift from the constant
    /// `docs/AnimationParity.md` pins.
    ///
    /// The envelope is `response * 5` (this stack's spring convention), but
    /// `AnimationEasing.spring` clamps its first overshoot, so the knob is
    /// *there* at `0.25 * response` of normalised progress — 0.3125s of
    /// travel. That is the number to compare against NSSwitch, and it is what
    /// `switchTrackCrossfadeDuration` matches.
    public static let switchKnobAnimation = AnimationTransaction(
        duration: Animation.snappy.duration, easing: Animation.snappy.easing)

    /// Where the knob's spring saturates: the interval the travel actually
    /// occupies, and therefore the interval the track's fill cross-fades over
    /// so the two read as one movement.
    public static let switchTrackCrossfadeDuration = Animation.snappy.duration * 0.125

    /// The track's fill cross-fade.
    public static let switchTrackAnimation = AnimationTransaction(
        duration: switchTrackCrossfadeDuration, easing: .easeInOut)

    // MARK: - DisclosureGroup

    /// A disclosure opens over `NSAnimationContext.defaultDuration` — 0.25s,
    /// the interval `NSOutlineView`'s animator proxy turns its triangle and
    /// reveals its rows over. SwiftUI's `DisclosureGroup` on macOS animates its
    /// expansion by default; this stack expanded in a single frame, with the
    /// body content at full opacity and full height on the first frame after
    /// the rebuild and nothing in flight for the runtime to tick.
    public static let disclosureDuration: Double = 0.25

    /// The chevron's turn and the content's reveal, as one transaction so the
    /// two read as a single movement. Carried by the node rather than waiting
    /// on an ambient `withAnimation`: a disclosure's own state change never
    /// has one, exactly as a switch's does not.
    public static let disclosureAnimation = AnimationTransaction(
        duration: disclosureDuration, easing: .easeInOut)

    /// A closed disclosure points right; an open one points down. One glyph
    /// that turns, not two glyphs that swap — a swap is a step function no
    /// amount of tweening reaches.
    public static let disclosureOpenRotation: Double = Double.pi / 2

    /// How far the revealed content rises into place, in points. AppKit's
    /// disclosure slides its rows out from under the header rather than
    /// cross-fading them in place.
    public static let disclosureContentRevealOffset: Double = 6

    public static func toggle(
        runtime: RetainedViewRuntime,
        isOn: Bool,
        isEnabled: Bool = true,
        isError: Bool = false,
        preferredSize: Size? = nil,
        trackSize: Size? = nil,
        knobDiameter: Double? = nil,
        knobInset: Double? = nil,
        layoutPriority: Double = 0,
        onColor: Color = Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0),
        offColor: Color = Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0),
        knobColor: Color = .white,
        knobShadowColor: Color = Color(red: 0, green: 0, blue: 0, alpha: 0.30),
        offTrackBorderColor: Color? = nil,
        palette: SurfacePalette = SurfacePalette(
            idle: .clear,
            focused: Color(red: 0.26, green: 0.33, blue: 0.42, alpha: 1.0),
            pressed: Color(red: 0.72, green: 0.82, blue: 0.92, alpha: 1.0)
        ),
        chrome: SurfaceChrome = SurfaceChrome(
            borderWidth: 0,
            focusRingColor: SurfaceChrome.elevatedButton.focusRingColor,
            focusRingWidth: SurfaceChrome.focusRingStrokeWidth),
        animation: ControlAnimationStyle = .default,
        onToggle: ((Bool) -> Void)? = nil
    ) -> ViewNode {
        // The switch's own geometry, which is *not* the node's preferred
        // size: the node is the pointer target and the track floats inside
        // it with a gutter all round. WinSwiftUI passes
        // `MacOSControlMetrics.Toggle`; the defaults keep the retained
        // builder usable on its own.
        let resolvedTrack = trackSize ?? Size(width: 40, height: 22)
        let trackWidth = resolvedTrack.width
        let trackHeight = resolvedTrack.height
        let thumbInset = knobInset ?? 2
        let thumbSize = knobDiameter ?? max(0, trackHeight - thumbInset * 2)

        let resolvedTrackColor: Color
        if !isEnabled {
            resolvedTrackColor = palette.disabledBackground
        } else {
            resolvedTrackColor = isOn ? onColor : offColor
        }

        let thumbX = isOn ? trackWidth - thumbSize - thumbInset : thumbInset
        let thumbColor = isEnabled ? knobColor : palette.disabledForeground

        // The knob is a flat white disc lifted by `e1` — a 3pt blur at y 1.
        // It used to carry a gradient *and* a hairline edge *and* a 0.32
        // shadow at spread 2, three depth cues stacked on an 18pt circle, on
        // a control whose whole job is to be legible at a glance.
        let thumb = panel(
            frame: Rect(x: thumbX, y: thumbInset, width: thumbSize, height: thumbSize),
            backgroundColor: thumbColor,
            shadowColor: isEnabled ? knobShadowColor : .clear,
            shadowOffset: Point(x: 0, y: 1),
            shadowSpread: 3,
            cornerRadius: thumbSize * 0.5,
            isHitTestVisible: false
        )

        // Track: on state reads as a raised accent pill (top-lighter
        // gradient); off state reads recessed (top-darker gradient) with a
        // hairline edge, like NSSwitch.
        let trackBackgroundColor =
            isEnabled && !isOn ? shaded(resolvedTrackColor, by: grooveSheenFactor) : resolvedTrackColor
        let trackGradient: GradientType? =
            isEnabled
            ? .linear(
                LinearGradient(
                    startColor: trackBackgroundColor,
                    endColor: isOn ? shaded(resolvedTrackColor, by: surfaceSheenFactor) : resolvedTrackColor))
            : nil
        // The off track's ring used to be a blue-cast near-white literal
        // (`0.96, 0.98, 1.0`) — one of the last chromatic neutrals in the
        // app, on the one control that sits in every settings row.
        let resolvedOffBorder = offTrackBorderColor ?? Color(red: 1, green: 1, blue: 1, alpha: 0.10)
        let trackBorderColor =
            isError
            ? palette.errorBorder
            : (isOn ? shaded(resolvedTrackColor, by: 0.70) : resolvedOffBorder)
        let track = panel(
            preferredSize: Size(width: trackWidth, height: trackHeight),
            backgroundColor: trackBackgroundColor,
            backgroundGradient: trackGradient,
            borderColor: trackBorderColor,
            borderWidth: isError ? 2 : (isEnabled ? 1 : 0),
            cornerRadius: trackHeight * 0.5,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [thumb]
        )
        // NSSwitch springs its knob across and cross-fades its track, and it
        // does so whether or not the state change was wrapped in an animation
        // — so the switch carries its own transaction rather than waiting for
        // an ambient one that a rebuilt control never has. `Animation.snappy`
        // (response 0.5 / dampingFraction 0.85) is the pinned constant for
        // exactly this class of control-scale motion; see
        // `docs/AnimationParity.md`.
        //
        // Both halves matter. Before this the thumb reached its end position
        // in a single frame — measured at every sample from 0.0s to 0.4s,
        // local x = 24.00, with the 20px of travel never drawn — and the
        // track's fill jumped from (0.270,0.306,0.360) to (0,0.478,1) on the
        // same frame.
        thumb.implicitReconcileAnimation = Self.switchKnobAnimation
        track.implicitReconcileAnimation = Self.switchTrackAnimation

        track.onLayout = { bounds in
            let resolvedWidth = max(0, bounds.size.width)
            let resolvedHeight = max(0, bounds.size.height)
            let resolvedThumbSize = min(thumbSize, resolvedWidth, resolvedHeight)
            let resolvedThumbY = max(0, (resolvedHeight - resolvedThumbSize) * 0.5)
            let resolvedThumbX =
                isOn
                ? max(0, resolvedWidth - resolvedThumbSize - thumbInset)
                : min(thumbInset, max(0, resolvedWidth - resolvedThumbSize))
            thumb.frame = Rect(
                x: resolvedThumbX,
                y: resolvedThumbY,
                width: resolvedThumbSize,
                height: resolvedThumbSize
            )
        }

        let action: (() -> Void)? = isEnabled ? { onToggle?(!isOn) } : nil

        let node = button(
            runtime: runtime,
            preferredSize: preferredSize ?? Size(width: trackWidth + 8, height: trackHeight + 8),
            layoutPriority: layoutPriority,
            cornerRadius: (trackHeight + 8) * 0.5,
            palette: palette,
            chrome: chrome,
            clipsToBounds: false,
            layoutMode: .stack(
                .horizontal(
                    padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), alignment: .center,
                    mainAlignment: .center)),
            isEnabled: isEnabled,
            animation: animation,
            action: action,
            children: [track]
        )
        // Toggle semantics: the isToggle trait maps to the UIA checkBox
        // control type (a switch has no dedicated UIA type); the on state
        // projects as isSelected. The base button trait stays so the element
        // keeps button behavior for clients that don't pattern-match.
        node.accessibilityTraits.formUnion(.isToggle)
        if isOn {
            node.accessibilityTraits.formUnion(.isSelected)
        }
        return node
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
        chrome: SurfaceChrome = SurfaceChrome(
            focusRingColor: SurfaceChrome.elevatedButton.focusRingColor,
            focusRingWidth: SurfaceChrome.focusRingStrokeWidth),
        onValueChanged: ((Double) -> Void)? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) -> ViewNode {
        let sliderWidth = preferredSize?.width ?? 200
        // NSSlider linear track and knob: 4pt groove, 16pt thumb
        // (MacOSControlMetrics.Slider, one target up).
        let trackHeight: Double = 4
        let thumbSize: Double = 16
        let totalHeight: Double = max(thumbSize + 8, preferredSize?.height ?? 28)

        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        let progress =
            range.upperBound > range.lowerBound
            ? (clampedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            : 0

        let usableTrackWidth = max(0, sliderWidth - thumbSize)
        let thumbX = usableTrackWidth * progress
        let filledWidth = thumbX + thumbSize * 0.5

        let resolvedTrackColor = isEnabled ? trackColor : palette.disabledBackground
        let resolvedFilledColor = isEnabled ? filledColor : palette.disabledForeground
        let resolvedThumbColor = isEnabled ? thumbColor : palette.disabledForeground

        let trackY = (totalHeight - trackHeight) * 0.5
        // Recessed track: top-darker gradient reads as an inset groove.
        let trackSheen: GradientType? =
            isEnabled
            ? .linear(
                LinearGradient(
                    startColor: shaded(resolvedTrackColor, by: grooveSheenFactor), endColor: resolvedTrackColor))
            : nil
        let trackNode = panel(
            frame: Rect(x: 0, y: trackY, width: sliderWidth, height: trackHeight),
            backgroundColor: isEnabled ? shaded(resolvedTrackColor, by: grooveSheenFactor) : resolvedTrackColor,
            backgroundGradient: trackSheen,
            cornerRadius: trackHeight * 0.5,
            isHitTestVisible: false
        )

        let filledNode = panel(
            frame: Rect(x: 0, y: trackY, width: filledWidth, height: trackHeight),
            backgroundColor: resolvedFilledColor,
            backgroundGradient: backgroundSheen(for: resolvedFilledColor),
            cornerRadius: trackHeight * 0.5,
            isHitTestVisible: false
        )

        let thumbY = (totalHeight - thumbSize) * 0.5
        // macOS slider thumb: bright knob with a faint gradient, hairline
        // edge, and a soft shadow.
        let thumbSheen: GradientType? =
            isEnabled
            ? .linear(
                LinearGradient(
                    startColor: resolvedThumbColor,
                    endColor: Color(red: 0.88, green: 0.89, blue: 0.91, alpha: resolvedThumbColor.alpha)))
            : nil
        let thumbNode = panel(
            frame: Rect(x: thumbX, y: thumbY, width: thumbSize, height: thumbSize),
            backgroundColor: resolvedThumbColor,
            backgroundGradient: thumbSheen,
            borderColor: isError ? palette.errorBorder : Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.18),
            borderWidth: isError ? 2 : 1,
            shadowColor: isEnabled && !isError ? Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.30) : .clear,
            shadowOffset: Point(x: 0, y: 1),
            shadowSpread: 2,
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
        let state = SliderDragState()
        state.usableTrackWidth = usableTrackWidth
        sliderRoot.onLayout = { bounds in
            let resolvedWidth = max(0, bounds.size.width)
            let resolvedHeight = max(0, bounds.size.height)
            let resolvedUsableTrackWidth = max(0, resolvedWidth - thumbSize)
            let resolvedThumbX = resolvedUsableTrackWidth * progress
            let resolvedTrackY = (resolvedHeight - trackHeight) * 0.5
            let resolvedThumbY = (resolvedHeight - thumbSize) * 0.5

            state.usableTrackWidth = resolvedUsableTrackWidth
            trackNode.frame = Rect(x: 0, y: resolvedTrackY, width: resolvedWidth, height: trackHeight)
            filledNode.frame = Rect(
                x: 0,
                y: resolvedTrackY,
                width: resolvedThumbX + thumbSize * 0.5,
                height: trackHeight
            )
            thumbNode.frame = Rect(x: resolvedThumbX, y: resolvedThumbY, width: thumbSize, height: thumbSize)
        }

        if isEnabled {
            sliderRoot.isFocusable = true
            // Ring as data, resolved by the runtime: see the note in
            // `Controls.button`. Same 0.12s the closures used.
            sliderRoot.interactionSurface = RetainedInteractionSurface(
                focusRingColor: chrome.focusRingColor,
                focusRingWidth: chrome.focusRingWidth,
                hoverDuration: 0.12,
                pressDuration: 0.12,
                focusDuration: 0.12
            )
            sliderRoot.outlineWidth = 0
            sliderRoot.onDragStart = { point in
                state.startX = point.x
                state.startValue = clampedValue
                onEditingChanged?(true)
            }
            sliderRoot.onDragChange = { _, delta in
                let deltaRatio = delta.x / max(1, state.usableTrackWidth)
                let rangeSpan = range.upperBound - range.lowerBound
                let newValue = min(max(state.startValue + deltaRatio * rangeSpan, range.lowerBound), range.upperBound)
                onValueChanged?(newValue)
            }
            sliderRoot.onDragEnd = { _, _ in
                onEditingChanged?(false)
            }
        }

        // Default accessibility metadata: the projection maps
        // `accessibilityPrefersSliderBehavior` to the UIA slider control
        // type; the value mirrors the bound value. Explicit accessibility
        // modifiers apply after the builder and always win.
        sliderRoot.accessibilityPrefersSliderBehavior = true
        sliderRoot.accessibilityValue = String(clampedValue)

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
        let resolvedCornerRadius = min(cornerRadius, barHeight * 0.5)

        // Recessed track with a top-darker gradient; fill carries the
        // top-lighter accent sheen. Both ends are fully rounded.
        let trackNode = panel(
            frame: Rect(x: 0, y: 0, width: barWidth, height: barHeight),
            backgroundColor: shaded(trackColor, by: 0.78),
            backgroundGradient: .linear(
                LinearGradient(startColor: shaded(trackColor, by: grooveSheenFactor), endColor: trackColor)),
            cornerRadius: resolvedCornerRadius,
            isHitTestVisible: false
        )

        let filledNode = panel(
            frame: Rect(x: 0, y: 0, width: filledWidth, height: barHeight),
            backgroundColor: filledColor,
            backgroundGradient: backgroundSheen(for: filledColor),
            cornerRadius: resolvedCornerRadius,
            isHitTestVisible: false
        )

        let progressNode = panel(
            preferredSize: Size(width: barWidth, height: barHeight),
            layoutPriority: layoutPriority,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [trackNode, filledNode]
        )
        progressNode.onLayout = { bounds in
            let resolvedWidth = max(0, bounds.size.width)
            let resolvedHeight = max(0, bounds.size.height)
            let resolvedBarHeight = min(barHeight, resolvedHeight)
            let resolvedBarY = max(0, (resolvedHeight - resolvedBarHeight) * 0.5)
            let radius = min(cornerRadius, resolvedBarHeight * 0.5)
            trackNode.cornerRadius = radius
            filledNode.cornerRadius = radius
            trackNode.frame = Rect(x: 0, y: resolvedBarY, width: resolvedWidth, height: resolvedBarHeight)
            filledNode.frame = Rect(
                x: 0,
                y: resolvedBarY,
                width: resolvedWidth * progress,
                height: resolvedBarHeight
            )
        }

        // Default accessibility metadata: progress indicator trait (maps to
        // the UIA progressBar control type) plus the determinate progress as
        // a percentage value.
        progressNode.accessibilityTraits.formUnion(.isProgressIndicator)
        progressNode.accessibilityValue = "\(Int((progress * 100).rounded()))%"

        return progressNode
    }

    public static func circularProgress(
        value: Double?,
        total: Double = 1.0,
        preferredSize: Size? = nil,
        layoutPriority: Double = 0,
        trackColor: Color = Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0),
        filledColor: Color = Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0)
    ) -> ViewNode {
        let size = max(12, min(preferredSize?.width ?? 28, preferredSize?.height ?? 28))
        let dotSize = max(3, size * 0.16)
        let segmentCenters: [(Double, Double)] = [
            (0.50, 0.00), (0.75, 0.07), (0.93, 0.25), (1.00, 0.50),
            (0.93, 0.75), (0.75, 0.93), (0.50, 1.00), (0.25, 0.93),
            (0.07, 0.75), (0.00, 0.50), (0.07, 0.25), (0.25, 0.07),
        ]

        let segmentCount = segmentCenters.count
        let filledSegments: Int?
        if let value {
            let progress = total > 0 ? min(max(value / total, 0), 1) : 0
            filledSegments = progress <= 0 ? 0 : max(1, Int((progress * Double(segmentCount)).rounded(.up)))
        } else {
            filledSegments = nil
        }

        let children = segmentCenters.enumerated().map { index, center -> ViewNode in
            let color: Color
            if let filledSegments {
                color = index < filledSegments ? filledColor : trackColor
            } else {
                switch index {
                case 0:
                    color = filledColor
                case 1:
                    color = filledColor.multipliedAlpha(by: 0.72)
                case 2:
                    color = filledColor.multipliedAlpha(by: 0.44)
                default:
                    color = trackColor
                }
            }

            return panel(
                frame: Rect(
                    x: center.0 * (size - dotSize),
                    y: center.1 * (size - dotSize),
                    width: dotSize,
                    height: dotSize
                ),
                backgroundColor: color,
                cornerRadius: dotSize / 2,
                isHitTestVisible: false
            )
        }

        let progressNode = panel(
            preferredSize: Size(width: size, height: size),
            layoutPriority: layoutPriority,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: children
        )
        progressNode.onLayout = { bounds in
            let resolvedSize = max(0, min(bounds.size.width, bounds.size.height))
            let resolvedDotSize = min(dotSize, resolvedSize)
            let travel = max(0, resolvedSize - resolvedDotSize)
            for (index, dotNode) in children.enumerated() {
                let center = segmentCenters[index]
                dotNode.frame = Rect(
                    x: center.0 * travel,
                    y: center.1 * travel,
                    width: resolvedDotSize,
                    height: resolvedDotSize
                )
            }
        }

        // Default accessibility metadata: progress indicator trait (maps to
        // the UIA progressBar control type); determinate progress also
        // carries a percentage value, indeterminate progress carries none.
        progressNode.accessibilityTraits.formUnion(.isProgressIndicator)
        if let value {
            let progress = total > 0 ? min(max(value / total, 0), 1) : 0
            progressNode.accessibilityValue = "\(Int((progress * 100).rounded()))%"
        }

        return progressNode
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
        let innerSize: Double = 8

        // macOS radio: selected state is an accent-filled circle with a
        // white center dot; unselected is a subtle raised dark surface with
        // a hairline edge.
        let resolvedBorderColor =
            isError
            ? palette.errorBorder
            : (isEnabled
                ? (isSelected ? shaded(selectedColor, by: 0.70) : chrome.borderColor)
                : palette.disabledBorder)
        let resolvedOuterBg =
            isEnabled
            ? (isSelected ? selectedColor : palette.idle)
            : palette.disabledBackground
        let resolvedDotColor = isEnabled ? Color.white : palette.disabledForeground

        var outerChildren: [ViewNode] = []
        if isSelected {
            outerChildren.append(
                panel(
                    preferredSize: Size(width: innerSize, height: innerSize),
                    backgroundColor: resolvedDotColor,
                    cornerRadius: innerSize * 0.5,
                    isHitTestVisible: false
                )
            )
        }

        let outerCircle = panel(
            preferredSize: Size(width: outerSize, height: outerSize),
            backgroundColor: resolvedOuterBg,
            backgroundGradient: isEnabled ? backgroundSheen(for: resolvedOuterBg) : nil,
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
            layoutMode: .stack(
                .horizontal(
                    spacing: 10, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8), alignment: .center)),
            isEnabled: isEnabled,
            animation: animation,
            appliesSurfaceSheen: true,
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
            let optionColor =
                isCurrentSelection
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
                appliesSurfaceSheen: true,
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
            stackLayout: .vertical(
                spacing: 2, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), alignment: .stretch),
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
            layoutMode: .stack(
                .vertical(
                    spacing: 4, padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12), alignment: .stretch)),
            isEnabled: isEnabled,
            animation: animation,
            appliesSurfaceSheen: true,
            action: isEnabled
                ? {
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
                palette: isEnabled
                    ? tabPalette
                    : SurfacePalette(
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
                appliesSurfaceSheen: true,
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
            stackLayout: .horizontal(
                spacing: 4, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), alignment: .stretch),
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
            at: runtime.clock()
        )
    }

}
extension ViewNode {
    fileprivate func configured(_ update: (ViewNode) -> Void) -> ViewNode {
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
private final class SliderDragState {
    var startX: Double = 0
    var startValue: Double = 0
    var usableTrackWidth: Double = 0
}
private final class DropdownState {
    var isOpen = false
}
