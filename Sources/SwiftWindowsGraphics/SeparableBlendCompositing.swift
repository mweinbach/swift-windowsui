import SwiftWindowsCore

/// Pure color algebra used by the CPU's ordinary quad path. D3D11 mirrors this
/// source term before its existing source-over blend.
/// Source color is straight; the supplied destination is premultiplied and may be
/// the virtual surface F + (1 - coverage) * backdrop of an isolated target.
enum SceneSeparableBlendCompositing {
    static func mode(for encoded: Float) -> BlendMode? {
        switch encoded {
        case Float(BlendMode.multiply.rawValue):
            return .multiply
        case Float(BlendMode.screen.rawValue):
            return .screen
        case Float(BlendMode.overlay.rawValue):
            return .overlay
        default:
            return nil
        }
    }

    /// Returns the straight adjusted source. Its alpha is deliberately unchanged:
    /// q = as * ((1 - ad) * Cs + ad * B(Cs, Cd)). Compositing q source-over updates
    /// foreground F while the existing coverage update keeps the inherited
    /// backdrop coefficient correct. Additive is not expressible by this contract.
    static func adjustedSource(
        _ source: Color, premultipliedBackdrop backdrop: Color, mode: BlendMode
    ) -> Color {
        guard mode == .multiply || mode == .screen || mode == .overlay else { return source }
        let destinationAlpha = GPUISceneValue.clamped(backdrop.alpha, lower: 0, upper: 1)
        guard destinationAlpha > 0 else { return source }

        func component(_ sourceValue: Float, _ destinationValue: Float) -> Float {
            let sourceChannel = GPUISceneValue.clamped(sourceValue, lower: 0, upper: 1)
            let destinationChannel = GPUISceneValue.clamped(
                destinationValue / destinationAlpha, lower: 0, upper: 1)
            let mixed: Float
            switch mode {
            case .multiply:
                mixed = sourceChannel * destinationChannel
            case .screen:
                mixed = 1 - (1 - sourceChannel) * (1 - destinationChannel)
            case .overlay:
                mixed =
                    destinationChannel <= 0.5
                    ? 2 * sourceChannel * destinationChannel
                    : 1 - 2 * (1 - sourceChannel) * (1 - destinationChannel)
            case .normal, .additive:
                return sourceValue
            }
            return (1 - destinationAlpha) * sourceChannel + destinationAlpha * mixed
        }

        return Color(
            red: component(source.red, backdrop.red),
            green: component(source.green, backdrop.green),
            blue: component(source.blue, backdrop.blue),
            alpha: source.alpha)
    }
}
