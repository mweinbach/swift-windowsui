import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsUI

/// The raw colour ramp the whole app is built from — one table, two columns.
///
/// Roles (`ControlPalette`) are named by *what a surface is for*; tokens are
/// named by *where they sit in the ramp*. Keeping them apart is what makes
/// the design restylable: a card's fill is `surface1` here and
/// `raisedSurface` there, and changing which token a role points at is a
/// one-line edit rather than a hunt through chrome.
///
/// **Achromatic within a hair.** The neutrals carry at most a 6/255 cool
/// cast between their red and blue channels — enough that a near-black page
/// reads as ink rather than as brown, far short of the blue-cast navy
/// (`(0.18, 0.23, 0.31)` fills under `(0.96, 0.98, 1.0)` borders) this stack
/// started from. `ControlAppearanceChromeTests` pins the bound.
public enum DesignTokens {

    /// One token's two resolutions. Generic because a few tokens are an
    /// alpha rather than a colour, and an alpha that differs per appearance
    /// is exactly as much a token as a hex is.
    public struct Pair<Value: Sendable & Equatable>: Sendable, Equatable {
        public let dark: Value
        public let light: Value

        public init(dark: Value, light: Value) {
            self.dark = dark
            self.light = light
        }

        public func resolve(_ scheme: ColorScheme) -> Value {
            scheme == .dark ? dark : light
        }
    }

    static func hex(_ value: UInt32, alpha: Float = 1) -> Color {
        Color(
            red: Float((value >> 16) & 0xFF) / 255,
            green: Float((value >> 8) & 0xFF) / 255,
            blue: Float(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    // MARK: Neutral ramp

    /// The distance between two adjacent rungs of the neutral ramp, in levels
    /// of 255.
    ///
    /// **A rung you cannot see is not a rung.** The ramp this replaced stepped
    /// 5 to 8 levels — a card at `#17171A` on a `#111113` page is a 6/255
    /// difference, and 6/255 at the dark end of the curve is under a percent
    /// of luminance. Every elevation in the app was therefore carried by its
    /// hairline alone, and a screenshot of it read as one flat near-black
    /// field with rules drawn on it. Linear, Raycast, GitHub and Vercel all
    /// step their dark ramps 9 to 14 levels per rung; this is that, stated
    /// once so the table below is arithmetic rather than seven independently
    /// tuned literals.
    ///
    /// Pinned by `testNeutralRampStepsAreLegible`, which walks the table and
    /// fails on any adjacent pair closer than `minimumRampStep`.
    public static let rampStep = 11
    /// The floor the ramp is held to. A rung may be a level over or under
    /// `rampStep` where rounding and the cool cast want it; it may never be
    /// close enough to its neighbour to need a hairline to be seen.
    public static let minimumRampStep = 10

    /// **The frame.** Window backdrop, sidebar and rail columns, page gutters
    /// — everything that surrounds content rather than carrying it.
    ///
    /// The near-black end of the ramp is unchanged and deliberately so: the
    /// app's character lives here, and the fix for a compressed ramp is to
    /// spread the rungs *above* the floor, not to lift the floor.
    ///
    /// In light the frame is the *cooler* of the two as well as the darker
    /// one — 6/255 of blue over red against the field's 5 — so a sidebar
    /// reads as shade rather than as grey paint.
    public static let base = Pair(dark: hex(0x0C_0C_0E), light: hex(0xE6_E8_EC))
    /// **The paper.** Content wells, scroll wells, table bodies — and, through
    /// `chromeBand`, the toolbar and selector bands that frame them.
    public static let surface0 = Pair(dark: hex(0x17_17_1C), light: hex(0xF1_F3_F6))
    /// **Cards.** The one and only card fill.
    public static let surface1 = Pair(dark: hex(0x22_22_27), light: hex(0xFF_FF_FF))
    /// Inside a card: fields, chips, icon tiles, segmented track, row hover.
    public static let surface2 = Pair(dark: hex(0x2D_2D_32), light: hex(0xEB_ED_F0))
    /// Pressed / active / selected-neutral; menu and popover body.
    public static let surface3 = Pair(dark: hex(0x39_39_3E), light: hex(0xDF_E1_E4))
    /// One step past `surface3` — a bordered control held down.
    public static let surface4 = Pair(dark: hex(0x45_45_4A), light: hex(0xE5_E7_EA))
    /// Sheet / dialog backdrop.
    public static let scrim = Pair(dark: hex(0x00_00_00, alpha: 0.55), light: hex(0x0C_0C_0E, alpha: 0.28))

    /// **The chrome.** The tone a window's bands present when they sit on the
    /// window's own backdrop: the selector bar, the toolbar band, a footer
    /// inspector.
    ///
    /// It is the `surface0` rung, and that is a decision rather than a
    /// shortcut. A window at this bar has two tonal regions, not three: a
    /// *frame* (the columns and gutters, at `base`) and a *field* (the chrome
    /// bands and the content wells they close, one rung up). The bands and the
    /// well reading as one continuous tone is what makes a toolbar look like
    /// the top of the content rather than a third slab stacked above it —
    /// GitHub's canvas/subtle pair and Linear's sidebar/content split are both
    /// this shape.
    ///
    /// Naming it separately is what lets the *material* resolve against it.
    /// `.bar` used to tint toward `base`, and a translucent band tinted with
    /// the tone it is composited over is byte-identical to that tone: the top
    /// 88pt of every dark screen was one flat field with no band in it at all.
    public static let chromeBand = surface0

    /// Hover fill of an item that sits *directly on the page tone* with no
    /// surface of its own: a tab in the selector bar, a nav row, a quick
    /// action.
    ///
    /// One rung either way from the frame — the one token whose two columns
    /// move in *opposite* directions. On the near-black page the hover is a
    /// step up and reads as a lift; on the near-white page there is no room
    /// above `base` for a step that size, so the light hover moves a rung
    /// *down* toward the ink instead. Same gesture, opposite direction,
    /// because the page is.
    public static let pageItemHover = Pair(dark: hex(0x17_17_1C), light: hex(0xDB_DD_E0))

    /// The neutral a light-appearance wash is mixed from. Pure black on a
    /// cool near-white page reads warm; the page's own ink does not.
    public static let lightInk = hex(0x0C_0C_0E)

    // MARK: Hairlines

    /// Separators, table and form row rules, chart gridlines.
    public static let strokeSubtle = Pair(
        dark: ControlPalette.white(0.06), light: hex(0x0C_0C_0E, alpha: 0.07))
    /// Card ring, chip ring, field ring.
    public static let stroke = Pair(
        dark: ControlPalette.white(0.09), light: hex(0x0C_0C_0E, alpha: 0.10))
    /// Toolbar and footer band edges, popover ring, control bezel, chart baseline.
    public static let strokeStrong = Pair(
        dark: ControlPalette.white(0.14), light: hex(0x0C_0C_0E, alpha: 0.15))
    /// Top stop of every ring. A dark ring is brightest at the top; a light
    /// ring *withdraws* at the top and closes at the bottom, which is the
    /// same lighting read the other way round.
    public static let edgeHighlight = Pair(
        dark: ControlPalette.white(0.10), light: ControlPalette.white(0.75))

    // MARK: Accent — one accent, two roles

    /// The accent **as ink**: chart bars, selection indicators, active
    /// glyphs, link text, focus ring. It varies with the appearance behind
    /// it, because ink always does.
    public static let accentForeground = Pair(dark: hex(0x8B_7C_FF), light: hex(0x5B_4D_E0))
    /// The accent **as an opaque fill** under white text — prominent
    /// buttons, filled badges, a toggle that is on, a highlighted menu item.
    /// The *same* value in both appearances: an opaque fill has no
    /// appearance behind it to vary with. White on it clears 5.9:1.
    public static let accentFill = hex(0x5B_4D_E0)
    public static let accentFillHovered = hex(0x6A_5D_E8)
    public static let accentFillPressed = hex(0x4A_3E_C4)
    /// Alpha of the accent wash under a selected nav row or a hovered chart
    /// column, and of the stronger wash under a selected row in a focused
    /// list.
    public static let accentWashAlpha = Pair(dark: 0.14 as Float, light: 0.10 as Float)
    public static let accentWashStrongAlpha = Pair(dark: 0.20 as Float, light: 0.15 as Float)
    /// Keyboard focus halo and text selection, both appearances.
    public static let accentRingAlpha: Float = 0.45
    public static let accentSelectionAlpha: Float = 0.30

    // MARK: Status

    /// Status rides a 6–7pt dot, a meter fill or 11pt chip text — never a
    /// large fill, never body text, never a button fill.
    public static let success = Pair(dark: hex(0x3F_D0_8A), light: hex(0x0B_7A_52))
    public static let warning = Pair(dark: hex(0xF5_B9_3C), light: hex(0xA4_5A_00))
    public static let danger = Pair(dark: hex(0xFF_6F_6F), light: hex(0xC6_2B_22))
    public static let statusWashAlpha = Pair(dark: 0.14 as Float, light: 0.10 as Float)
}

/// One rung of the elevation ramp, in the engine's own shadow model: one
/// colour, one blur radius, one downward offset, per appearance.
public struct ElevationLevel: Sendable, Equatable {

    /// One appearance's resolution of a rung.
    public struct Shadow: Sendable, Equatable {
        public let color: Color
        public let radius: Double
        public let offsetY: Double

        public init(color: Color, radius: Double, offsetY: Double) {
            self.color = color
            self.radius = radius
            self.offsetY = offsetY
        }

        public static let none = Shadow(color: .clear, radius: 0, offsetY: 0)
    }

    public let dark: Shadow
    public let light: Shadow

    public init(dark: Shadow, light: Shadow) {
        self.dark = dark
        self.light = light
    }

    public func resolve(_ scheme: ColorScheme) -> Shadow {
        scheme == .dark ? dark : light
    }

    public func color(for scheme: ColorScheme) -> Color { resolve(scheme).color }
    public func radius(for scheme: ColorScheme) -> Double { resolve(scheme).radius }
    public func offsetY(for scheme: ColorScheme) -> Double { resolve(scheme).offsetY }
}

/// The elevation ramp — five rungs, one shadow each.
///
/// **Structure is carried by the hairline; a shadow only ever says "this
/// floats."** That distinction is the whole ramp: a card in the page is
/// flat and closed by a ring, and only something genuinely above the page —
/// a toolbar over scrolled content, a menu, a sheet — casts anything.
///
/// The retired ramp had one shadow used at every level with an *unspecified*
/// offset that defaulted large: `DemoElevation.panel` blurred 8 and offset
/// **14**, under a 12pt gutter. Every gutter in the window was filled with a
/// shadow smear rather than showing the page base, which is the single
/// largest source of the muddy read in both appearances. Nothing here
/// offsets more than 12, and `e0`/`e1` — the rungs a page card takes — offset
/// 0 and 1.
public enum Elevation {

    /// Everything flat in the page: nav rows, table rows, form rows, chips,
    /// and **all cards in the dark appearance**. A shadow under a near-black
    /// card on a near-black page is invisible work.
    public static let e0 = ElevationLevel(dark: .none, light: .none)

    /// Cards and form boxes **in the light appearance**; the segmented
    /// selected pill; a toggle knob. A 3pt blur at y 1 — a paper lift.
    public static let e1 = ElevationLevel(
        dark: .init(color: ControlPalette.black(0.30), radius: 3, offsetY: 1),
        light: .init(color: ControlPalette.ink(0.06), radius: 3, offsetY: 1)
    )

    /// A toolbar band over scrolled content, an inline popup, a tooltip.
    public static let e2 = ElevationLevel(
        dark: .init(color: ControlPalette.black(0.38), radius: 10, offsetY: 4),
        light: .init(color: ControlPalette.ink(0.08), radius: 8, offsetY: 3)
    )

    /// Menu, popover, sheet, dialog.
    public static let e3 = ElevationLevel(
        dark: .init(color: ControlPalette.black(0.50), radius: 24, offsetY: 12),
        light: .init(color: ControlPalette.ink(0.13), radius: 22, offsetY: 10)
    )

    /// **The hero card only.** The one tinted shadow in the app.
    public static let e4 = ElevationLevel(
        dark: .init(color: DesignTokens.accentFill.opacity(0.22), radius: 28, offsetY: 10),
        light: .init(color: DesignTokens.accentFill.opacity(0.16), radius: 24, offsetY: 10)
    )
}

/// The design system's colour roles, resolved for one appearance.
///
/// Before this existed every chrome colour in `Views.swift` was a literal
/// tuned for dark mode, so `.preferredColorScheme(.light)` changed exactly
/// one pixel region in the whole app (the toolbar band). A control that
/// wants to be appearance-correct asks `ViewBuildContext.controlPalette`
/// for the role it needs — `separator`, `label`, `controlSurface` — and
/// never writes an RGB literal.
///
/// The *mechanism* was built for macOS parity and is unchanged. The values
/// are now this app's own system ("quiet ink, one signature"): a near-black
/// or near-white page, structure carried by hairlines and one surface lift,
/// and exactly one saturated moment per screen. `DesignTokens` below holds
/// the ramp; every role here is one of those tokens, so restyling the app is
/// a change to a table rather than a search through chrome. Pinned in
/// docs/MacOSDesignParity.md and asserted by `MacOSDesignParityTests` /
/// `ControlAppearanceChromeTests`.
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
    public static func resolve(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast = .standard,
        systemColors: HighContrastSystemColors? = nil
    ) -> ControlPalette {
        if contrast == .increased, let systemColors {
            return nativeHighContrast(colors: systemColors, colorScheme: colorScheme)
        }
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

    /// A Windows contrast theme is a user-selected accessibility contract,
    /// not a stronger version of our neutral dark/light ramp. Keep its actual
    /// text, surface, selection, disabled, and border colors intact so themes
    /// such as Aquatic/Desert and custom palettes remain legible.
    private static func nativeHighContrast(
        colors: HighContrastSystemColors, colorScheme: ColorScheme
    ) -> ControlPalette {
        var palette = colorScheme == .dark ? darkIncreased : lightIncreased
        palette.windowBackground = colors.windowBackground
        palette.controlBackground = colors.windowBackground
        palette.controlSurface = colors.controlBackground
        palette.controlSurfaceHovered = colors.selectedBackground
        palette.controlSurfacePressed = colors.selectedBackground
        palette.raisedSurface = colors.controlBackground
        palette.label = colors.windowText
        palette.secondaryLabel = colors.windowText
        palette.tertiaryLabel = colors.controlText
        palette.quaternaryLabel = colors.disabledText
        palette.disabledLabel = colors.disabledText
        palette.selectedContentLabel = colors.selectedText
        palette.separator = colors.controlText
        palette.controlBorder = colors.controlText
        palette.controlBorderStrong = colors.selectedBackground
        palette.unemphasizedSelectedBackground = colors.selectedBackground
        palette.systemFill = colors.controlBackground
        palette.secondaryFill = colors.controlBackground
        palette.tertiaryFill = colors.controlBackground
        palette.quaternaryFill = colors.controlBackground
        palette.quinaryFill = colors.controlBackground
        return palette
    }

    /// A light-appearance wash, mixed from the page's own ink rather than
    /// from pure black. On a cool near-white page a pure-black hairline
    /// reads a shade warm; `#0C0C0E` at the same alpha does not, and it is
    /// the same neutral the dark appearance uses as its base.
    public static func ink(_ alpha: Float) -> Color {
        Color(
            red: DesignTokens.lightInk.red,
            green: DesignTokens.lightInk.green,
            blue: DesignTokens.lightInk.blue,
            alpha: alpha
        )
    }

    public static let darkStandard = ControlPalette(
        windowBackground: DesignTokens.base.dark,
        controlBackground: DesignTokens.surface0.dark,
        // A bordered control's face is opaque, not a wash. `white(0.10)`
        // over a `#212121` window was a visible plate; over the near-black
        // `#0C0C0E` page it is 25/255 of nothing, and every button in the
        // app dissolved into its own backdrop.
        controlSurface: DesignTokens.surface2.dark,
        controlSurfaceHovered: DesignTokens.surface3.dark,
        controlSurfacePressed: DesignTokens.surface4.dark,
        raisedSurface: DesignTokens.surface1.dark,
        label: white(LabelHierarchy.primaryAlpha),
        secondaryLabel: white(LabelHierarchy.secondaryAlpha),
        tertiaryLabel: white(LabelHierarchy.tertiaryAlpha),
        quaternaryLabel: white(LabelHierarchy.quaternaryAlpha),
        // A disabled label is the fourth rung — the same tone as a chevron
        // or any other thing that is not a string you have to read.
        disabledLabel: white(LabelHierarchy.quaternaryAlpha),
        selectedContentLabel: .white,
        separator: DesignTokens.strokeSubtle.dark,
        controlBorder: DesignTokens.stroke.dark,
        controlBorderStrong: DesignTokens.strokeStrong.dark,
        unemphasizedSelectedBackground: DesignTokens.surface3.dark,
        systemFill: white(0.10),
        secondaryFill: white(0.08),
        tertiaryFill: white(0.05),
        quaternaryFill: white(0.03),
        quinaryFill: white(0.02),
        colorScheme: .dark
    )

    public static let lightStandard = ControlPalette(
        windowBackground: DesignTokens.base.light,
        controlBackground: DesignTokens.surface0.light,
        controlSurface: DesignTokens.surface1.light,
        controlSurfaceHovered: DesignTokens.surface0.light,
        controlSurfacePressed: DesignTokens.surface4.light,
        raisedSurface: DesignTokens.surface1.light,
        label: ink(LabelHierarchy.lightPrimaryAlpha),
        secondaryLabel: ink(LabelHierarchy.lightSecondaryAlpha),
        tertiaryLabel: ink(LabelHierarchy.lightTertiaryAlpha),
        quaternaryLabel: ink(LabelHierarchy.lightQuaternaryAlpha),
        disabledLabel: ink(LabelHierarchy.lightQuaternaryAlpha),
        selectedContentLabel: .white,
        separator: DesignTokens.strokeSubtle.light,
        controlBorder: DesignTokens.stroke.light,
        controlBorderStrong: DesignTokens.strokeStrong.light,
        unemphasizedSelectedBackground: DesignTokens.surface3.light,
        systemFill: ink(0.10),
        secondaryFill: ink(0.08),
        tertiaryFill: ink(0.05),
        quaternaryFill: ink(0.03),
        quinaryFill: ink(0.02),
        colorScheme: .light
    )

    public static let darkIncreased: ControlPalette = {
        var palette = darkStandard
        palette.label = .white
        palette.secondaryLabel = white(LabelHierarchy.increasedContrastSecondaryAlpha)
        palette.tertiaryLabel = white(LabelHierarchy.increasedContrastTertiaryAlpha)
        palette.separator = white(0.14)
        palette.controlBorder = white(0.20)
        palette.controlBorderStrong = white(0.34)
        return palette
    }()

    public static let lightIncreased: ControlPalette = {
        var palette = lightStandard
        palette.label = ink(1)
        palette.secondaryLabel = ink(LabelHierarchy.lightIncreasedContrastSecondaryAlpha)
        palette.tertiaryLabel = ink(LabelHierarchy.lightIncreasedContrastTertiaryAlpha)
        palette.separator = ink(0.16)
        palette.controlBorder = ink(0.22)
        palette.controlBorderStrong = ink(0.36)
        return palette
    }()

    // MARK: The ramp, by name

    /// **The frame.** Window backdrop, sidebar and rail columns, page gutters.
    public var base: Color { DesignTokens.base.resolve(colorScheme) }
    /// **The paper.** Content wells, scroll wells, table bodies.
    public var surface0: Color { DesignTokens.surface0.resolve(colorScheme) }
    /// **The chrome.** The tone a selector bar, a toolbar band or a footer
    /// inspector presents over the window backdrop. See
    /// `DesignTokens.chromeBand` for why the bands and the content well share
    /// a rung and why the material needs the name.
    public var chromeBand: Color { DesignTokens.chromeBand.resolve(colorScheme) }
    /// **Cards.** The one and only card fill.
    public var surface1: Color { DesignTokens.surface1.resolve(colorScheme) }
    /// Inside a card: fields, chips, icon tiles, segmented track, row hover.
    public var surface2: Color { DesignTokens.surface2.resolve(colorScheme) }
    /// Pressed / active / selected-neutral; menu and popover body.
    public var surface3: Color { DesignTokens.surface3.resolve(colorScheme) }
    /// Sheet / dialog backdrop.
    public var scrim: Color { DesignTokens.scrim.resolve(colorScheme) }

    /// The face of a text input, a search field, a stepper's number well.
    ///
    /// The appearances are genuine inverses and both are right: `surface2`
    /// on the near-black page — one step *lighter* than the card it sits in,
    /// because a darker recess on near-black is a hole — and white on the
    /// near-white one, one step lighter than the chips beside it. The ring
    /// carries "you can type here" in both.
    public var fieldSurface: Color { isDark ? surface2 : DesignTokens.surface1.light }

    /// The structural hairline — one step above `separator`. Toolbar and
    /// footer band edges, a popover's ring, a chart baseline: the lines that
    /// say "this region ends here", as opposed to the ones that say "these
    /// two rows are different rows".
    public var separatorStrong: Color { controlBorderStrong }

    // MARK: Derived control roles

    /// The recessed groove a *continuous* control's fill runs along: a
    /// slider's unfilled bar, a determinate `ProgressView`'s remainder, a
    /// segmented gauge's empty cells, and the body of an `off` switch.
    ///
    /// All four used to bake the same dark slate literal
    /// (`Color(red: 0.30, green: 0.34, blue: 0.40)`) into their `Controls`
    /// default, so a light-mode Form drew a near-black groove across a white
    /// settings pane and an `off` switch came out charcoal.
    ///
    /// That slate was also the last chromatic neutral in the app — a groove
    /// on a blue axis beside an otherwise achromatic ramp — so it is gone:
    /// the groove is `surface3` in dark, and a neutral light grey deep enough
    /// to read as recessed on white.
    public var controlTrack: Color {
        isDark ? surface3 : DesignTokens.hex(0xD2_D4_DA)
    }

    /// Recessed groove a segmented control's segments sit in — the same
    /// `surface2` a field or a chip takes, because they are the same idea:
    /// a recess inside a card.
    public var segmentedTrackFill: Color { surface2 }

    /// Hover fill of an item drawn straight onto the page tone — a selector
    /// bar tab, a sidebar row, a quick action. See `DesignTokens.pageItemHover`
    /// for why it is not `surface1` in both appearances.
    public var pageItemHoverFill: Color { DesignTokens.pageItemHover.resolve(colorScheme) }

    /// The raised pill under the selected segment.
    ///
    /// Dark mode used to raise a mid-grey plate (#636366) so the pill could
    /// be seen. The lift comes from *elevation* now — `surface3` plus the
    /// `e1` contact shadow — which is why the pill can sit one quiet step
    /// above its track instead of six.
    public var segmentedSelectedFill: Color {
        isDark ? surface3 : DesignTokens.surface1.light
    }

    /// Label on the selected segment. The primary rung in both appearances:
    /// a selected segment is the one you are meant to read.
    public var segmentedSelectedLabel: Color { label }

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
    ///
    /// **Elevated means lighter than the window, in both appearances**, so the
    /// two columns are different rungs: `surface3` on the near-black page,
    /// where a panel three rungs up is a clear lift, and the card rung on the
    /// near-white one, where `surface3` is a *recess* — it resolved to a panel
    /// darker than the backdrop it was supposed to be floating over, which is
    /// a menu that reads as a hole. The same inversion `fieldSurface` and
    /// `pageItemHover` make, for the same reason: the near-white page has no
    /// room above itself except white.
    public var elevatedSurface: Color {
        let surface = isDark ? surface3 : DesignTokens.surface1.light
        return Color(red: surface.red, green: surface.green, blue: surface.blue, alpha: 0.98)
    }

    /// The hairline closing an elevated surface. A floating panel is closed
    /// with the *structural* hairline, not the card one: it has no page
    /// around it to borrow an edge from.
    public var elevatedSurfaceBorder: Color { controlBorderStrong }

    /// The knob of an overlay scroller, at the moment it is revealed.
    ///
    /// A neutral pill with no track behind it: white on a dark app, ink on a
    /// light one. A modern overlay scroller is *nearly invisible* at rest —
    /// the 0.48 / 0.42 this used to draw made the scrollbar the brightest
    /// object in whatever column it floated over, which is the one thing a
    /// scrollbar must never be.
    public var scrollerKnob: Color {
        isDark ? ControlPalette.white(0.22) : ControlPalette.ink(0.18)
    }

    /// The knob under the pointer.
    public var scrollerKnobHovered: Color {
        isDark ? ControlPalette.white(0.34) : ControlPalette.ink(0.30)
    }

    /// The knob being dragged — the only state in which it is meant to be
    /// the thing you are looking at.
    public var scrollerKnobActive: Color {
        isDark ? ControlPalette.white(0.50) : ControlPalette.ink(0.46)
    }

    /// Contact shadow under a grouped container — a `Form` section box, a
    /// `GroupBox`, a settings card.
    ///
    /// **The appearance-conditional card rule.** In dark, a card is
    /// `surface1` closed by a hairline and casts *nothing*: a shadow under a
    /// near-black card on a near-black page is invisible work, and at any
    /// alpha strong enough to see it fills the 12pt gutter beside the card
    /// with a grey smear instead of page tone. In light, a white card on
    /// `#F2F3F5` takes `e1` — a 3pt blur at y 1 that reads as a paper lift,
    /// which is what every app at this bar does.
    ///
    /// Stated once here so both appearances resolve from one rule rather
    /// than from two independently tuned alphas.
    public var groupedContainerShadow: Color {
        isDark ? .clear : Elevation.e1.color(for: colorScheme)
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
        DesignTokens.edgeHighlight.resolve(colorScheme)
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

    /// The accent **as ink** — a chart bar, a selection indicator, an active
    /// glyph, link text, a focus ring. It varies with the appearance behind
    /// it: `#8B7CFF` on the near-black page (5.6:1) and `#5B4DE0` on the
    /// near-white one (5.9:1).
    public var accentForeground: Color { DesignTokens.accentForeground.resolve(colorScheme) }

    /// The accent **as an opaque fill** under white text. The *same* value
    /// in both appearances — an opaque fill has no appearance behind it to
    /// vary with — and white on it clears 5.9:1 either way.
    public var accentFill: Color { DesignTokens.accentFill }
    public var accentFillHovered: Color { DesignTokens.accentFillHovered }
    public var accentFillPressed: Color { DesignTokens.accentFillPressed }

    /// Selected nav row, hovered chart column, tag chips.
    public var accentWash: Color {
        accentForeground.opacity(Double(DesignTokens.accentWashAlpha.resolve(colorScheme)))
    }

    /// Selected row in a *focused* list — one step up from `accentWash`.
    public var accentWashStrong: Color {
        accentForeground.opacity(Double(DesignTokens.accentWashStrongAlpha.resolve(colorScheme)))
    }

    /// Keyboard focus halo.
    public var accentRing: Color {
        accentForeground.opacity(Double(DesignTokens.accentRingAlpha))
    }

    /// Text selection.
    public var accentSelection: Color {
        accentForeground.opacity(Double(DesignTokens.accentSelectionAlpha))
    }

    /// Resolves a tint for use as **ink**.
    ///
    /// This is the accent split, applied. A view hands chrome an ambient
    /// tint; if that tint is the system accent, ink resolves to the
    /// appearance's own `accentForeground` (violet on the dark page, indigo
    /// on the light one) rather than to the fill value, which is 2.7:1 as
    /// text on a near-black page. A tint the app chose itself is the app's
    /// business and passes through untouched — the same exact-value
    /// recognition rule the label ladder uses.
    public func accentInk(for tint: Color) -> Color {
        let opaqueTint = ControlPalette.opaque(tint)
        let fill = DesignTokens.accentFill
        let isSystemAccent =
            abs(opaqueTint.red - fill.red) < 0.004
            && abs(opaqueTint.green - fill.green) < 0.004
            && abs(opaqueTint.blue - fill.blue) < 0.004
        guard isSystemAccent else {
            return ControlPalette.opaque(tint)
        }
        return accentForeground
    }

    // MARK: Status

    /// Status rides a 6–7pt dot, a meter fill or 11pt chip text — never a
    /// large fill, never body text, never a button fill.
    public var success: Color { DesignTokens.success.resolve(colorScheme) }
    public var warning: Color { DesignTokens.warning.resolve(colorScheme) }
    public var danger: Color { DesignTokens.danger.resolve(colorScheme) }

    public func statusWash(_ status: Color) -> Color {
        status.opacity(Double(DesignTokens.statusWashAlpha.resolve(colorScheme)))
    }

    /// The emphasised selection fill for a surface that genuinely *is*
    /// filled: a highlighted menu item, a filled badge, an emphasised chip.
    /// Solid accent under white content.
    public func selectedContentBackground(tint: Color) -> Color {
        ControlPalette.opaque(tint)
    }

    /// The selection fill for a **row in a list or table** — a wash, not a
    /// fill.
    ///
    /// A selected row used to be the solid accent with white text on it. On
    /// the demo's Data screen that is a full-bleed saturated band across the
    /// window: the loudest object in the app, for the least important reason,
    /// and the one place a list stops looking like a list. The wash keeps the
    /// row on the page's own ladder and lets the leading indicator bar say
    /// "this one" instead. Emphasis is what separates it from the
    /// unfocused-window fill, which stays neutral (`surface3`).
    public func listSelectionBackground(tint: Color) -> Color {
        accentInk(for: tint).opacity(Double(DesignTokens.accentWashStrongAlpha.resolve(colorScheme)))
    }

    /// State ramp for an accent-filled surface: a lightness change on a
    /// fully opaque accent, never an alpha ramp that lets the backdrop bleed
    /// through a "half-disabled" looking fill. The system accent takes its
    /// pinned hover/pressed stops; a tint the app chose takes the same
    /// lightness move applied to its own hue.
    public func accentHovered(_ tint: Color) -> Color {
        let accent = ControlPalette.opaque(tint)
        return accent == DesignTokens.accentFill
            ? DesignTokens.accentFillHovered
            : ControlPalette.lightened(accent, by: 0.08)
    }

    public func accentPressed(_ tint: Color) -> Color {
        let accent = ControlPalette.opaque(tint)
        return accent == DesignTokens.accentFill
            ? DesignTokens.accentFillPressed
            : ControlPalette.darkened(accent, by: 0.12)
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

    /// The contact shadow a raised control casts, by the same
    /// appearance-conditional rule the cards follow: `e1` in light, nothing
    /// in dark. A near-black bezel on a near-black page has no shadow to
    /// cast that is not either invisible or a smear.
    public var controlShadow: Color { isDark ? .clear : Elevation.e1.color(for: colorScheme) }

    /// The 1pt ring plus the contact shadow a bordered control casts. A
    /// control shadow is never tinted with the accent colour.
    ///
    /// The focus ring is the accent as **ink** — the appearance's own
    /// `accentForeground`, not the fill value, which is 2.7:1 against a
    /// near-black page and would put a focus ring you cannot see around the
    /// control you just tabbed to.
    ///
    /// `focusRingWidth` is `MacOSControlMetrics.FocusRing.strokeWidth`; the
    /// runtime insets the ring by a hairline so it does not sit flush
    /// against the bevel.
    public func buttonChrome(focusTint: Color, casts shadow: Bool = true) -> SurfaceChrome {
        let contact = shadow ? controlShadow : .clear
        return SurfaceChrome(
            borderColor: controlBorder,
            borderHoveredColor: controlBorderStrong,
            borderFocusedColor: controlBorderStrong,
            borderPressedColor: controlBorderStrong,
            borderWidth: 1,
            focusRingColor: accentInk(for: focusTint).opacity(Double(ControlPalette.focusRingAlpha)),
            focusRingWidth: MacOSControlMetrics.FocusRing.strokeWidth,
            shadowColor: contact,
            shadowHoveredColor: contact,
            shadowFocusedColor: contact,
            shadowPressedColor: .clear,
            shadowOffset: Point(x: 0, y: Elevation.e1.light.offsetY),
            shadowSpread: shadow ? 1 : 0
        )
    }

    /// Ambient contact shadow, appearance-blind. Kept for the handful of
    /// call sites that want *a* neutral contact tone without a palette in
    /// hand; anything with a palette should ask for `controlShadow`.
    public static let ambientShadow = ControlPalette.ink(0.06)

    /// A keyboard focus ring is a 1px accent border plus a 2px halo outside
    /// it — clearly visible, and small enough to sit *outside* a 6pt corner
    /// radius rather than swallowing it. The retired 4pt ring at 0.55 was
    /// authored against macOS's softer bezel; on this radius scale it read
    /// as a bloom around the control rather than an outline of it.
    public static let focusRingAlpha: Float = DesignTokens.accentRingAlpha

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
