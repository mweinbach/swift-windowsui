import SwiftWindowsCore
import XCTest

@testable import WinSwiftUI

/// Pins each row of the "Control dimension reference" table in
/// `docs/MacOSDesignParity.md`. The constants in
/// `MacOSControlMetrics` encode the documented macOS HIG values; a
/// change here without updating the doc fails CI.
final class MacOSControlReferenceTests: XCTestCase {

    // MARK: - Push button

    func testButtonHeightsMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.Button.miniHeight, 16, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Button.smallHeight, 19, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Button.regularHeight, 22, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Button.largeHeight, 32, accuracy: 0.001)
    }

    // MARK: - Toggle switch

    /// The switch is the **one** control sized outside the "macOS reference
    /// + pointer padding" rule, and it says so in `MacOSControlMetrics`: a
    /// padded 38x22 comes out at 52x32, which is an iOS switch — the largest
    /// object in a settings pane, for a boolean.
    func testToggleSwitchRegularSizeMatchesNSSwitch() {
        XCTAssertEqual(MacOSControlMetrics.Toggle.regularSize.width, 40, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Toggle.regularSize.height, 22, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Toggle.knobDiameter, 18, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Toggle.knobInset, 2, accuracy: 0.001)
        // The knob fills the track's height less its own inset on both sides.
        XCTAssertEqual(
            MacOSControlMetrics.Toggle.knobDiameter + 2 * MacOSControlMetrics.Toggle.knobInset,
            MacOSControlMetrics.Toggle.regularSize.height,
            accuracy: 0.001)
    }

    func testToggleSwitchLargeSizeMatchesAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.Toggle.largeSize.width, 48, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Toggle.largeSize.height, 26, accuracy: 0.001)
    }

    // MARK: - Slider

    func testSliderTrackAndThumbMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.Slider.trackThickness, 4, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Slider.thumbDiameter, 16, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Slider.regularHeight, 28, accuracy: 0.001)
    }

    // MARK: - Stepper

    func testStepperButtonAndRegularSizeMatchNSStepper() {
        // The modern stepper bezel is 13pt across, not the 19 of the old Aqua
        // one: it is a narrow two-part bezel, taller than it is wide.
        XCTAssertEqual(MacOSControlMetrics.Stepper.buttonSize.width, 13, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Stepper.buttonSize.height, 11, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Stepper.regularSize.width, 13, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Stepper.regularSize.height, 22, accuracy: 0.001)
        XCTAssertEqual(
            MacOSControlMetrics.Stepper.regularSize.height,
            MacOSControlMetrics.Stepper.buttonSize.height * 2,
            accuracy: 0.001,
            "the pair is the bezel: two halves, no leftover"
        )
        XCTAssertEqual(MacOSControlMetrics.Stepper.cornerRadius, 3, accuracy: 0.001)
        XCTAssertLessThan(
            MacOSControlMetrics.Stepper.chevronSize.width,
            MacOSControlMetrics.Stepper.buttonSize.width,
            "the arrow is a wedge inside the half, not the half itself"
        )
    }

    // MARK: - Colour well

    func testColorWellMatchesNSColorWell() {
        XCTAssertEqual(MacOSControlMetrics.ColorWell.regularSize.width, 34, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.ColorWell.regularSize.height, 22, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.ColorWell.cornerRadius, 5, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.ColorWell.swatchInset, 3, accuracy: 0.001)
        XCTAssertLessThan(
            MacOSControlMetrics.ColorWell.swatchCornerRadius,
            MacOSControlMetrics.ColorWell.cornerRadius,
            "the swatch is inset inside the bezel, so its rounding is tighter"
        )
    }

    // MARK: - Pop-up button

    func testPopUpButtonHeightsMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.PopUpButton.regularHeight, 22, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.PopUpButton.largeHeight, 32, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.PopUpButton.chevronInset, 8, accuracy: 0.001)
    }

    // MARK: - Progress

    func testProgressBarHeightMatchesNSProgressIndicator() {
        XCTAssertEqual(MacOSControlMetrics.ProgressBar.regularHeight, 6, accuracy: 0.001)
    }

    func testProgressSpinnerDiametersMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.ProgressSpinner.smallDiameter, 12, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.ProgressSpinner.regularDiameter, 16, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.ProgressSpinner.largeDiameter, 32, accuracy: 0.001)
    }

    // MARK: - Text field

    /// 22, not macOS's 21, so `reference + windowsPointerPadding` lands a
    /// field on **28** — the same height as a button. A field and the button
    /// beside it in a toolbar differing by one point is the kind of
    /// misalignment nobody can name and everybody sees.
    func testTextFieldHeightsMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.TextField.regularHeight, 22, accuracy: 0.001)
        XCTAssertEqual(
            MacOSControlMetrics.TextField.regularHeight, MacOSControlMetrics.Button.regularHeight,
            accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.TextField.largeHeight, 28, accuracy: 0.001)
    }

    // MARK: - List

    /// **One row height for the app.** The 24 plain / 28 sidebar split is a
    /// distinction between two kinds of list this design does not draw — a
    /// nav row and a plain row are the same object at the same rhythm — and a
    /// 24pt row is cramped under a 13pt label with a 15pt glyph beside it.
    func testListRowHeightsMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.List.plainRowHeight, 30, accuracy: 0.001)
        XCTAssertEqual(
            MacOSControlMetrics.List.sidebarRowHeight, MacOSControlMetrics.List.plainRowHeight,
            accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.List.chevronColumnInset, 16, accuracy: 0.001)
    }

    // MARK: - Toolbar

    func testToolbarHeightsMatchNSToolbar() {
        XCTAssertEqual(MacOSControlMetrics.Toolbar.regularHeight, 52, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Toolbar.unifiedCompactHeight, 38, accuracy: 0.001)
    }

    // MARK: - Selector bar

    /// A tab bar is not a segmented control. It has no track, its items have
    /// no pill, and its band is square and full bleed — 40 tall, closed by
    /// one hairline, with the selection carried by a 20x3 accent bar at
    /// `r-xs`. Drawing it with the segmented control put a rounded grey
    /// capsule holding three chained buttons across the top of every screen.
    func testSelectorBarGeometry() {
        let bar = MacOSControlMetrics.SelectorBar.self
        XCTAssertEqual(bar.bandHeight, 40, accuracy: 0.001)
        XCTAssertEqual(bar.hairlineThickness, 1, accuracy: 0.001)
        XCTAssertEqual(bar.itemHeight, 32, accuracy: 0.001)
        XCTAssertEqual(bar.itemCornerRadius, MacOSControlMetrics.Radius.sm, accuracy: 0.001)
        XCTAssertEqual(bar.itemHorizontalPadding, MacOSControlMetrics.Spacing.s3, accuracy: 0.001)
        XCTAssertEqual(bar.itemSpacing, MacOSControlMetrics.Spacing.s1, accuracy: 0.001)
        XCTAssertEqual(bar.indicatorSize.width, 20, accuracy: 0.001)
        XCTAssertEqual(bar.indicatorSize.height, 3, accuracy: 0.001)
        XCTAssertEqual(bar.indicatorCornerRadius, MacOSControlMetrics.Radius.xs, accuracy: 0.001)
        XCTAssertEqual(bar.indicatorGap, 2, accuracy: 0.001)
        XCTAssertLessThan(
            bar.itemHeight, bar.bandHeight,
            "the item is a box inside the band, not the band itself")
    }

    // MARK: - Window chrome

    func testWindowCornerRadiusMatchesMacOSSonoma() {
        XCTAssertEqual(MacOSControlMetrics.Window.cornerRadius, 10, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Window.sheetCornerRadius, 12, accuracy: 0.001)
    }

    // MARK: - Focus ring

    /// A 2pt halo outside a 1px accent border — a recorded divergence from
    /// macOS's 4pt ring, justified by the tighter radius scale: 4pt of ring
    /// around a 6pt corner swallows the corner, so a focused control loses
    /// the shape that identifies it at the moment you need to find it.
    func testFocusRingMetricsMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.FocusRing.strokeWidth, 2, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.FocusRing.outsetFromBounds, 1, accuracy: 0.001)
        XCTAssertLessThan(
            MacOSControlMetrics.FocusRing.strokeWidth, MacOSControlMetrics.Radius.sm,
            "a ring wider than the corner it rings erases the corner")
    }

    // MARK: - Layout

    func testDefaultStackSpacingMatchesSwiftUI() {
        XCTAssertEqual(MacOSControlMetrics.Layout.defaultStackSpacing, 8, accuracy: 0.001)
    }

    func testDefaultPaddingMatchesSwiftUI() {
        XCTAssertEqual(MacOSControlMetrics.Layout.defaultPadding, 16, accuracy: 0.001)
    }
}
