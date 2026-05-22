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

    func testToggleSwitchRegularSizeMatchesNSSwitch() {
        XCTAssertEqual(MacOSControlMetrics.Toggle.regularSize.width, 38, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Toggle.regularSize.height, 22, accuracy: 0.001)
    }

    func testToggleSwitchLargeSizeMatchesAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.Toggle.largeSize.width, 44, accuracy: 0.001)
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
        XCTAssertEqual(MacOSControlMetrics.Stepper.buttonSize.width, 19, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Stepper.buttonSize.height, 11, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Stepper.regularSize.width, 19, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Stepper.regularSize.height, 22, accuracy: 0.001)
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

    func testTextFieldHeightsMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.TextField.regularHeight, 21, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.TextField.largeHeight, 28, accuracy: 0.001)
    }

    // MARK: - List

    func testListRowHeightsMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.List.plainRowHeight, 24, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.List.sidebarRowHeight, 28, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.List.chevronColumnInset, 16, accuracy: 0.001)
    }

    // MARK: - Toolbar

    func testToolbarHeightsMatchNSToolbar() {
        XCTAssertEqual(MacOSControlMetrics.Toolbar.regularHeight, 52, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Toolbar.unifiedCompactHeight, 38, accuracy: 0.001)
    }

    // MARK: - Window chrome

    func testWindowCornerRadiusMatchesMacOSSonoma() {
        XCTAssertEqual(MacOSControlMetrics.Window.cornerRadius, 10, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.Window.sheetCornerRadius, 12, accuracy: 0.001)
    }

    // MARK: - Focus ring

    func testFocusRingMetricsMatchAppleHIG() {
        XCTAssertEqual(MacOSControlMetrics.FocusRing.strokeWidth, 4, accuracy: 0.001)
        XCTAssertEqual(MacOSControlMetrics.FocusRing.outsetFromBounds, 3, accuracy: 0.001)
    }

    // MARK: - Layout

    func testDefaultStackSpacingMatchesSwiftUI() {
        XCTAssertEqual(MacOSControlMetrics.Layout.defaultStackSpacing, 8, accuracy: 0.001)
    }

    func testDefaultPaddingMatchesSwiftUI() {
        XCTAssertEqual(MacOSControlMetrics.Layout.defaultPadding, 16, accuracy: 0.001)
    }
}
