import SwiftWindowsCore

import SwiftWindowsPlatform

/// Maps a sampled `SystemAppearanceSnapshot` onto WinSwiftUI environment
/// appearance values.
///
/// Precedence (highest first):
/// 1. App overrides — `preferredColorScheme(_:)` or explicit
///    `environment(\.colorScheme, ...)` / `environment(\.colorSchemeContrast, ...)`
///    sets applied deeper in the view tree.
/// 2. System snapshot — the values derived here, applied to the host's base
///    environment via `EnvironmentValues.applyingSystemAppearance(_:)`.
/// 3. Toolkit defaults — the `EnvironmentValues` defaults used when no
///    snapshot is available (or a snapshot field is `nil`).
public enum SystemAppearanceMapping {
    /// Effective color scheme: an explicit app override wins, then the
    /// system preference, then the supplied fallback (toolkit default).
    public static func colorScheme(
        appOverride: ColorScheme?,
        snapshot: SystemAppearanceSnapshot?,
        fallback: ColorScheme = .dark
    ) -> ColorScheme {
        if let appOverride {
            return appOverride
        }

        switch snapshot?.colorSchemePreference {
        case .light:
            return .light
        case .dark:
            return .dark
        case nil:
            return fallback
        }
    }

    /// Effective contrast: Windows high contrast maps to
    /// `ColorSchemeContrast.increased`; anything else keeps the fallback.
    public static func colorSchemeContrast(
        snapshot: SystemAppearanceSnapshot?,
        fallback: ColorSchemeContrast = .standard
    ) -> ColorSchemeContrast {
        guard let snapshot else {
            return fallback
        }

        return snapshot.isHighContrastEnabled ? .increased : .standard
    }

    /// Effective reduce-motion flag: an explicit app override wins, then the
    /// system preference, then the supplied fallback.
    public static func accessibilityReduceMotion(
        appOverride: Bool?,
        snapshot: SystemAppearanceSnapshot?,
        fallback: Bool = false
    ) -> Bool {
        appOverride ?? snapshot?.prefersReducedMotion ?? fallback
    }
}
extension EnvironmentValues {
    /// Returns a copy with system-derived appearance applied on top of the
    /// receiver's current (default) values. Snapshot fields that are
    /// unavailable (`nil`) leave the receiver's values untouched, so toolkit
    /// defaults survive. App-level overrides set downstream
    /// (`preferredColorScheme`, explicit `environment(_:_:)`) still win —
    /// see `SystemAppearanceMapping` for the full precedence contract.
    ///
    /// Note: `textScaleFactor` is sampled but intentionally not mapped onto
    /// `dynamicTypeSize` yet; bucketing the OS text scale into dynamic-type
    /// sizes is a follow-up.
    public func applyingSystemAppearance(_ snapshot: SystemAppearanceSnapshot) -> EnvironmentValues {
        var resolved = self
        resolved.colorScheme = SystemAppearanceMapping.colorScheme(
            appOverride: nil,
            snapshot: snapshot,
            fallback: colorScheme
        )
        resolved.colorSchemeContrast = SystemAppearanceMapping.colorSchemeContrast(
            snapshot: snapshot,
            fallback: colorSchemeContrast
        )
        resolved.accessibilityReduceMotion = SystemAppearanceMapping.accessibilityReduceMotion(
            appOverride: nil,
            snapshot: snapshot,
            fallback: accessibilityReduceMotion
        )
        return resolved
    }
}
