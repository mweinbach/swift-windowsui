import SwiftWindowsCore

/// Saturated premultiplied addition for ordinary quads. The source is straight;
/// its alpha already includes geometric and clip coverage. The destination is
/// premultiplied, including the virtual F + (1-K)B of an isolated target.
enum SceneAdditiveBlendCompositing {
    /// Add this increment to local foreground F without changing replacement K.
    /// RGB can exceed increment alpha, including a positive color at alpha zero.
    /// Unpremultiplying this contribution would lose that color.
    static func premultipliedIncrement(
        source: Color, premultipliedBackdrop backdrop: Color
    ) -> Color {
        let sourceAlpha = GPUISceneValue.clamped(source.alpha, lower: 0, upper: 1)
        guard sourceAlpha > 0 else { return .clear }

        func increment(_ sourceComponent: Float, _ destinationComponent: Float) -> Float {
            let destination = GPUISceneValue.clamped(destinationComponent, lower: 0, upper: 1)
            // Equivalent to saturate(S+D)-D for normalized nonnegative inputs,
            // without subtracting nearly equal values for a small source.
            return min(sourceComponent, max(0, 1 - destination))
        }

        return Color(
            red: increment(GPUISceneValue.clamped(source.red, lower: 0, upper: 1) * sourceAlpha, backdrop.red),
            green: increment(GPUISceneValue.clamped(source.green, lower: 0, upper: 1) * sourceAlpha, backdrop.green),
            blue: increment(GPUISceneValue.clamped(source.blue, lower: 0, upper: 1) * sourceAlpha, backdrop.blue),
            alpha: increment(sourceAlpha, backdrop.alpha))
    }
}
