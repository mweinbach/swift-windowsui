import Foundation

/// Which face the stack draws UI text in, and at which optical size.
///
/// Windows 11 ships **Segoe UI Variable** and uses it for every piece of
/// system UI; Windows 10 has only the classic **Segoe UI**. Text drawn in
/// the classic face on Windows 11 is the single loudest "this is not a
/// modern app" signal a window can emit, because every surface around it —
/// Settings, Explorer, the Start menu, every WinUI app — is in the variable
/// face. So the default UI face is resolved, once per process, against what
/// is actually installed.
///
/// ## Optical size is not a weight
///
/// Segoe UI Variable is a variable font with an `opsz` axis, and Windows
/// exposes that axis as three named families rather than one. They are not
/// interchangeable styles: `Small` has open apertures and loose spacing so a
/// 10pt caption stays legible, `Display` has tight spacing and fine strokes
/// that only resolve at headline size. Setting a headline in `Small` looks
/// clumsy and a caption in `Display` looks broken, which is why this type
/// picks the family from the **point** size.
///
/// Point size, specifically — never device pixels. Optical size tracks the
/// *physical* size the reader sees, and that is what a point already is: a
/// 10pt caption is a 10pt caption at 96 DPI and at 144 DPI, drawn from more
/// device pixels but at the same apparent size. Keying the ramp off device
/// pixels would put 8pt text at 150% scale (12 device px) in the same family
/// as 12pt text at 100%, and the glyph atlas — whose key is device pixels —
/// would then hold one entry standing for two different faces.
///
/// See `docs/Typography.md`.
@MainActor
public enum SystemUIFontFace {

    /// The three optical sizes Segoe UI Variable is cut in.
    public enum OpticalSize: String, Sendable, CaseIterable {
        case small
        case text
        case display
    }

    /// The Windows 10 face, and the fallback whenever the variable face is
    /// not installed. Also the answer for every non-UI design (`.serif`,
    /// `.monospaced`), which resolve their own families elsewhere.
    public static let classicFamily = "Segoe UI"

    /// Below this point size, text is set in the `Small` optical size.
    ///
    /// 12pt is where the Windows 11 type ramp puts its Caption/Body seam
    /// (Caption 12px ≈ 9pt, Body 14px ≈ 10.5pt, in the ramp's own device
    /// units at 100%). In this stack's macOS-derived point ramp that lands
    /// footnote, caption and caption2 (10pt) and subheadline (11pt) in
    /// `Small`, which is exactly the text that needs its apertures open.
    public static let smallOpticalSizeUpperBound: Double = 12

    /// At and above this point size, text is set in the `Display` optical
    /// size: title (22pt) and largeTitle (26pt). Everything between the two
    /// bounds — callout 12, body and headline 13, title3 15, title2 17 —
    /// is `Text`, the face the bulk of an app is set in.
    public static let displayOpticalSizeLowerBound: Double = 20

    public static func family(for opticalSize: OpticalSize) -> String {
        switch opticalSize {
        case .small:
            return "Segoe UI Variable Small"
        case .text:
            return "Segoe UI Variable Text"
        case .display:
            return "Segoe UI Variable Display"
        }
    }

    /// The optical size a run of `points` should be set in.
    ///
    /// Non-finite or non-positive sizes answer `.text`: a caller that has
    /// lost its point size should get the body face, not a headline one.
    public static func opticalSize(forPointSize points: Double) -> OpticalSize {
        guard points.isFinite, points > 0 else {
            return .text
        }
        if points < smallOpticalSizeUpperBound {
            return .small
        }
        if points >= displayOpticalSizeLowerBound {
            return .display
        }
        return .text
    }

    /// The UI font family for a run of `points`, honouring what is installed.
    public static func family(forPointSize points: Double) -> String {
        guard isVariableFaceAvailable else {
            return classicFamily
        }
        return family(for: opticalSize(forPointSize: points))
    }

    /// Whether every optical size of the variable face is installed.
    ///
    /// All three or none: a window that set its captions in Segoe UI Variable
    /// Small and its headlines in classic Segoe UI would be visibly mixing
    /// two type designs, which is worse than either face used consistently.
    public static var isVariableFaceAvailable: Bool {
        if let override = availabilityOverrideForTesting {
            return override
        }
        if let cached = cachedAvailability {
            return cached
        }
        if ProcessInfo.processInfo.environment["SWIFT_WINDOWSUI_CLASSIC_UI_FONT"] == "1" {
            // The Windows 10 branch, on demand. Without it the fallback path
            // is unreachable — and therefore uninspectable — on any machine
            // that actually has the variable face installed, which is every
            // Windows 11 machine this stack is developed on.
            cachedAvailability = false
            return false
        }
        let resolved = OpticalSize.allCases.allSatisfy { size in
            // `nil` — DirectWrite itself missing — is a "no": without the
            // font collection there is no evidence the face is there, and
            // the classic face is the safe answer.
            DirectWriteTextRenderer.isFontFamilyInstalled(family(for: size)) ?? false
        }
        cachedAvailability = resolved
        return resolved
    }

    /// Memoized for the process: the answer cannot change while it runs
    /// short of a font install, and `FindFamilyName` is three COM round trips
    /// that would otherwise run on every `Text` in every rebuilt body.
    private static var cachedAvailability: Bool?

    /// Test seam: forces the verdict without touching the font collection, so
    /// both the Windows 11 and the Windows 10 branch are exercised on either.
    public static var availabilityOverrideForTesting: Bool?

    /// Test seam: drops the memo so the next query probes DirectWrite again.
    public static func resetAvailabilityCacheForTesting() {
        cachedAvailability = nil
        availabilityOverrideForTesting = nil
    }

    /// Test seam: whether the process has already probed.
    public static var hasProbedAvailabilityForTesting: Bool {
        cachedAvailability != nil
    }
}
