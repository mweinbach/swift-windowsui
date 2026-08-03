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

    /// `Stepper` — NSStepper. Each chevron button is 19×11 in
    /// regular size; the pair stack is 19×22.
    public enum Stepper {
        public static let buttonSize = Size(width: 19, height: 11)
        public static let regularSize = Size(width: 19, height: 22)
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

    /// `VStack`, `HStack` default spacing on macOS — SwiftUI uses
    /// 8pt between adjacent views unless explicitly overridden.
    public enum Layout {
        public static let defaultStackSpacing: Double = 8
        /// `.padding()` no-argument default — macOS uses 16pt on all
        /// edges.
        public static let defaultPadding: Double = 16
    }
}
