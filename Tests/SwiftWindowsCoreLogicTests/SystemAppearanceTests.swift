import SwiftWindowsCore
import WinSDK

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
/// Counts settings-change deliveries so the filter can be measured rather
/// than argued about.
final class SettingsChangeCountingDelegate: WindowDelegate {
    private(set) var settingsChangeCount = 0

    func windowDidChangeSystemSettings(_ window: Win32Window) {
        settingsChangeCount += 1
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

    // MARK: - Settings-change routing

    /// Builds a headless window wired to a fake provider and a counting
    /// delegate. The delegate is returned so the caller keeps it alive —
    /// `Win32Window.delegate` is weak.
    private func makeSettingsChangeWindow(
        snapshot: SystemAppearanceSnapshot = .unavailable
    ) -> (Win32Window, FakeSystemAppearanceProvider, SettingsChangeCountingDelegate) {
        let provider = FakeSystemAppearanceProvider(snapshot: snapshot)
        let delegate = SettingsChangeCountingDelegate()
        let window = Win32Window(title: "Test", clientSize: IntSize(width: 100, height: 100))
        window.systemAppearanceProvider = provider
        window.delegate = delegate
        _ = window.systemAppearance
        return (window, provider, delegate)
    }

    /// The high-frequency generic broadcasts — environment variables, policy
    /// refreshes, any `SystemParametersInfo` write by any process — stay
    /// filtered when nothing the app can see moved.
    func testGenericBroadcastStaysFilteredWhenAppearanceIsUnchanged() async {
        let (window, _, delegate) = makeSettingsChangeWindow()

        XCTAssertFalse(window.routeSettingChange(wParam: 0, section: "Environment"))
        XCTAssertFalse(window.routeSettingChange(wParam: 0, section: "Policy"))
        XCTAssertFalse(window.routeSettingChange(wParam: 0, section: nil))
        XCTAssertEqual(delegate.settingsChangeCount, 0)
    }

    func testGenericBroadcastIsDeliveredWhenAppearanceActuallyChanged() async {
        let (window, provider, delegate) = makeSettingsChangeWindow(
            snapshot: SystemAppearanceSnapshot(colorSchemePreference: .light))

        provider.snapshot = SystemAppearanceSnapshot(colorSchemePreference: .dark)
        XCTAssertTrue(window.routeSettingChange(wParam: 0, section: "Environment"))
        XCTAssertEqual(delegate.settingsChangeCount, 1)
    }

    /// Metrics and font broadcasts change what the app draws and are not in
    /// the four-field snapshot, so gating them on it silenced them entirely.
    func testMetricsAndFontBroadcastsReachTheDelegateWithoutASnapshotChange() async {
        let (window, _, delegate) = makeSettingsChangeWindow()

        XCTAssertTrue(window.routeSettingChange(wParam: WPARAM(SPI_SETNONCLIENTMETRICS), section: nil))
        XCTAssertTrue(window.routeSettingChange(wParam: WPARAM(SPI_SETICONTITLELOGFONT), section: nil))
        XCTAssertTrue(window.routeSettingChange(wParam: WPARAM(SPI_SETFONTSMOOTHINGTYPE), section: nil))
        XCTAssertEqual(delegate.settingsChangeCount, 3)
    }

    /// `ImmersiveColorSet` is the dark-mode switch, and it can arrive before
    /// the registry value it announces reads back changed — so it must not
    /// depend on the re-sample moving.
    func testThemeAndLocaleSectionsReachTheDelegateWithoutASnapshotChange() async {
        let (window, _, delegate) = makeSettingsChangeWindow()

        XCTAssertTrue(window.routeSettingChange(wParam: 0, section: "ImmersiveColorSet"))
        XCTAssertTrue(window.routeSettingChange(wParam: 0, section: "immersivecolorset"))
        XCTAssertTrue(window.routeSettingChange(wParam: 0, section: "WindowsThemeElement"))
        XCTAssertTrue(window.routeSettingChange(wParam: 0, section: "intl"))
        XCTAssertEqual(delegate.settingsChangeCount, 4)
    }

    /// High contrast is in the snapshot, but the sampler degrades to `false`
    /// when `SystemParametersInfo` fails; an unconditional route means a
    /// failed sample cannot swallow the switch.
    func testHighContrastBroadcastReachesTheDelegateEvenWhenSamplingFails() async {
        let (window, _, delegate) = makeSettingsChangeWindow()

        XCTAssertTrue(window.routeSettingChange(wParam: WPARAM(SPI_SETHIGHCONTRAST), section: nil))
        XCTAssertEqual(delegate.settingsChangeCount, 1)
    }

    /// System colours are not in the snapshot at all, and the message is rare:
    /// it keeps the cheap unconditional path.
    func testSystemColorChangeAlwaysReachesTheDelegate() async {
        let (window, _, delegate) = makeSettingsChangeWindow()

        window.routeSystemColorChange()
        window.routeSystemColorChange()
        XCTAssertEqual(delegate.settingsChangeCount, 2)
    }

    /// Every route re-samples, whether or not it forwards: a filtered
    /// broadcast must not leave a stale snapshot cached.
    func testFilteredBroadcastStillReSamplesTheSnapshot() async {
        let (window, provider, _) = makeSettingsChangeWindow(
            snapshot: SystemAppearanceSnapshot(colorSchemePreference: .light))
        XCTAssertEqual(provider.sampleCount, 1)

        XCTAssertFalse(window.routeSettingChange(wParam: 0, section: "Environment"))
        XCTAssertEqual(provider.sampleCount, 2, "a filtered broadcast still refreshes the cache")
        XCTAssertEqual(window.systemAppearance.colorSchemePreference, .light)
        XCTAssertEqual(provider.sampleCount, 2, "and the refreshed value is cached again")
    }

    func testSettingChangeClassificationTable() async {
        XCTAssertEqual(
            Win32Window.settingChangeDelivery(wParam: WPARAM(SPI_SETNONCLIENTMETRICS), section: nil),
            .unconditional)
        XCTAssertEqual(
            Win32Window.settingChangeDelivery(wParam: 0, section: "ImmersiveColorSet"),
            .unconditional)
        XCTAssertEqual(
            Win32Window.settingChangeDelivery(wParam: 0, section: "Environment"),
            .whenAppearanceChanged)
        XCTAssertEqual(
            Win32Window.settingChangeDelivery(wParam: 0, section: nil),
            .whenAppearanceChanged)
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
