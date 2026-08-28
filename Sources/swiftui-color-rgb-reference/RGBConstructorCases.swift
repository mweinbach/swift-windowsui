#if os(Windows)
    import WinSwiftUI
#elseif os(macOS)
    import SwiftUI
#else
    #error("The canonical RGB reference fixture supports only Windows and macOS.")
#endif

enum RGBConstructorSpace: String, Sendable {
    case sRGB = "srgb"
    case sRGBLinear = "srgb-linear"
    case displayP3 = "display-p3"

    var colorSpace: Color.RGBColorSpace {
        switch self {
        case .sRGB: return .sRGB
        case .sRGBLinear: return .sRGBLinear
        case .displayP3: return .displayP3
        }
    }
}

enum RGBConstructorDomain: String, Sendable {
    case requiredFinite = "required-finite"
    case exploratoryExtendedP3 = "exploratory-extended-p3"
}

/// Inputs, not a conversion oracle. Both platforms invoke the public initializer
/// through the same typed function reference; neither observer recomputes RGB.
struct RGBConstructorCase: Sendable {
    let id: String
    let space: RGBConstructorSpace
    let domain: RGBConstructorDomain
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    @MainActor
    func makeColor() -> Color {
        let constructor: (Color.RGBColorSpace, Double, Double, Double, Double) -> Color =
            Color.init(_:red:green:blue:opacity:)
        return constructor(space.colorSpace, red, green, blue, opacity)
    }

    static let protocolID = "canonical-rgb-constructor-v1"
    static let caseSetID = "canonical-rgb-finite-23-plus-exploratory-p3-2-v1"

    static let all: [RGBConstructorCase] = [
        .init(id: "srgb-zero", space: .sRGB, domain: .requiredFinite, red: 0, green: 0, blue: 0, opacity: 1),
        .init(id: "srgb-white", space: .sRGB, domain: .requiredFinite, red: 1, green: 1, blue: 1, opacity: 1),
        .init(
            id: "srgb-interior", space: .sRGB, domain: .requiredFinite, red: 0.25, green: 0.5, blue: 0.75, opacity: 1),
        .init(id: "srgb-extended", space: .sRGB, domain: .requiredFinite, red: -0.5, green: 1.25, blue: 2, opacity: 1),
        .init(
            id: "srgb-alpha-zero", space: .sRGB, domain: .requiredFinite, red: 0.25, green: 0.5, blue: 0.75, opacity: 0),
        .init(
            id: "srgb-alpha-fraction", space: .sRGB, domain: .requiredFinite, red: 0.25, green: 0.5, blue: 0.75,
            opacity: 0.625),
        .init(id: "linear-zero", space: .sRGBLinear, domain: .requiredFinite, red: 0, green: 0, blue: 0, opacity: 1),
        .init(id: "linear-white", space: .sRGBLinear, domain: .requiredFinite, red: 1, green: 1, blue: 1, opacity: 1),
        .init(
            id: "linear-interior", space: .sRGBLinear, domain: .requiredFinite, red: 0.25, green: 0.5, blue: 0.75,
            opacity: 1),
        .init(
            id: "linear-low", space: .sRGBLinear, domain: .requiredFinite, red: 0.001, green: 0.0030, blue: 0.0032,
            opacity: 1),
        .init(
            id: "linear-negative-low", space: .sRGBLinear, domain: .requiredFinite, red: -0.001, green: -0.0030,
            blue: -0.0032, opacity: 1),
        .init(
            id: "linear-extended", space: .sRGBLinear, domain: .requiredFinite, red: -0.25, green: 0.5, blue: 2,
            opacity: 1),
        .init(
            id: "linear-alpha-zero", space: .sRGBLinear, domain: .requiredFinite, red: 0.25, green: 0.5, blue: 0.75,
            opacity: 0),
        .init(
            id: "linear-alpha-fraction", space: .sRGBLinear, domain: .requiredFinite, red: 0.25, green: 0.5, blue: 0.75,
            opacity: 0.625),
        .init(id: "p3-zero", space: .displayP3, domain: .requiredFinite, red: 0, green: 0, blue: 0, opacity: 1),
        .init(id: "p3-white", space: .displayP3, domain: .requiredFinite, red: 1, green: 1, blue: 1, opacity: 1),
        .init(
            id: "p3-neutral", space: .displayP3, domain: .requiredFinite, red: 0.5, green: 0.5, blue: 0.5, opacity: 1),
        .init(
            id: "p3-interior", space: .displayP3, domain: .requiredFinite, red: 0.1, green: 0.2, blue: 0.3, opacity: 1),
        .init(id: "p3-red", space: .displayP3, domain: .requiredFinite, red: 1, green: 0, blue: 0, opacity: 1),
        .init(id: "p3-green", space: .displayP3, domain: .requiredFinite, red: 0, green: 1, blue: 0, opacity: 1),
        .init(id: "p3-blue", space: .displayP3, domain: .requiredFinite, red: 0, green: 0, blue: 1, opacity: 1),
        .init(id: "p3-alpha-zero", space: .displayP3, domain: .requiredFinite, red: 1, green: 0, blue: 0, opacity: 0),
        .init(
            id: "p3-alpha-fraction", space: .displayP3, domain: .requiredFinite, red: 1, green: 0, blue: 0,
            opacity: 0.625),
        .init(
            id: "p3-extended-input", space: .displayP3, domain: .exploratoryExtendedP3, red: 1.2, green: -0.2,
            blue: 0.5, opacity: 1),
        .init(
            id: "p3-negative-input", space: .displayP3, domain: .exploratoryExtendedP3, red: -0.1, green: -0.2,
            blue: -0.3, opacity: 1),
    ]
}
