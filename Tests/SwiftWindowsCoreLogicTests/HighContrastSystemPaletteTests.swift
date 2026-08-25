import SwiftWindowsCore
import WinSDK
import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

@MainActor
final class HighContrastSystemPaletteTests: XCTestCase {
    private static let darkColors = HighContrastSystemColors(
        windowBackground: Color(red: 0.04, green: 0.07, blue: 0.12, alpha: 1),
        windowText: Color(red: 1, green: 0.92, blue: 0.18, alpha: 1),
        controlBackground: Color(red: 0.12, green: 0.18, blue: 0.25, alpha: 1),
        controlText: Color(red: 0.68, green: 0.90, blue: 1, alpha: 1),
        selectedBackground: Color(red: 0.16, green: 0.45, blue: 0.78, alpha: 1),
        selectedText: Color(red: 0.98, green: 1, blue: 0.97, alpha: 1),
        disabledText: Color(red: 0.41, green: 0.52, blue: 0.60, alpha: 1),
        linkText: Color(red: 0.37, green: 0.86, blue: 1, alpha: 1)
    )

    private static let lightColors = HighContrastSystemColors(
        windowBackground: Color(red: 1, green: 0.97, blue: 0.88, alpha: 1),
        windowText: Color(red: 0.08, green: 0.02, blue: 0.16, alpha: 1),
        controlBackground: Color(red: 0.95, green: 0.90, blue: 0.72, alpha: 1),
        controlText: Color(red: 0.14, green: 0.04, blue: 0.22, alpha: 1),
        selectedBackground: Color(red: 0.30, green: 0.12, blue: 0.54, alpha: 1),
        selectedText: Color(red: 1, green: 0.96, blue: 0.82, alpha: 1),
        disabledText: Color(red: 0.48, green: 0.40, blue: 0.33, alpha: 1),
        linkText: Color(red: 0.20, green: 0.10, blue: 0.62, alpha: 1)
    )

    private func snapshot(
        colors: HighContrastSystemColors,
        preference: SystemAppearanceSnapshot.ColorSchemePreference? = nil,
        enabled: Bool = true
    ) -> SystemAppearanceSnapshot {
        SystemAppearanceSnapshot(
            colorSchemePreference: preference,
            isHighContrastEnabled: enabled,
            highContrastColors: colors
        )
    }

    private func context(for snapshot: SystemAppearanceSnapshot) -> ViewBuildContext {
        let environment = EnvironmentValues().applyingSystemAppearance(snapshot)
        return ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) },
            invalidateHandler: {},
            environmentValuesProvider: { environment }
        )
    }

    func testWindowsCOLORREFChannelOrderIsConvertedWithoutSwappingRedAndBlue() async {
        let color = Win32SystemAppearanceProvider.systemColor(from: DWORD(0x00_56_34_12))
        XCTAssertEqual(color.red, Float(0x12) / 255, accuracy: 0.0001)
        XCTAssertEqual(color.green, Float(0x34) / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blue, Float(0x56) / 255, accuracy: 0.0001)
        XCTAssertEqual(color.alpha, 1)
    }

    func testDarkContrastThemeWinsOverUnrelatedLightRegistryPreference() async {
        let resolved = SystemAppearanceMapping.colorScheme(
            appOverride: nil,
            snapshot: snapshot(colors: Self.darkColors, preference: .light)
        )
        XCTAssertEqual(resolved, .dark)
        XCTAssertFalse(Self.darkColors.prefersLightAppearance)
    }

    func testLightContrastThemeWinsOverUnrelatedDarkRegistryPreference() async {
        let resolved = SystemAppearanceMapping.colorScheme(
            appOverride: nil,
            snapshot: snapshot(colors: Self.lightColors, preference: .dark)
        )
        XCTAssertEqual(resolved, .light)
        XCTAssertTrue(Self.lightColors.prefersLightAppearance)
    }

    func testExplicitAppAppearanceOverrideStillWins() async {
        XCTAssertEqual(
            SystemAppearanceMapping.colorScheme(
                appOverride: .light,
                snapshot: snapshot(colors: Self.darkColors, preference: .dark)
            ),
            .light
        )
    }

    func testHighContrastPaletteMapsNativeSurfaceTextAndSelectionRoles() async {
        let colors = Self.darkColors
        let palette = ControlPalette.resolve(colorScheme: .dark, contrast: .increased, systemColors: colors)
        XCTAssertEqual(palette.windowBackground, colors.windowBackground)
        XCTAssertEqual(palette.controlBackground, colors.windowBackground)
        XCTAssertEqual(palette.controlSurface, colors.controlBackground)
        XCTAssertEqual(palette.raisedSurface, colors.controlBackground)
        XCTAssertEqual(palette.label, colors.windowText)
        XCTAssertEqual(palette.secondaryLabel, colors.windowText)
        XCTAssertEqual(palette.tertiaryLabel, colors.controlText)
        XCTAssertEqual(palette.disabledLabel, colors.disabledText)
        XCTAssertEqual(palette.selectedContentLabel, colors.selectedText)
        XCTAssertEqual(palette.unemphasizedSelectedBackground, colors.selectedBackground)
        XCTAssertEqual(palette.controlBorder, colors.controlText)
        XCTAssertEqual(palette.controlBorderStrong, colors.selectedBackground)
    }

    func testNativePaletteNeverLeaksIntoStandardContrast() async {
        XCTAssertEqual(
            ControlPalette.resolve(colorScheme: .dark, contrast: .standard, systemColors: Self.darkColors),
            ControlPalette.darkStandard
        )
    }

    func testEnvironmentInheritsAndClearsCustomHighContrastColors() async {
        let active = EnvironmentValues().applyingSystemAppearance(snapshot(colors: Self.darkColors))
        XCTAssertEqual(active.colorSchemeContrast, .increased)
        XCTAssertEqual(active.systemHighContrastColors, Self.darkColors)

        let inactive = active.applyingSystemAppearance(snapshot(colors: Self.darkColors, enabled: false))
        XCTAssertEqual(inactive.colorSchemeContrast, .standard)
        XCTAssertNil(inactive.systemHighContrastColors)
    }

    func testViewContextUsesNativeThemeForControlsAccentAndSemanticText() async {
        let colors = Self.darkColors
        let resolved = context(for: snapshot(colors: colors))
        XCTAssertEqual(resolved.controlPalette.windowBackground, colors.windowBackground)
        XCTAssertEqual(resolved.controlPalette.label, colors.windowText)
        XCTAssertEqual(resolved.tint, colors.selectedBackground)
        XCTAssertEqual(resolved.foregroundColor, colors.windowText)
    }

    func testSelectedSemanticTextUsesNativeHighlightForeground() async {
        XCTAssertEqual(
            Color.primary.resolvedForVisualEnvironment(
                colorScheme: .dark,
                contrast: .increased,
                backgroundProminence: .increased,
                systemColors: Self.darkColors
            ),
            Self.darkColors.selectedText
        )
        XCTAssertEqual(
            Color.quaternary.resolvedForBackgroundVisualEnvironment(
                colorScheme: .dark,
                contrast: .increased,
                backgroundProminence: .standard,
                systemColors: Self.darkColors
            ),
            Self.darkColors.windowBackground
        )
    }

    func testContrastColorChangesInvalidateAppearanceSnapshotEquality() async {
        let original = snapshot(colors: Self.darkColors)
        var changedColors = Self.darkColors
        changedColors.selectedBackground = Color(red: 1, green: 0, blue: 0.5, alpha: 1)
        XCTAssertNotEqual(original, snapshot(colors: changedColors))
    }
}
