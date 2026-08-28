import Foundation

/// Canonicalizes the RGB initializer into the existing retained, unpremultiplied
/// encoded-sRGB components. It does not select a renderer working color space.
/// See docs/ColorSpaceConversion.md for the derivation and numeric policy.
enum RetainedColorSpaceConversion {
    struct Components: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        fileprivate var isFinite: Bool {
            red.isFinite && green.isFinite && blue.isFinite
        }

        fileprivate static let zero = Components(red: 0, green: 0, blue: 0)
    }

    /// Invalid RGB inputs become zero individually. Finite extended components
    /// are not gamut-clipped. A nonfinite P3 intermediate invalidates the whole
    /// RGB conversion, avoiding a partial result contaminated by overflow.
    /// These invalid/overflow rules are a Windows policy, not native evidence.
    static func encodedSRGB(
        from colorSpace: Color.RGBColorSpace,
        red: Double,
        green: Double,
        blue: Double
    ) -> Components {
        let input = Components(
            red: red.isFinite ? red : 0,
            green: green.isFinite ? green : 0,
            blue: blue.isFinite ? blue : 0
        )
        switch colorSpace {
        case .sRGB:
            return input
        case .sRGBLinear:
            return Components(
                red: encodeSRGB(input.red),
                green: encodeSRGB(input.green),
                blue: encodeSRGB(input.blue)
            )
        case .displayP3:
            let linearP3 = Components(
                red: decodeSRGB(input.red),
                green: decodeSRGB(input.green),
                blue: decodeSRGB(input.blue)
            )
            guard linearP3.isFinite else { return .zero }
            // Product of the rational P3->XYZ-D65 and XYZ-D65->sRGB matrices
            // in W3C CSS Color 4 (2026-08-25), section 19. Both spaces use D65;
            // no chromatic adaptation is involved. Matrix rows act on RGB.
            let linearSRGB = Components(
                red: (3_685_649.0 / 3_008_840.0) * linearP3.red
                    - (676_809.0 / 3_008_840.0) * linearP3.green,
                green: -(5_617_931.0 / 133_579_120.0) * linearP3.red
                    + (139_197_051.0 / 133_579_120.0) * linearP3.green,
                blue: -(1_323_971.0 / 67_420_360.0) * linearP3.red
                    - (1_514_763.0 / 19_262_960.0) * linearP3.green
                    + (148_092_003.0 / 134_840_720.0) * linearP3.blue
            )
            guard linearSRGB.isFinite else { return .zero }
            let encoded = Components(
                red: encodeSRGB(linearSRGB.red),
                green: encodeSRGB(linearSRGB.green),
                blue: encodeSRGB(linearSRGB.blue)
            )
            return encoded.isFinite ? encoded : .zero
        }
    }

    /// The signed extension of the sRGB decoding curve. This raw math helper
    /// does not sanitize inputs; the RGB conversion owns that policy.
    static func decodeSRGB(_ value: Double) -> Double {
        let magnitude = abs(value)
        if magnitude <= 0.04045 { return value / 12.92 }
        let linear = pow((magnitude + 0.055) / 1.055, 2.4)
        return value.sign == .minus ? -linear : linear
    }

    /// The inverse transfer curve, extended by reflection below zero. Retain
    /// the published branch threshold rather than forcing exact round trips
    /// across the tiny discontinuity between the rounded transfer constants.
    static func encodeSRGB(_ value: Double) -> Double {
        let magnitude = abs(value)
        if magnitude <= 0.0031308 { return 12.92 * value }
        let encoded = 1.055 * pow(magnitude, 1.0 / 2.4) - 0.055
        return value.sign == .minus ? -encoded : encoded
    }

    /// Only the representable storage range is bounded here, after conversion.
    /// RGB is never restricted to [0, 1]. Alpha does not use this function.
    static func storedFloat(_ value: Double) -> Float {
        guard value.isFinite else { return 0 }
        let limit = Double(Float.greatestFiniteMagnitude)
        return Float(min(max(value, -limit), limit))
    }
}
