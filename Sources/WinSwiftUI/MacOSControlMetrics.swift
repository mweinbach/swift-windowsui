import SwiftWindowsCore

/// Apple HIG-published reference dimensions for standard macOS controls.
///
/// These constants encode the documented control sizes from Apple's
/// Human Interface Guidelines (sections "Buttons", "Pickers",
/// "Sliders", "Toggles", "Indicators", and AppKit's standard
/// `NSControl` size variants). They are the visual-parity *target*
/// that WinSwiftUI's layout aspires to.
///
/// Pinned in docs/MacOSDesignParity.md. The constants themselves are
/// inert — they don't change runtime layout. Layout code (Views.swift
/// `ControlSize` extensions) may converge to them over time. Whenever
/// a divergence between WinSwiftUI's actual layout output and the
/// macOS reference is intentional (e.g., for Windows pointer-target
/// ergonomics), it must be recorded with rationale in the doc.
///
/// All dimensions are in logical points (1pt = 1 / displayScale px).
public enum MacOSControlMetrics {

    /// The spacing scale — a 4/8 grid, and **nothing else is legal**.
    ///
    /// Before this existed the app spaced things at 6, 10, 14, 18, 26 and 30
    /// as often as at 8, 12 and 16, because every gap was chosen where it
    /// was written. Half a dozen near-miss values do not read as a rhythm;
    /// they read as an absence of one, and no amount of care at any single
    /// site recovers it. Every gap in the app snaps to a step here.
    public enum Spacing {
        public static let s1: Double = 4
        public static let s2: Double = 8
        public static let s3: Double = 12
        public static let s4: Double = 16
        public static let s5: Double = 20
        public static let s6: Double = 24
        public static let s8: Double = 32
        public static let s10: Double = 40
        public static let s12: Double = 48
        public static let s16: Double = 64

        /// Every legal step, in order — for the guardrail that asserts a
        /// shipped gap is a member of the scale.
        public static let scale: [Double] = [s1, s2, s3, s4, s5, s6, s8, s10, s12, s16]
    }

    /// The radius scale. **Nothing in the app exceeds 12**, and full-bleed
    /// regions are square.
    ///
    /// The 16 / 20 / 22 / 24 / 26 / 30 the app used to carry is what made it
    /// read as bubbly: a 30pt radius on a panel and a 20pt radius on a
    /// 28pt-tall row are both stadium shapes, and a window full of stadiums
    /// is a consumer toy however correct its tones are. A band that touches
    /// a window edge takes radius 0 and is bounded by a hairline instead —
    /// that is what stops a shell reading as stacked rounded slabs.
    public enum Radius {
        /// Chart bar caps, selection indicator bars, mini meters.
        public static let xs: Double = 3
        /// **Controls**: button, text field, segment pill, checkbox, nav
        /// row, table row hover/selection, tab item.
        public static let sm: Double = 6
        /// Chip, icon tile, segmented track, badge.
        public static let md: Double = 8
        /// **Cards**, form section boxes, group boxes.
        public static let lg: Double = 10
        /// Hero, popover, menu, sheet, dialog.
        public static let xl: Double = 12
        /// The largest radius the design system allows anywhere.
        public static let maximum: Double = xl
    }

    /// Push buttons. The reference heights are macOS Sonoma's standard
    /// rounded-bezel button; the shipped heights are those plus
    /// `ControlSize.windowsPointerPadding`.
    public enum Button {
        public static let miniHeight: Double = 16
        public static let smallHeight: Double = 19
        public static let regularHeight: Double = 22
        public static let largeHeight: Double = 32

        /// Corner radius of the push bezel — `Radius.sm`. A capsule is the
        /// opt-in shape (`.buttonBorderShape(.capsule)`), never the default;
        /// 16 on a 22–30pt control clamps to h/2 and renders every button as
        /// a stadium.
        public static let miniCornerRadius: Double = Radius.xs
        /// `.mini` / `.small`, and the segmented selected pill.
        public static let smallCornerRadius: Double = Radius.sm
        public static let regularCornerRadius: Double = Radius.sm
        public static let largeCornerRadius: Double = Radius.md
    }

    /// `Toggle` with `.switch` style.
    ///
    /// **The one control this system sizes outside the "macOS reference +
    /// pointer padding" rule**, and it says so. 52×32 — reference 38×22 plus
    /// a padded delta — is an *iOS* switch: at that size it is the largest
    /// control in a settings pane and the first thing the eye lands on, for
    /// a boolean. 40×22 with an 18pt knob at a 2pt inset is a desktop
    /// switch: the same height as every other control in the row.
    public enum Toggle {
        public static let regularSize = Size(width: 40, height: 22)
        public static let largeSize = Size(width: 48, height: 26)
        /// The knob, and the gutter between it and the track's edge.
        public static let knobDiameter: Double = 18
        public static let knobInset: Double = 2
    }

    /// `Slider` — NSSlider with linear track. Track is 4pt tall;
    /// thumb diameter is 16pt regular. Total control height includes
    /// hover-target padding.
    public enum Slider {
        public static let trackThickness: Double = 4
        public static let thumbDiameter: Double = 16
        public static let regularHeight: Double = 28
    }

    /// `Stepper` — NSStepper.
    ///
    /// The modern (Big Sur+) stepper is a *narrow* two-part bezel: one
    /// rounded rectangle 13pt across and 22pt tall, split in half by a
    /// hairline, with a small arrow centred in each half. The 19pt width
    /// this used to claim is the old Aqua stepper, and at that width the
    /// arrows grew to fill the box and the control read as a square button
    /// with two chevrons rather than as a stepper.
    public enum Stepper {
        /// One half of the bezel — the up (or down) arrow button.
        public static let buttonSize = Size(width: 13, height: 11)
        /// The joined pair: one bezel, not two chained buttons.
        public static let regularSize = Size(width: 13, height: 22)
        /// Corner radius of the shared bezel. A stepper is closed tighter
        /// than a push button — it is 22pt tall in total, so the 4pt
        /// small-button radius rounds a half almost to a capsule.
        public static let cornerRadius: Double = 3
        /// The arrow glyph's box inside a half. The arrow is a small wedge
        /// with clear air around it; a glyph sized to the half's own box is
        /// what made the chevrons read as the control. The box keeps the
        /// glyph's own proportions — the icon bitmap is stretched into it, so
        /// a 7×4 box squashes a chevron into an unreadable smudge.
        public static let chevronSize = Size(width: 9, height: 8)
    }

    /// `ColorPicker` — NSColorWell.
    ///
    /// A colour well is a bordered control that happens to be filled with
    /// the selection: a rounded bezel in the control-border tone with the
    /// swatch inset inside it, not a bare rectangle of colour. The inset is
    /// what keeps a white selection legible on a light window and a black
    /// one on a dark window.
    public enum ColorWell {
        public static let regularSize = Size(width: 34, height: 22)
        public static let cornerRadius: Double = 5
        /// Gutter between the bezel and the swatch.
        public static let swatchInset: Double = 3
        public static let swatchCornerRadius: Double = 2
    }

    /// `Picker(...)` with `.menu` style — NSPopUpButton. Standard
    /// height tracks the button.
    public enum PopUpButton {
        public static let regularHeight: Double = 22
        public static let largeHeight: Double = 32
        /// Disclosure chevron column inset from the right.
        public static let chevronInset: Double = 8
    }

    /// `ProgressView(value:)` linear bar. NSProgressIndicator bar
    /// thickness is 4pt indeterminate, 6pt determinate (regular).
    public enum ProgressBar {
        public static let regularHeight: Double = 6
    }

    /// `ProgressView()` spinner (indeterminate). NSProgressIndicator
    /// spinning style — regular diameter is 16pt.
    public enum ProgressSpinner {
        public static let smallDiameter: Double = 12
        public static let regularDiameter: Double = 16
        public static let largeDiameter: Double = 32
    }

    /// `TextField` with `.roundedBorder` style.
    ///
    /// 22, not macOS's 21, so that `reference + windowsPointerPadding` lands
    /// a field on **28** — the same height as a button. A field and the
    /// button beside it in a toolbar differing by one point is the kind of
    /// misalignment nobody can name and everybody sees.
    public enum TextField {
        public static let regularHeight: Double = 22
        public static let largeHeight: Double = 28
    }

    /// `List` row metrics.
    ///
    /// **One row height for the app**: 30. macOS's 24 plain / 28 sidebar
    /// split is a distinction between two kinds of list this design does not
    /// draw — a nav row and a plain row are the same object at the same
    /// rhythm — and a 24pt row is cramped under a 13pt label with a 15pt
    /// glyph beside it.
    public enum List {
        public static let plainRowHeight: Double = 30
        public static let sidebarRowHeight: Double = 30
        /// Inset for the disclosure chevron on hierarchical rows.
        public static let chevronColumnInset: Double = 16
        /// Leading/trailing inset from the list's own edge to row content
        /// (NSTableView's standard content inset).
        public static let contentInset: Double = 16
        /// `.inset` is a *body* style, not a spacing tweak: NSTableView's
        /// inset style draws its rows on a rounded `textBackgroundColor`
        /// card. This is that card's radius — the same 6pt a `.bordered`
        /// list is closed with, because they are the same box with and
        /// without the row inset.
        public static let insetCornerRadius: Double = Radius.sm
        /// Top and bottom gutter between the inset body's edge and its first
        /// and last row. Without it the first row's text sits flush against
        /// the body's own rounded corner.
        public static let insetVerticalInset: Double = 6
        /// Gutter a selected/hovered row's fill is inset from the list's own
        /// horizontal edges. A selection is a rounded plate *inside* the
        /// list, not a full-bleed band across the window.
        public static let selectionInset: Double = 6
    }

    /// A grouped container — `GroupBox`, a `Form` section box, a settings
    /// card: a near-flat rounded rectangle closed by a hairline. The depth
    /// cue is the ring and the surface tone; the shadow is a light-appearance
    /// contact shadow only (`Elevation.e1`), which is why its offset is 1.
    public enum GroupBox {
        /// `Radius.lg`. A 28pt radius on a 600pt-wide card is a marketing
        /// panel, not a settings box.
        public static let cornerRadius: Double = Radius.lg
        /// `Elevation.e1` — 3pt blur at y 1. The unspecified offset that
        /// used to default large is what smeared every gutter in the window.
        public static let shadowOffsetY: Double = 1
        public static let shadowSpread: Double = 3
    }

    /// Grouped `Form` metrics — SwiftUI's `.formStyle(.grouped)`.
    ///
    /// A settings pane is a **leading-anchored column** of section boxes.
    /// Rows carry their own height, so a box has no vertical padding of its
    /// own; the rhythm between a section header and the group it names is
    /// the 3:1 eyebrow ratio (24 above, 8 below) that keeps a header
    /// attached to what is *under* it rather than floating between two
    /// groups.
    public enum Form {
        /// Width of the content column. 640 centred in a 1280 window leaves
        /// ~340pt of dead space on each side and reads as a pane borrowed
        /// from another app; 720 leading-anchored inside the page margin
        /// reads as this app's settings.
        public static let contentMaxWidth: Double = 720
        /// Margin between the column's edge and the section boxes inside it.
        ///
        /// Still 20, and still a *centred* column: leading-anchoring the
        /// column inside the page margin is a screen decision the settings
        /// pane makes (§5), not a chrome default, and moving it here would
        /// re-anchor every grouped `Form` in every app.
        public static let contentHorizontalMargin: Double = Spacing.s5
        /// Gap between the label column and the value column.
        public static let labelColumnGap: Double = Spacing.s3
        /// Box-to-next-header rhythm between adjacent sections.
        public static let sectionSpacing: Double = Spacing.s6
        /// Gap between a section header and the box it labels — 8 below
        /// against 24 above, so the header belongs to its group.
        public static let headerSpacing: Double = Spacing.s2
        /// A section header sits flush with the box it names.
        public static let headerLeadingInset: Double = 0
        /// Row-to-row spacing inside a group box.
        public static let rowSpacing: Double = Spacing.s3
        /// Interior padding of a group box.
        ///
        /// The design system's end state is 0 — a row states its own height
        /// (`rowMinHeight`), so box padding only doubles the first and last
        /// gaps. That is true *once rows carry that height*, which is the
        /// settings pane's own rebuild; until then a zero-padded box sits its
        /// first row flush against its own corner. Kept at one scale step
        /// (8) and recorded as the interim it is.
        public static let boxVerticalPadding: Double = Spacing.s2
        public static let boxHorizontalPadding: Double = Spacing.s4
        /// Minimum height of a form row, and of a row that also carries a
        /// description line under its title.
        public static let rowMinHeight: Double = 36
        public static let descriptiveRowMinHeight: Double = 52
    }

    /// `NSScroller` in its modern *overlay* style — the only style a macOS
    /// app gets unless the user has set "Show scroll bars: Always" in General
    /// settings.
    ///
    /// An overlay scroller has no track and no arrows: it is a rounded pill
    /// floating over the content, invisible at rest and faded in while the
    /// content moves. That is why a screenshot of a real macOS app shows no
    /// scrollbar anywhere, and why the always-on 5–6pt bar this stack used to
    /// draw read as a web page's scrollbar rather than a system one.
    public enum Scroller {
        /// Thickness of the knob pill. A modern overlay scroller is a hair
        /// under the pointer, not a bar.
        public static let overlayThumbThickness: Double = 6
        /// Gap between the pill and the scroll view's own edge. The pill
        /// floats *inside* the content, it does not steal a gutter.
        public static let overlayInset: Double = 4
        /// Shortest a knob is allowed to get on a very long document.
        public static let minimumThumbLength: Double = 24
    }

    /// `NavigationStack` / `NavigationSplitView` toolbar (NSToolbar).
    /// macOS Sonoma's standard toolbar is 52pt tall with title; 38pt
    /// when configured `.unifiedCompact`.
    public enum Toolbar {
        public static let regularHeight: Double = 52
        public static let unifiedCompactHeight: Double = 38
    }

    /// The `TabView` band — a **selector bar**, not a segmented groove.
    ///
    /// A tab bar and a segmented picker are not the same control, and drawing
    /// them with the same one is what put a rounded grey capsule holding three
    /// chained buttons across the top of every screen. A selector bar has no
    /// track: the band is the page tone, square and full bleed, closed by one
    /// hairline; the items are transparent at rest; and the selection is a
    /// short bar under the label plus one step of rung and weight. The
    /// segmented control keeps its groove, because a segmented control *is* a
    /// groove.
    public enum SelectorBar {
        /// Band height. One row of chrome, not two.
        public static let bandHeight: Double = 40
        /// The hairline that closes the band. Structural, so `strokeSubtle`
        /// rather than a ring: it separates two regions of the same page.
        public static let hairlineThickness: Double = 1
        /// Item box: 32 tall inside a 40 band, `r-sm`, 12 horizontal.
        public static let itemHeight: Double = 32
        public static let itemCornerRadius: Double = Radius.sm
        public static let itemHorizontalPadding: Double = Spacing.s3
        /// Gap between items. Small enough that the bar reads as one control,
        /// large enough that two hover fills never touch.
        public static let itemSpacing: Double = Spacing.s1
        /// The selection bar: 20 long, 3 thick, `r-xs`.
        public static let indicatorSize = Size(width: 20, height: 3)
        public static let indicatorCornerRadius: Double = Radius.xs
        /// Clear between the label's box and the bar under it.
        public static let indicatorGap: Double = 2
    }

    /// Window chrome.
    public enum Window {
        public static let cornerRadius: Double = Radius.lg
        public static let sheetCornerRadius: Double = Radius.xl
    }

    /// Focus ring stroke and inset.
    ///
    /// A **2pt halo outside a 1px accent border**, not the 4pt soft ring
    /// macOS draws. Recorded as a deliberate divergence, justified by the
    /// tighter radius scale: 4pt of ring around a 6pt corner swallows the
    /// corner entirely, so the focused control loses the shape that
    /// identifies it at exactly the moment you need to find it.
    public enum FocusRing {
        public static let strokeWidth: Double = 2
        public static let outsetFromBounds: Double = 1
    }

    /// The macOS system type ramp — `Font.body`, `Font.headline` and the
    /// rest of `Font.TextStyle`, in points.
    ///
    /// This lives beside the control geometry deliberately. The ramp used
    /// to exist only as literals in `Core.swift`, and because the
    /// machine-checked constants module never mentioned type, the two were
    /// free to diverge: the ramp drifted to the *iOS* Dynamic Type table at
    /// `.large` (body 17, largeTitle 34) while the control geometry stayed
    /// macOS (a 21pt text field, a 24pt list row, a 22pt push button). A
    /// 17pt label needs a ~21pt line box, so every control in the app was
    /// starved by its own label. `Font`'s statics now read from here, which
    /// is what keeps the type and the boxes it has to fit in pinned by one
    /// module.
    ///
    /// Values are AppKit's `NSFont.preferredFont(forTextStyle:)` on macOS,
    /// *not* UIKit's. macOS has no `.large` Dynamic Type content size and
    /// no 34pt large title; the top of the ramp is 26.
    public enum Typography {
        public static let largeTitleSize: Double = 26
        public static let titleSize: Double = 22
        public static let title2Size: Double = 17
        public static let title3Size: Double = 15
        public static let headlineSize: Double = 13
        public static let bodySize: Double = 13
        public static let calloutSize: Double = 12
        public static let subheadlineSize: Double = 11
        public static let footnoteSize: Double = 10
        /// The `caption` role — 11, not 10. A caption is the smallest thing
        /// in the app a reader is actually expected to read, and at 10pt in
        /// the third text rung it was a texture rather than a string. 10
        /// survives as `caption2`, which is the axis-label role: a number
        /// you glance at, beside a mark that already told you the answer.
        public static let captionSize: Double = 11
        public static let caption2Size: Double = 10

        /// Leading is a *fraction of the point size*, not an absolute pixel
        /// count. DirectWrite is given `size + leading` as the uniform line
        /// height, so `standardLeadingRatio` is what makes 13pt body lay out
        /// on macOS's 16pt line and 26pt largeTitle on its 32pt line. A flat
        /// constant (the previous 2px at every size) cramps a title and
        /// loosens a caption, which reads as a different typeface per size.
        public static let standardLeadingRatio: Double = 0.22
        public static let tightLeadingRatio: Double = 0.08
        public static let looseLeadingRatio: Double = 0.40
        /// Leading never rounds to nothing, however small the type.
        public static let minimumLeading: Double = 1

        /// Window and toolbar titles. macOS has no large-title navigation
        /// bar: `NSWindow.title` and an `NSToolbar` title are 13pt semibold,
        /// which is also what `Toolbar.regularHeight` (52) assumes.
        public static let windowTitleSize: Double = 13
        /// The secondary line under a window title (a toolbar subtitle).
        public static let windowSubtitleSize: Double = 11
        /// Tracking added to an uppercase run, as a fraction of the point
        /// size. Capitals carry sidebearings tuned for mixed-case setting;
        /// without extra tracking an all-caps label reads as a solid block.
        public static let uppercaseTrackingRatio: Double = 0.06
        /// An SF Symbol's image box relative to the point size of the font
        /// it inherits. SF Symbols are drawn to the font's full
        /// ascender-to-descender box at `.medium` scale, so a symbol beside
        /// 13pt body text occupies roughly 16pt.
        public static let symbolBoxRatio: Double = 1.25
        /// A `List` group header — the `eyebrow` role. A list group title
        /// genuinely is a *label*: it names the rows under it and is not
        /// something you read on the way past.
        public static let sectionHeaderSize: Double = 11

        /// A grouped-`Form` section header — the `section` role.
        ///
        /// A settings section header is a **heading**, not a label: 15/600
        /// at the primary rung, attached to the group under it. The 11pt
        /// secondary-rung eyebrow it used to be is a System Settings idiom,
        /// and an 11pt dim string floating between two boxes belongs to
        /// neither of them. The distinction is the whole reason these are
        /// two constants rather than one.
        public static let formSectionHeaderSize: Double = 15

        /// A control's own label — a button, a segment, a field's
        /// placeholder. 12/500: one step under body, one step over it in
        /// weight, which is what lets a control label sit beside body text
        /// without competing with it.
        public static let controlLabelSize: Double = 12
        /// A card's title. 14/600 against 13/400 body is one point of size
        /// and two of hierarchy — **weight and rung are the hierarchy tool,
        /// not size**, which is the whole reason a 14pt title reads as a
        /// different role from the 13pt line under it.
        public static let cardTitleSize: Double = 14
        /// An uppercase eyebrow — group titles, column headers. The only
        /// uppercase role in the system.
        public static let eyebrowSize: Double = 11
    }

    /// `VStack`, `HStack` default spacing — 8pt between adjacent views
    /// unless explicitly overridden, which is `Spacing.s2`.
    public enum Layout {
        public static let defaultStackSpacing: Double = Spacing.s2
        /// Gap between a `Label`'s symbol and its title — `Spacing.s2`. An
        /// icon and its label are one object, and 8 is the step the scale
        /// has for that; 6 was AppKit's image-and-title cell and is not a
        /// member of this grid.
        public static let labelIconSpacing: Double = Spacing.s2
        /// `.padding()` no-argument default.
        public static let defaultPadding: Double = Spacing.s4
    }
}
