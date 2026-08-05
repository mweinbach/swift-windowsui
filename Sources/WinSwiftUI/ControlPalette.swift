import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsUI

/// The semantic colour roles macOS control chrome is built from, resolved
/// for one appearance.
///
/// Before this existed every chrome colour in `Views.swift` was a literal
/// tuned for dark mode, so `.preferredColorScheme(.light)` changed exactly
/// one pixel region in the whole app (the toolbar band). A control that
/// wants to be appearance-correct asks `ViewBuildContext.controlPalette`
/// for the role it needs — `separator`, `label`, `controlSurface` — and
/// never writes an RGB literal.
///
/// The values are AppKit's published semantic colours (`NSColor.labelColor`,
/// `separatorColor`, `controlBackgroundColor`, the `systemFill` ramp), which
/// is also why they are achromatic: macOS neutrals are grey, not the blue-cast
/// navy the hand-tuned literals had drifted to. Pinned in
/// docs/MacOSDesignParity.md and asserted by `ControlPaletteTests`.
public struct ControlPalette: Sendable, Equatable {

    // MARK: Surfaces

    /// The window's own backdrop (`NSColor.windowBackgroundColor`).
    public var windowBackground: Color
    /// Recessed content areas: text fields, list bodies, scroll content
    /// (`NSColor.controlBackgroundColor` / `textBackgroundColor`).
    public var controlBackground: Color
    /// The face of a raised bordered control at rest — a push button, a
    /// pop-up button, a stepper half.
    public var controlSurface: Color
    public var controlSurfaceHovered: Color
    public var controlSurfacePressed: Color
    /// Grouped containers that sit above the window backdrop: `GroupBox`,
    /// `Form` sections, cards.
    public var raisedSurface: Color

    // MARK: Content

    /// Primary text (`NSColor.labelColor`).
    public var label: Color
    public var secondaryLabel: Color
    public var tertiaryLabel: Color
    public var quaternaryLabel: Color
    /// Text and glyphs in a disabled control (`disabledControlTextColor`).
    public var disabledLabel: Color
    /// Content drawn on top of an emphasised selection fill
    /// (`alternateSelectedControlTextColor`) — always white on macOS.
    public var selectedContentLabel: Color

    // MARK: Structure

    /// Hairline rules: `Divider`, list row separators, section closers
    /// (`NSColor.separatorColor`).
    public var separator: Color
    /// The 1pt ring around a bordered control.
    public var controlBorder: Color
    /// The same ring on hover / focus, where macOS strengthens it.
    public var controlBorderStrong: Color

    // MARK: Selection

    /// Selection fill for a list/table that does not have key focus
    /// (`unemphasizedSelectedContentBackgroundColor`).
    public var unemphasizedSelectedBackground: Color

    // MARK: Fill ramp

    /// `NSColor.systemFill` … `quinarySystemFill` — the neutral wash macOS
    /// uses for recessed grooves, unselected segment tracks and chips.
    public var systemFill: Color
    public var secondaryFill: Color
    public var tertiaryFill: Color
    public var quaternaryFill: Color
    public var quinaryFill: Color

    /// The appearance this palette was resolved for.
    public var colorScheme: ColorScheme

    public init(
        windowBackground: Color,
        controlBackground: Color,
        controlSurface: Color,
        controlSurfaceHovered: Color,
        controlSurfacePressed: Color,
        raisedSurface: Color,
        label: Color,
        secondaryLabel: Color,
        tertiaryLabel: Color,
        quaternaryLabel: Color,
        disabledLabel: Color,
        selectedContentLabel: Color,
        separator: Color,
        controlBorder: Color,
        controlBorderStrong: Color,
        unemphasizedSelectedBackground: Color,
        systemFill: Color,
        secondaryFill: Color,
        tertiaryFill: Color,
        quaternaryFill: Color,
        quinaryFill: Color,
        colorScheme: ColorScheme
    ) {
        self.windowBackground = windowBackground
        self.controlBackground = controlBackground
        self.controlSurface = controlSurface
        self.controlSurfaceHovered = controlSurfaceHovered
        self.controlSurfacePressed = controlSurfacePressed
        self.raisedSurface = raisedSurface
        self.label = label
        self.secondaryLabel = secondaryLabel
        self.tertiaryLabel = tertiaryLabel
        self.quaternaryLabel = quaternaryLabel
        self.disabledLabel = disabledLabel
        self.selectedContentLabel = selectedContentLabel
        self.separator = separator
        self.controlBorder = controlBorder
        self.controlBorderStrong = controlBorderStrong
        self.unemphasizedSelectedBackground = unemphasizedSelectedBackground
        self.systemFill = systemFill
        self.secondaryFill = secondaryFill
        self.tertiaryFill = tertiaryFill
        self.quaternaryFill = quaternaryFill
        self.quinaryFill = quinaryFill
        self.colorScheme = colorScheme
    }

    public var isDark: Bool { colorScheme == .dark }

    /// Resolves the palette for an appearance. `.increased` contrast
    /// strengthens exactly the roles AppKit strengthens: hairlines, control
    /// borders and secondary/tertiary text.
    public static func resolve(colorScheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> ControlPalette {
        switch (colorScheme, contrast) {
        case (.dark, .standard):
            return darkStandard
        case (.dark, .increased):
            return darkIncreased
        case (.light, .standard):
            return lightStandard
        case (.light, .increased):
            return lightIncreased
        }
    }

    public static let darkStandard = ControlPalette(
        windowBackground: Color(red: 0.129, green: 0.129, blue: 0.129, alpha: 1),
        controlBackground: Color(red: 0.118, green: 0.118, blue: 0.118, alpha: 1),
        controlSurface: white(0.10),
        controlSurfaceHovered: white(0.15),
        controlSurfacePressed: white(0.22),
        raisedSurface: Color(red: 0.157, green: 0.157, blue: 0.161, alpha: 1),
        label: white(LabelHierarchy.primaryAlpha),
        secondaryLabel: white(LabelHierarchy.secondaryAlpha),
        tertiaryLabel: white(LabelHierarchy.tertiaryAlpha),
        quaternaryLabel: white(LabelHierarchy.quaternaryAlpha),
        disabledLabel: white(LabelHierarchy.tertiaryAlpha),
        selectedContentLabel: .white,
        separator: white(0.10),
        controlBorder: white(0.14),
        controlBorderStrong: white(0.28),
        unemphasizedSelectedBackground: Color(red: 0.247, green: 0.247, blue: 0.255, alpha: 1),
        systemFill: white(0.10),
        secondaryFill: white(0.08),
        tertiaryFill: white(0.05),
        quaternaryFill: white(0.03),
        quinaryFill: white(0.02),
        colorScheme: .dark
    )

    public static let lightStandard = ControlPalette(
        windowBackground: Color(red: 0.925, green: 0.925, blue: 0.925, alpha: 1),
        controlBackground: .white,
        controlSurface: .white,
        controlSurfaceHovered: Color(red: 0.957, green: 0.957, blue: 0.957, alpha: 1),
        controlSurfacePressed: Color(red: 0.878, green: 0.878, blue: 0.882, alpha: 1),
        raisedSurface: .white,
        label: black(LabelHierarchy.primaryAlpha),
        secondaryLabel: black(LabelHierarchy.secondaryAlpha),
        tertiaryLabel: black(LabelHierarchy.tertiaryAlpha),
        quaternaryLabel: black(LabelHierarchy.quaternaryAlpha),
        disabledLabel: black(LabelHierarchy.tertiaryAlpha),
        selectedContentLabel: .white,
        separator: black(0.10),
        controlBorder: black(0.16),
        controlBorderStrong: black(0.30),
        unemphasizedSelectedBackground: Color(red: 0.863, green: 0.863, blue: 0.867, alpha: 1),
        systemFill: black(0.10),
        secondaryFill: black(0.08),
        tertiaryFill: black(0.05),
        quaternaryFill: black(0.03),
        quinaryFill: black(0.02),
        colorScheme: .light
    )

    public static let darkIncreased: ControlPalette = {
        var palette = darkStandard
        palette.label = .white
        palette.secondaryLabel = white(LabelHierarchy.increasedContrastSecondaryAlpha)
        palette.tertiaryLabel = white(LabelHierarchy.increasedContrastTertiaryAlpha)
        palette.separator = white(0.28)
        palette.controlBorder = white(0.34)
        palette.controlBorderStrong = white(0.55)
        return palette
    }()

    public static let lightIncreased: ControlPalette = {
        var palette = lightStandard
        palette.label = .black
        palette.secondaryLabel = black(LabelHierarchy.increasedContrastSecondaryAlpha)
        palette.tertiaryLabel = black(LabelHierarchy.increasedContrastTertiaryAlpha)
        palette.separator = black(0.28)
        palette.controlBorder = black(0.36)
        palette.controlBorderStrong = black(0.55)
        return palette
    }()

    // MARK: Derived control roles

    /// The recessed groove a *continuous* control's fill runs along: a
    /// slider's unfilled bar, a determinate `ProgressView`'s remainder, a
    /// segmented gauge's empty cells, and the body of an `off` switch.
    ///
    /// All four used to bake the same dark slate literal
    /// (`Color(red: 0.30, green: 0.34, blue: 0.40)`) into their `Controls`
    /// default, so a light-mode Form drew a near-black groove across a white
    /// settings pane and an `off` switch came out charcoal — the one part of
    /// the light appearance that still looked like the dark one. The dark
    /// value below is that literal unchanged; light is macOS's neutral
    /// groove, dark enough to read as recessed on white.
    public var controlTrack: Color {
        isDark
            ? Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1)
            : Color(red: 0.839, green: 0.839, blue: 0.855, alpha: 1)
    }

    /// Recessed groove an `NSSegmentedControl`'s segments sit in.
    public var segmentedTrackFill: Color {
        isDark
            ? Color(red: 0.173, green: 0.173, blue: 0.180, alpha: 1)
            : Color(red: 0.914, green: 0.914, blue: 0.922, alpha: 1)
    }

    /// The raised pill under the selected segment. Dark mode raises a grey
    /// pill (#636366) — a near-white pill with a near-black label is the
    /// *light* appearance and reads as a foreign chip in a dark app.
    public var segmentedSelectedFill: Color {
        isDark
            ? Color(red: 0.388, green: 0.388, blue: 0.400, alpha: 1)
            : .white
    }

    /// Label on the selected segment: white on the dark pill, black on the
    /// light one.
    public var segmentedSelectedLabel: Color {
        isDark ? .white : .black
    }

    /// A surface that floats above the window rather than sitting inside it —
    /// a menu, a popover, a sheet, an alert, a context menu, an inspector.
    ///
    /// This is a *different* elevation from `raisedSurface`, which is a card
    /// on the window's own backdrop. macOS renders a floating panel on a
    /// vibrant material that is lighter than the window in dark mode and
    /// slightly off-white in light mode; this is that material's flat
    /// approximation. It exists because every one of these surfaces was a
    /// dark literal, so a light-mode app opened a black menu with black text
    /// on it.
    public var elevatedSurface: Color {
        isDark
            ? Color(red: 0.169, green: 0.169, blue: 0.176, alpha: 0.98)
            : Color(red: 0.976, green: 0.976, blue: 0.980, alpha: 0.98)
    }

    /// The hairline closing an elevated surface. A near-white ring is a dark
    /// mode idea; in light mode the ring has to be the dark one.
    public var elevatedSurfaceBorder: Color {
        isDark ? ControlPalette.white(0.16) : ControlPalette.black(0.14)
    }

    /// The knob of an overlay scroller, at the moment it is revealed.
    ///
    /// macOS draws it as a neutral pill with no track behind it: white on a
    /// dark app, black on a light one, at roughly half strength. The
    /// blue-tinted near-white the retained defaults carried was invisible in
    /// light mode and cool against a grey app in dark mode.
    public var scrollerKnob: Color {
        isDark ? ControlPalette.white(0.48) : ControlPalette.black(0.42)
    }

    /// The knob under the pointer. macOS both darkens and widens the knob on
    /// hover; this stack only changes the tone.
    public var scrollerKnobHovered: Color {
        isDark ? ControlPalette.white(0.64) : ControlPalette.black(0.58)
    }

    /// The knob being dragged.
    public var scrollerKnobActive: Color {
        isDark ? ControlPalette.white(0.78) : ControlPalette.black(0.72)
    }

    /// Contact shadow under a grouped container — a `Form` section box, a
    /// `GroupBox`, a settings card.
    ///
    /// A macOS light-mode group box is *near-flat*: a white surface closed
    /// by a separator-tone hairline, with barely any shadow under it. The
    /// depth in dark mode comes from the shadow instead, because a white @
    /// 0.10 hairline on a near-black backdrop carries almost no edge on its
    /// own. One shared `ambientShadow` at 0.12 could only ever be right for
    /// one of the two, and in light mode it put a visible smudge under every
    /// card.
    public var groupedContainerShadow: Color {
        isDark ? ControlPalette.black(0.22) : ControlPalette.black(0.04)
    }

    // MARK: Surface materials

    /// The *material* a grouped container is filled with — a `GroupBox`, a
    /// `Form` section box, a settings card.
    ///
    /// A macOS panel is not one flat colour. It carries a vertical gradient
    /// so slight you would not call it a gradient if you saw it alone — a
    /// handful of levels of 255 between its top and its bottom — and that
    /// slight amount is the whole difference between a surface and a
    /// rectangle of paint. Every card in this app was a single `fillRect`,
    /// which is why a screenshot of it read as flat colour blocking however
    /// correct the tones themselves were.
    ///
    /// It is the same sheen every control surface takes
    /// (`Controls.backgroundSheen`), deliberately: a card and the buttons
    /// standing on it have to be lit from one direction, and two separately
    /// tuned "subtle gradients" would eventually disagree about which way is
    /// up.
    public var raisedSurfaceFill: GradientType {
        .linear(
            SwiftWindowsGraphics.LinearGradient(
                startColor: raisedSurface,
                endColor: Controls.sheenBottom(raisedSurface, drop: Controls.surfaceSheenDrop),
                axis: .vertical
            )
        )
    }

    /// The top edge of a grouped container's hairline ring.
    ///
    /// macOS lights a panel from above, so its top hairline is the lightest
    /// part of the ring in *both* appearances — what changes is what "lighter"
    /// looks like. On a dark window a white top edge reads as a highlight
    /// against the card; on a light one the card is already near-white, so the
    /// same edge reads as the ring *withdrawing* at the top and closing at the
    /// bottom, which is exactly how a System Settings box sits on its window.
    public var raisedSurfaceHighlight: Color {
        isDark ? ControlPalette.white(0.16) : ControlPalette.white(0.55)
    }

    /// The container's ring: the top highlight above, the separator tone
    /// below. `borderColor` carries the start stop because a quad resolves a
    /// gradient's first stop from the fill colour it is handed.
    public var raisedSurfaceRing: GradientType {
        .linear(
            SwiftWindowsGraphics.LinearGradient(
                startColor: raisedSurfaceHighlight,
                endColor: separator,
                axis: .vertical
            )
        )
    }

    // MARK: Accent-derived roles

    /// The emphasised selection fill — a *solid* accent, as
    /// `selectedContentBackgroundColor` is on macOS. Nothing about a
    /// selected row is a translucent wash.
    public func selectedContentBackground(tint: Color) -> Color {
        ControlPalette.opaque(tint)
    }

    /// State ramp for an accent-filled surface. macOS expresses button
    /// state as a lightness change on a fully opaque accent, never as an
    /// alpha ramp that lets the backdrop bleed through a "half-disabled"
    /// looking fill.
    public func accentHovered(_ tint: Color) -> Color {
        ControlPalette.lightened(ControlPalette.opaque(tint), by: 0.08)
    }

    public func accentPressed(_ tint: Color) -> Color {
        ControlPalette.darkened(ControlPalette.opaque(tint), by: 0.12)
    }

    // MARK: Colour maths

    public static func white(_ alpha: Float) -> Color {
        Color(red: 1, green: 1, blue: 1, alpha: alpha)
    }

    public static func black(_ alpha: Float) -> Color {
        Color(red: 0, green: 0, blue: 0, alpha: alpha)
    }

    /// Drops any translucency, keeping the hue. Accent fills on macOS are
    /// opaque.
    public static func opaque(_ color: Color) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    /// Moves a colour `amount` of the way toward white, alpha preserved.
    public static func lightened(_ color: Color, by amount: Float) -> Color {
        let t = min(max(amount, 0), 1)
        return Color(
            red: color.red + (1 - color.red) * t,
            green: color.green + (1 - color.green) * t,
            blue: color.blue + (1 - color.blue) * t,
            alpha: color.alpha
        )
    }

    /// Moves a colour `amount` of the way toward black, alpha preserved.
    public static func darkened(_ color: Color, by amount: Float) -> Color {
        let t = min(max(amount, 0), 1)
        return Color(
            red: color.red * (1 - t),
            green: color.green * (1 - t),
            blue: color.blue * (1 - t),
            alpha: color.alpha
        )
    }
}

// MARK: - Chrome factories

extension ControlPalette {

    /// Fill ramp for a standard bordered (push) button.
    public var borderedButtonPalette: SurfacePalette {
        SurfacePalette(
            idle: controlSurface,
            hovered: controlSurfaceHovered,
            focused: controlSurfaceHovered,
            pressed: controlSurfacePressed,
            disabledBackground: quaternaryFill,
            disabledForeground: disabledLabel,
            disabledBorder: quaternaryLabel
        )
    }

    /// Fill ramp for an accent-filled (`.borderedProminent`) button. macOS
    /// keeps the accent fully opaque at rest and moves lightness for state.
    public func prominentPalette(tint: Color) -> SurfacePalette {
        let accent = ControlPalette.opaque(tint)
        return SurfacePalette(
            idle: accent,
            hovered: accentHovered(accent),
            focused: accentHovered(accent),
            pressed: accentPressed(accent),
            disabledBackground: quaternaryFill,
            disabledForeground: disabledLabel,
            disabledBorder: quaternaryLabel
        )
    }

    /// The 1pt ring plus the neutral ambient shadow a bordered control
    /// casts. macOS never tints a control shadow with the accent colour.
    ///
    /// `focusRingWidth` is `MacOSControlMetrics.FocusRing.strokeWidth`; the
    /// runtime insets the ring by a hairline so it does not sit flush
    /// against the bevel.
    public func buttonChrome(focusTint: Color, casts shadow: Bool = true) -> SurfaceChrome {
        SurfaceChrome(
            borderColor: controlBorder,
            borderHoveredColor: controlBorderStrong,
            borderFocusedColor: controlBorderStrong,
            borderPressedColor: controlBorderStrong,
            borderWidth: 1,
            focusRingColor: ControlPalette.opaque(focusTint).opacity(Double(ControlPalette.focusRingAlpha)),
            focusRingWidth: MacOSControlMetrics.FocusRing.strokeWidth,
            shadowColor: shadow ? ControlPalette.ambientShadow : .clear,
            shadowHoveredColor: shadow ? ControlPalette.ambientShadow : .clear,
            shadowFocusedColor: shadow ? ControlPalette.ambientShadow : .clear,
            shadowPressedColor: .clear,
            shadowOffset: Point(x: 0, y: 1),
            shadowSpread: shadow ? 1 : 0
        )
    }

    /// Ambient 1pt drop shadow shared by every raised control. Neutral
    /// black at low alpha — the tinted glows the accent and destructive
    /// styles used to cast are not a macOS affordance.
    public static let ambientShadow = ControlPalette.black(0.12)

    /// Keyboard focus rings on macOS are a clearly visible accent halo,
    /// not the ~0.28 whisper the hand-tuned chrome used.
    public static let focusRingAlpha: Float = 0.55

    /// Opacity a disabled control's *content* is drawn at. AppKit dims the
    /// entire disabled cell — label, glyph and all — rather than only
    /// swapping the surface fill, which is why a disabled button used to be
    /// pixel-identical to an enabled one everywhere except its background.
    public static let disabledContentOpacity: Double = 0.35

    /// Opacity a *borderless* control's content is drawn at while held down.
    ///
    /// A bordered control answers a press with its bezel fill and leaves its
    /// content alone; a borderless one has no bezel, and AppKit highlights it
    /// by darkening the contents instead (`contentsCellMask`). Applies to the
    /// `.plain` / `.borderless` / `.link` button styles only — see
    /// `ButtonSurfaceStyle.plain`.
    public static let pressedContentOpacity: Double = 0.72
}

/// The glyph a `SecureField` masks its content with.
///
/// macOS uses U+2022 BULLET — a round dot centred on the line box. The
/// ASCII asterisk that used to stand in sits high on the line and reads as
/// a placeholder string rather than masked input.
let secureFieldMaskCharacter: Character = "\u{2022}"
