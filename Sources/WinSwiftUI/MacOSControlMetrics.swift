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

    /// Push buttons (NSButton, .push bezel). The reference values for
    /// `.regular` match macOS Sonoma's standard rounded-bezel button.
    public enum Button {
        public static let miniHeight: Double = 16
        public static let smallHeight: Double = 19
        public static let regularHeight: Double = 22
        public static let largeHeight: Double = 32

        /// Corner radius of the push bezel. Big Sur+ push buttons are a
        /// rounded rectangle at ~6pt; a capsule is the opt-in shape
        /// (`.buttonBorderShape(.capsule)`), never the default.
        public static let miniCornerRadius: Double = 4
        public static let smallCornerRadius: Double = 4
        public static let regularCornerRadius: Double = 6
        public static let largeCornerRadius: Double = 8
    }

    /// `Toggle` with `.switch` style — NSSwitch. macOS Sonoma's
    /// rounded pill measures 38×22 (regular).
    public enum Toggle {
        public static let regularSize = Size(width: 38, height: 22)
        public static let largeSize = Size(width: 44, height: 26)
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

    /// `TextField` with `.roundedBorder` style. macOS Sonoma's
    /// single-line text field is 21pt tall.
    public enum TextField {
        public static let regularHeight: Double = 21
        public static let largeHeight: Double = 28
    }

    /// `List` row metrics. Plain rows are 24pt tall; sidebar rows
    /// (NSOutlineView source-list style) are 28pt.
    public enum List {
        public static let plainRowHeight: Double = 24
        public static let sidebarRowHeight: Double = 28
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
        public static let insetCornerRadius: Double = 6
        /// Top and bottom gutter between the inset body's edge and its first
        /// and last row. Without it the first row's text sits flush against
        /// the body's own rounded corner.
        public static let insetVerticalInset: Double = 6
    }

    /// A grouped container — `GroupBox`, a `Form` section box, a settings
    /// card. macOS draws these as a near-flat rounded rectangle closed by a
    /// hairline; the depth cue is the border and the surface tone, not a
    /// drop shadow. The shadow that remains is an ambient contact shadow
    /// only, which is why its offset and spread are single digits.
    public enum GroupBox {
        /// macOS Sonoma's grouped box radius. A 28pt radius on a 600pt-wide
        /// card is a marketing panel, not an `NSBox`.
        public static let cornerRadius: Double = 10
        public static let shadowOffsetY: Double = 2
        public static let shadowSpread: Double = 3
    }

    /// Grouped `Form` metrics — SwiftUI's `.formStyle(.grouped)`, macOS
    /// System Settings.
    ///
    /// A macOS grouped form is a *two-column grid* inside a centred content
    /// column: trailing-aligned labels share one leading column, controls
    /// lead the value column beside them, and the section header sits
    /// outside and above the box it names.
    public enum Form {
        /// Width of the centred content column. macOS settings panes run a
        /// ~600–715pt column with generous margins; edge-to-edge is a web
        /// layout, not a settings pane.
        public static let contentMaxWidth: Double = 640
        /// Horizontal margin between the content column's edge and the
        /// section boxes inside it, so a 640pt column carries 600pt boxes.
        public static let contentHorizontalMargin: Double = 20
        /// Gap between the label column and the value column.
        public static let labelColumnGap: Double = 8
        /// Box-to-next-header rhythm between adjacent sections.
        public static let sectionSpacing: Double = 20
        /// Gap between a section header and the box it labels.
        public static let headerSpacing: Double = 6
        /// Leading inset of an outside-the-box section header, so the header
        /// text sits just proud of the box's own corner.
        public static let headerLeadingInset: Double = 6
        /// Row-to-row spacing inside a group box.
        public static let rowSpacing: Double = 10
        /// Interior padding of a group box.
        public static let boxVerticalPadding: Double = 12
        public static let boxHorizontalPadding: Double = 16
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
        /// Thickness of the knob pill.
        public static let overlayThumbThickness: Double = 7
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

    /// Window chrome. macOS Sonoma+ uses a 10pt corner radius on
    /// standard windows. Sheet presentations use 12pt.
    public enum Window {
        public static let cornerRadius: Double = 10
        public static let sheetCornerRadius: Double = 12
    }

    /// Focus ring stroke and inset. macOS draws a 4pt soft ring
    /// outside the control's bounds for keyboard focus.
    public enum FocusRing {
        public static let strokeWidth: Double = 4
        public static let outsetFromBounds: Double = 3
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
        public static let captionSize: Double = 10
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
        /// Grouped-form / list section headers — `NSTableView`'s group row
        /// and SwiftUI's `Form` section header. Hierarchy here comes from
        /// size and colour, not weight alone.
        public static let sectionHeaderSize: Double = 11
    }

    /// `VStack`, `HStack` default spacing on macOS — SwiftUI uses
    /// 8pt between adjacent views unless explicitly overridden.
    public enum Layout {
        public static let defaultStackSpacing: Double = 8
        /// Gap between a `Label`'s symbol and its title. AppKit's
        /// image-and-title cell uses a 6pt gutter; the previous 10 was
        /// tuned against a 17.6px semibold title.
        public static let labelIconSpacing: Double = 6
        /// `.padding()` no-argument default — macOS uses 16pt on all
        /// edges.
        public static let defaultPadding: Double = 16
    }
}
