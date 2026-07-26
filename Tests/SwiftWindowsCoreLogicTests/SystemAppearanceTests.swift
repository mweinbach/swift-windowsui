import SwiftWindowsCore

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import WinSwiftUI

/// Fake settings source so host sampling stays headless — no live OS theme
/// flips in unit tests.
final class FakeSystemAppearanceProvider: SystemAppearanceProvider, @unchecked Sendable {
    var snapshot: SystemAppearanceSnapshot
    private(set) var sampleCount = 0

    init(snapshot: SystemAppearanceSnapshot = .unavailable) {
        self.snapshot = snapshot
    }

    func sampleSystemAppearance() -> SystemAppearanceSnapshot {
        sampleCount += 1
        return snapshot
    }
}
@MainActor
final class SystemAppearanceTests: XCTestCase {
    // MARK: - Host sampling (injected provider)

    func testWindowSamplesAppearanceLazilyFromInjectedProvider() async {
        let provider = FakeSystemAppearanceProvider(
            snapshot: SystemAppearanceSnapshot(
                colorSchemePreference: .light,
                isHighContrastEnabled: true,
                textScaleFactor: 1.25,
                prefersReducedMotion: true
            )
        )
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 100, height: 100))
        window.systemAppearanceProvider = provider

        XCTAssertEqual(provider.sampleCount, 0)

        let sampled = window.systemAppearance
        XCTAssertEqual(sampled.colorSchemePreference, .light)
        XCTAssertTrue(sampled.isHighContrastEnabled)
        XCTAssertEqual(sampled.textScaleFactor, 1.25)
        XCTAssertEqual(sampled.prefersReducedMotion, true)
        XCTAssertEqual(provider.sampleCount, 1)
    }

    func testWindowCachesAppearanceUntilInvalidated() async {
        let provider = FakeSystemAppearanceProvider(
            snapshot: SystemAppearanceSnapshot(colorSchemePreference: .light)
        )
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 100, height: 100))
        window.systemAppearanceProvider = provider

        _ = window.systemAppearance
        provider.snapshot = SystemAppearanceSnapshot(colorSchemePreference: .dark)

        // Cached value is served until the settings-change path invalidates.
        XCTAssertEqual(window.systemAppearance.colorSchemePreference, .light)
        XCTAssertEqual(provider.sampleCount, 1)

        window.invalidateSystemAppearanceCache()
        XCTAssertEqual(window.systemAppearance.colorSchemePreference, .dark)
        XCTAssertEqual(provider.sampleCount, 2)
    }

    // MARK: - Mapping tables

    func testHighContrastMapsToIncreasedContrast() async {
        let snapshot = SystemAppearanceSnapshot(isHighContrastEnabled: true)
        XCTAssertEqual(SystemAppearanceMapping.colorSchemeContrast(snapshot: snapshot), .increased)
    }

    func testHighContrastOffMapsToStandardContrast() async {
        let snapshot = SystemAppearanceSnapshot(isHighContrastEnabled: false)
        XCTAssertEqual(SystemAppearanceMapping.colorSchemeContrast(snapshot: snapshot), .standard)
    }

    func testMissingSnapshotKeepsContrastFallback() async {
        XCTAssertEqual(
            SystemAppearanceMapping.colorSchemeContrast(snapshot: nil, fallback: .increased),
            .increased
        )
    }

    func testSystemColorSchemePreferenceMapping() async {
        let dark = SystemAppearanceSnapshot(colorSchemePreference: .dark)
        let light = SystemAppearanceSnapshot(colorSchemePreference: .light)
        XCTAssertEqual(SystemAppearanceMapping.colorScheme(appOverride: nil, snapshot: dark), .dark)
        XCTAssertEqual(SystemAppearanceMapping.colorScheme(appOverride: nil, snapshot: light), .light)
    }

    func testUnknownSystemColorSchemeKeepsFallback() async {
        let snapshot = SystemAppearanceSnapshot(colorSchemePreference: nil)
        XCTAssertEqual(
            SystemAppearanceMapping.colorScheme(appOverride: nil, snapshot: snapshot, fallback: .dark),
            .dark
        )
        XCTAssertEqual(
            SystemAppearanceMapping.colorScheme(appOverride: nil, snapshot: nil, fallback: .light),
            .light
        )
    }

    func testReduceMotionMapping() async {
        let reducing = SystemAppearanceSnapshot(prefersReducedMotion: true)
        let notReducing = SystemAppearanceSnapshot(prefersReducedMotion: false)
        let unknown = SystemAppearanceSnapshot(prefersReducedMotion: nil)
        XCTAssertTrue(SystemAppearanceMapping.accessibilityReduceMotion(appOverride: nil, snapshot: reducing))
        XCTAssertFalse(SystemAppearanceMapping.accessibilityReduceMotion(appOverride: nil, snapshot: notReducing))
        XCTAssertFalse(SystemAppearanceMapping.accessibilityReduceMotion(appOverride: nil, snapshot: unknown))
        XCTAssertTrue(
            SystemAppearanceMapping.accessibilityReduceMotion(appOverride: nil, snapshot: unknown, fallback: true)
        )
    }

    // MARK: - Precedence: app override > system snapshot > toolkit default

    func testAppOverrideWinsOverSystemSnapshot() async {
        let systemDark = SystemAppearanceSnapshot(colorSchemePreference: .dark)
        XCTAssertEqual(
            SystemAppearanceMapping.colorScheme(appOverride: .light, snapshot: systemDark, fallback: .dark),
            .light
        )

        let systemReduceMotion = SystemAppearanceSnapshot(prefersReducedMotion: true)
        XCTAssertFalse(
            SystemAppearanceMapping.accessibilityReduceMotion(
                appOverride: false,
                snapshot: systemReduceMotion,
                fallback: true
            )
        )
    }

    func testSystemSnapshotWinsOverToolkitDefault() async {
        let systemLight = SystemAppearanceSnapshot(colorSchemePreference: .light)
        XCTAssertEqual(
            SystemAppearanceMapping.colorScheme(appOverride: nil, snapshot: systemLight, fallback: .dark),
            .light
        )
    }

    // MARK: - Environment application

    func testApplyingSystemAppearanceUpdatesDerivedValuesOnly() async {
        let base = EnvironmentValues()
        let snapshot = SystemAppearanceSnapshot(
            colorSchemePreference: .light,
            isHighContrastEnabled: true,
            textScaleFactor: 1.5,
            prefersReducedMotion: true
        )

        let resolved = base.applyingSystemAppearance(snapshot)
        XCTAssertEqual(resolved.colorScheme, .light)
        XCTAssertEqual(resolved.colorSchemeContrast, .increased)
        XCTAssertTrue(resolved.accessibilityReduceMotion)

        // Unrelated environment values are untouched.
        XCTAssertEqual(resolved.scenePhase, base.scenePhase)
        XCTAssertEqual(resolved.displayScale, base.displayScale)
        XCTAssertEqual(resolved.dynamicTypeSize, base.dynamicTypeSize)
        XCTAssertEqual(resolved.layoutDirection, base.layoutDirection)
    }

    func testApplyingUnavailableSnapshotKeepsExistingValues() async {
        let base = EnvironmentValues(colorScheme: .light, accessibilityReduceMotion: true)
        let resolved = base.applyingSystemAppearance(.unavailable)

        XCTAssertEqual(resolved.colorScheme, .light)
        XCTAssertEqual(resolved.colorSchemeContrast, .standard)
        XCTAssertTrue(resolved.accessibilityReduceMotion)
    }

    // MARK: - Contrast-response palette

    func testStandardContrastLeavesColorsUntouched() async {
        XCTAssertEqual(Color.secondary.resolvedForContrast(.standard), .secondary)
        XCTAssertEqual(tertiaryFallback.resolvedForContrast(.standard), tertiaryFallback)
        XCTAssertEqual(Color.red.resolvedForContrast(.standard), .red)
    }

    func testIncreasedContrastBrightensSecondary() async {
        let resolved = Color.secondary.resolvedForContrast(.increased)
        XCTAssertEqual(resolved.red, Color.highContrastSecondary.red)
        XCTAssertEqual(resolved.green, Color.highContrastSecondary.green)
        XCTAssertEqual(resolved.blue, Color.highContrastSecondary.blue)
    }

    func testIncreasedContrastRaisesHierarchicalGreyRamp() async {
        let tertiary = tertiaryFallback.resolvedForContrast(.increased)
        let quaternary = HierarchicalShapeStyle.quaternary.retainedFallbackColor.resolvedForContrast(.increased)

        // The ramp moves every level closer to the high-contrast secondary
        // target so low-contrast greys do not survive HC mode.
        XCTAssertGreaterThan(tertiary.red, tertiaryFallback.red)
        XCTAssertGreaterThan(quaternary.red, HierarchicalShapeStyle.quaternary.retainedFallbackColor.red)
        XCTAssertGreaterThanOrEqual(tertiary.red, quaternary.red)
    }

    func testIncreasedContrastPreservesSourceAlphaOnRamp() async {
        let translucent = Color(
            red: tertiaryFallback.red,
            green: tertiaryFallback.green,
            blue: tertiaryFallback.blue,
            alpha: 0.5
        )
        XCTAssertEqual(translucent.resolvedForContrast(.increased).alpha, 0.5)
    }

    func testIncreasedContrastLeavesNonSemanticColorsUntouched() async {
        XCTAssertEqual(Color.red.resolvedForContrast(.increased), .red)
        XCTAssertEqual(Color.accentColor.resolvedForContrast(.increased), .accentColor)
        XCTAssertEqual(Color.black.opacity(0.4).resolvedForContrast(.increased), Color.black.opacity(0.4))
    }

    private var tertiaryFallback: Color {
        HierarchicalShapeStyle.tertiary.retainedFallbackColor
    }
}
