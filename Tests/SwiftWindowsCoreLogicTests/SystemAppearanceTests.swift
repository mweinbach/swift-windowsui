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

    // MARK: - WM_SETTINGCHANGE lParam is attacker-controlled

    /// `PostMessage(HWND_BROADCAST, WM_SETTINGCHANGE, …)` delivers `lParam`
    /// untouched, so every one of these values can reach the wndproc from a
    /// process that wishes this one harm. None of them may fault: the
    /// section classifies as absent and the routing table answers that case.
    func testSettingChangeSectionRefusesLParamValuesItCannotRead() async {
        XCTAssertNil(Win32Window.settingChangeSection(0), "null is not a section pointer")

        // Reserved but never committed: the address is inside this process's
        // address space and reading it is still an access violation.
        let reserved = VirtualAlloc(nil, SIZE_T(Self.pageSize), DWORD(MEM_RESERVE), DWORD(PAGE_NOACCESS))
        XCTAssertNotNil(reserved)
        XCTAssertNil(Win32Window.settingChangeSection(Self.lParam(for: reserved!)))

        // Committed but explicitly unreadable.
        let noAccess = VirtualAlloc(
            nil, SIZE_T(Self.pageSize), DWORD(MEM_RESERVE | MEM_COMMIT), DWORD(PAGE_NOACCESS))
        XCTAssertNotNil(noAccess)
        XCTAssertNil(Win32Window.settingChangeSection(Self.lParam(for: noAccess!)))

        // A plausible-looking constant of the kind a fuzzer posts.
        XCTAssertNil(Win32Window.settingChangeSection(LPARAM(bitPattern: UInt64(0x0000_0DEA_D000_0000))))

        VirtualFree(reserved, 0, DWORD(MEM_RELEASE))
        VirtualFree(noAccess, 0, DWORD(MEM_RELEASE))
    }

    /// A real `LPCWSTR` is `WCHAR`-aligned. An odd address is not one, and an
    /// unaligned load is undefined behaviour before it is ever a fault.
    func testSettingChangeSectionRefusesAMisalignedPointer() async {
        let page = VirtualAlloc(
            nil, SIZE_T(Self.pageSize), DWORD(MEM_RESERVE | MEM_COMMIT), DWORD(PAGE_READWRITE))
        XCTAssertNotNil(page)
        defer { VirtualFree(page, 0, DWORD(MEM_RELEASE)) }

        XCTAssertNil(Win32Window.settingChangeSection(Self.lParam(for: page!) + 1))
    }

    /// The readable case still resolves, so hardening the base address did
    /// not cost the classification the routing depends on.
    func testSettingChangeSectionReadsAReadableSectionName() async {
        let page = VirtualAlloc(
            nil, SIZE_T(Self.pageSize), DWORD(MEM_RESERVE | MEM_COMMIT), DWORD(PAGE_READWRITE))
        XCTAssertNotNil(page)
        defer { VirtualFree(page, 0, DWORD(MEM_RELEASE)) }

        let units = Array("ImmersiveColorSet".utf16) + [0]
        let destination = page!.bindMemory(to: WCHAR.self, capacity: units.count)
        for (index, unit) in units.enumerated() {
            destination[index] = unit
        }

        let section = Win32Window.settingChangeSection(Self.lParam(for: page!))
        XCTAssertEqual(section, "ImmersiveColorSet")
        XCTAssertEqual(
            Win32Window.settingChangeDelivery(wParam: 0, section: section), .unconditional,
            "the theme broadcast still arrives with wParam == 0, which is why wParam is not the gate")
    }

    /// An unterminated name at the tail of a committed page whose successor
    /// is only reserved: the scan must stop at the region edge instead of
    /// walking into the hole.
    func testSettingChangeSectionStopsAtAnUncommittedPageBoundary() async {
        let span = VirtualAlloc(nil, SIZE_T(Self.pageSize * 2), DWORD(MEM_RESERVE), DWORD(PAGE_NOACCESS))
        XCTAssertNotNil(span)
        defer { VirtualFree(span, 0, DWORD(MEM_RELEASE)) }
        XCTAssertNotNil(VirtualAlloc(span, SIZE_T(Self.pageSize), DWORD(MEM_COMMIT), DWORD(PAGE_READWRITE)))

        // Four non-zero WCHARs flush against the end of the committed page.
        let tail = span!.advanced(by: Self.pageSize - 8)
        let letters = tail.bindMemory(to: WCHAR.self, capacity: 4)
        for index in 0..<4 {
            letters[index] = WCHAR(0x0041)
        }

        XCTAssertEqual(Win32Window.readableUnitCount(from: UInt(bitPattern: tail), limit: 64), 4)
        XCTAssertNil(Win32Window.settingChangeSection(Self.lParam(for: tail)))
    }

    func testReadableUnitCountMeasuresRatherThanGuesses() async {
        XCTAssertEqual(Win32Window.readableUnitCount(from: 0, limit: 64), 0)

        let page = VirtualAlloc(
            nil, SIZE_T(Self.pageSize), DWORD(MEM_RESERVE | MEM_COMMIT), DWORD(PAGE_READWRITE))
        XCTAssertNotNil(page)
        defer { VirtualFree(page, 0, DWORD(MEM_RELEASE)) }

        XCTAssertEqual(Win32Window.readableUnitCount(from: UInt(bitPattern: page!), limit: 0), 0)
        XCTAssertEqual(Win32Window.readableUnitCount(from: UInt(bitPattern: page!), limit: 64), 64)
        XCTAssertEqual(
            Win32Window.readableUnitCount(from: UInt.max - 1, limit: 64), 0,
            "an address whose span overflows is not readable, it is arithmetic")
    }

    /// The wndproc pairs a possibly-unreadable `lParam` with `wParam`. When
    /// the section cannot be read the classification falls back to `wParam`
    /// alone, which is why the font/metrics broadcasts survive a hostile
    /// pointer and the anonymous ones stay filtered.
    func testSettingChangeClassificationSurvivesAnUnreadableLParam() async {
        let hostile = LPARAM(bitPattern: UInt64(0x0000_0DEA_D000_0000))
        XCTAssertEqual(
            Win32Window.settingChangeDelivery(
                wParam: WPARAM(SPI_SETNONCLIENTMETRICS),
                section: Win32Window.settingChangeSection(hostile)),
            .unconditional)
        XCTAssertEqual(
            Win32Window.settingChangeDelivery(
                wParam: 0, section: Win32Window.settingChangeSection(hostile)),
            .whenAppearanceChanged)
        XCTAssertEqual(
            Win32Window.settingChangeDelivery(
                wParam: WPARAM(SPI_SETHIGHCONTRAST), section: Win32Window.settingChangeSection(0)),
            .unconditional)
    }

    private static let pageSize = 4096

    private static func lParam(for pointer: UnsafeMutableRawPointer) -> LPARAM {
        LPARAM(bitPattern: UInt64(UInt(bitPattern: pointer)))
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
    //
    // Resolution now takes the appearance as well as the contrast: the
    // semantic label colours are one alpha ladder over a base that the
    // colour scheme picks. `resolvedForContrast` on its own could not
    // express that and is gone.

    func testStandardContrastLeavesAppAuthoredColorsUntouched() async {
        XCTAssertEqual(Color.red.resolved(.dark, .standard), .red)
        XCTAssertEqual(Color.accentColor.resolved(.dark, .standard), .accentColor)
        XCTAssertEqual(Color.black.opacity(0.4).resolved(.light, .standard), Color.black.opacity(0.4))
    }

    func testIncreasedContrastBrightensSecondaryInDarkAppearance() async {
        let standard = Color.secondary.resolved(.dark, .standard)
        let increased = Color.secondary.resolved(.dark, .increased)
        XCTAssertGreaterThan(increased.alpha, standard.alpha)
        XCTAssertEqual(increased, ControlPalette.darkIncreased.secondaryLabel)
    }

    func testIncreasedContrastDarkensSecondaryInLightAppearance() async {
        let standard = Color.secondary.resolved(.light, .standard)
        let increased = Color.secondary.resolved(.light, .increased)
        XCTAssertGreaterThan(increased.alpha, standard.alpha)
        XCTAssertEqual(increased, ControlPalette.lightIncreased.secondaryLabel)
    }

    func testIncreasedContrastRaisesTheWholeHierarchicalRamp() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let tertiaryStandard = tertiaryFallback.resolved(scheme, .standard)
            let tertiaryIncreased = tertiaryFallback.resolved(scheme, .increased)
            XCTAssertGreaterThan(
                tertiaryIncreased.alpha, tertiaryStandard.alpha,
                "\(scheme): low-contrast greys must not survive HC mode")
        }
    }

    func testIncreasedContrastKeepsTheRampOrdered() async {
        let secondary = Color.secondary.resolved(.dark, .increased)
        let tertiary = tertiaryFallback.resolved(.dark, .increased)
        XCTAssertGreaterThanOrEqual(secondary.alpha, tertiary.alpha)
    }

    func testIncreasedContrastLeavesNonSemanticColorsUntouched() async {
        XCTAssertEqual(Color.red.resolved(.dark, .increased), .red)
        XCTAssertEqual(Color.accentColor.resolved(.dark, .increased), .accentColor)
        XCTAssertEqual(Color.black.opacity(0.4).resolved(.dark, .increased), Color.black.opacity(0.4))
    }

    private var tertiaryFallback: Color {
        HierarchicalShapeStyle.tertiary.retainedFallbackColor
    }
}

extension Color {
    fileprivate func resolved(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Color {
        resolvedForVisualEnvironment(
            colorScheme: scheme, contrast: contrast, backgroundProminence: .standard)
    }
}
