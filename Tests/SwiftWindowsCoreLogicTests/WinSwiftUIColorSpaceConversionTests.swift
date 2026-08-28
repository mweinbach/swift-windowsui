import XCTest

@testable import WinSwiftUI

private typealias Conversion = RetainedColorSpaceConversion

// Expected vectors were derived independently from the rational D65 conversion
// matrices and signed transfer functions in W3C CSS Color 4 (2026-08-25),
// section 19. They are math references, not observations of native SwiftUI.
final class WinSwiftUIColorSpaceConversionTests: XCTestCase {
    func testSRGBIsAnIdentityForOrdinaryComponents() async {
        await MainActor.run {
            let inputs: [Conversion.Components] = [
                .init(red: 0, green: 0.25, blue: 0.5),
                .init(red: 0.75, green: 1, blue: 0.1),
            ]
            for input in inputs {
                XCTAssertEqual(
                    Conversion.encodedSRGB(from: .sRGB, red: input.red, green: input.green, blue: input.blue),
                    input)
            }
        }
    }

    func testSRGBKeepsFiniteExtendedComponents() async {
        await MainActor.run {
            let inputs: [Conversion.Components] = [
                .init(red: -0.5, green: 1.25, blue: 2),
                .init(red: Double.greatestFiniteMagnitude, green: -Double.greatestFiniteMagnitude, blue: 1e-200),
            ]
            for input in inputs {
                XCTAssertEqual(
                    Conversion.encodedSRGB(from: .sRGB, red: input.red, green: input.green, blue: input.blue),
                    input)
            }
        }
    }

    func testSRGBAndLinearConversionPreserveSignedZero() async {
        await MainActor.run {
            for space in [Color.RGBColorSpace.sRGB, .sRGBLinear] {
                let result = Conversion.encodedSRGB(from: space, red: -0.0, green: 0.0, blue: -0.0)
                XCTAssertEqual(result.red, 0)
                XCTAssertEqual(result.green, 0)
                XCTAssertEqual(result.blue, 0)
                XCTAssertEqual(result.red.sign, .minus)
                XCTAssertEqual(result.green.sign, .plus)
                XCTAssertEqual(result.blue.sign, .minus)
            }
        }
    }

    func testRawTransferFunctionsPreserveSignedZero() async {
        await MainActor.run {
            XCTAssertEqual(Conversion.decodeSRGB(-0.0).bitPattern, (-0.0 as Double).bitPattern)
            XCTAssertEqual(Conversion.decodeSRGB(0.0).bitPattern, (0.0 as Double).bitPattern)
            XCTAssertEqual(Conversion.encodeSRGB(-0.0).bitPattern, (-0.0 as Double).bitPattern)
            XCTAssertEqual(Conversion.encodeSRGB(0.0).bitPattern, (0.0 as Double).bitPattern)
        }
    }

    func testDecodeUsesLinearBranchAtBothSignedThresholds() async {
        await MainActor.run {
            let threshold: Double = 0.04045
            for magnitude in [threshold.nextDown, threshold] {
                XCTAssertEqual(Conversion.decodeSRGB(magnitude), 0.0031308049535603713, accuracy: 1e-17)
                XCTAssertEqual(Conversion.decodeSRGB(-magnitude), -0.0031308049535603713, accuracy: 1e-17)
            }
        }
    }

    func testDecodeUsesPowerBranchImmediatelyOutsideBothSignedThresholds() async {
        await MainActor.run {
            let threshold: Double = 0.04045
            XCTAssertEqual(Conversion.decodeSRGB(threshold.nextUp), 0.0031308072830676845, accuracy: 1e-16)
            XCTAssertEqual(Conversion.decodeSRGB(-threshold.nextUp), -0.0031308072830676845, accuracy: 1e-16)
        }
    }

    func testEncodeUsesLinearBranchAtBothSignedThresholds() async {
        await MainActor.run {
            let threshold: Double = 0.0031308
            for magnitude in [threshold.nextDown, threshold] {
                XCTAssertEqual(Conversion.encodeSRGB(magnitude), 0.040449936, accuracy: 1e-16)
                XCTAssertEqual(Conversion.encodeSRGB(-magnitude), -0.040449936, accuracy: 1e-16)
            }
        }
    }

    func testEncodeUsesPowerBranchImmediatelyOutsideBothSignedThresholds() async {
        await MainActor.run {
            let threshold: Double = 0.0031308
            XCTAssertEqual(Conversion.encodeSRGB(threshold.nextUp), 0.04044990748269014, accuracy: 1e-15)
            XCTAssertEqual(Conversion.encodeSRGB(-threshold.nextUp), -0.04044990748269014, accuracy: 1e-15)
        }
    }

    func testDecodeMatchesIndependentInteriorAndExtendedValues() async {
        await MainActor.run {
            let cases: [(encoded: Double, linear: Double)] = [
                (0.02, 0.0015479876160990713),
                (0.1, 0.010022825574869039),
                (0.25, 0.05087608817155679),
                (0.5, 0.21404114048223255),
                (0.75, 0.5225215539683921),
                (1, 1),
                (2, 4.953845751592042),
            ]
            for value in cases {
                XCTAssertEqual(Conversion.decodeSRGB(value.encoded), value.linear, accuracy: 1e-13)
                XCTAssertEqual(Conversion.decodeSRGB(-value.encoded), -value.linear, accuracy: 1e-13)
            }
        }
    }

    func testEncodeMatchesIndependentInteriorAndExtendedValues() async {
        await MainActor.run {
            let cases: [(linear: Double, encoded: Double)] = [
                (0.002, 0.02584),
                (0.25, 0.5370987304831942),
                (0.5, 0.7353569830524495),
                (0.75, 0.8808250210902997),
                (1, 1),
                (2, 1.3532560461493863),
            ]
            for value in cases {
                XCTAssertEqual(Conversion.encodeSRGB(value.linear), value.encoded, accuracy: 1e-13)
                XCTAssertEqual(Conversion.encodeSRGB(-value.linear), -value.encoded, accuracy: 1e-13)
            }
        }
    }

    func testTransferFunctionsAreReflectionsForNegativeValues() async {
        await MainActor.run {
            for magnitude in [0.0001, 0.002, 0.0031308, 0.02, 0.04045, 0.1, 0.5, 1, 2] {
                XCTAssertEqual(Conversion.decodeSRGB(-magnitude), -Conversion.decodeSRGB(magnitude))
                XCTAssertEqual(Conversion.encodeSRGB(-magnitude), -Conversion.encodeSRGB(magnitude))
            }
        }
    }

    func testLinearRoundTripsAwayFromRoundedThresholdDiscontinuity() async {
        await MainActor.run {
            // The rounded branch thresholds are deliberately absent here.
            let values = [-2.0, -1, -0.25, -0.01, -0.002, -0.000001, 0, 0.000001, 0.002, 0.01, 0.25, 0.5, 1, 2]
            for value in values {
                XCTAssertEqual(Conversion.decodeSRGB(Conversion.encodeSRGB(value)), value, accuracy: 1e-13)
            }
        }
    }

    func testEncodedRoundTripsAwayFromRoundedThresholdDiscontinuity() async {
        await MainActor.run {
            let values = [-2.0, -1, -0.5, -0.1, -0.02, -0.000001, 0, 0.000001, 0.02, 0.1, 0.5, 1, 2]
            for value in values {
                XCTAssertEqual(Conversion.encodeSRGB(Conversion.decodeSRGB(value)), value, accuracy: 1e-13)
            }
        }
    }

    func testRawTransferFunctionsDoNotApplyCanonicalSanitation() async {
        await MainActor.run {
            XCTAssertTrue(Conversion.decodeSRGB(.nan).isNaN)
            XCTAssertTrue(Conversion.encodeSRGB(.nan).isNaN)
            for value in [Double.infinity, -Double.infinity] {
                XCTAssertEqual(Conversion.decodeSRGB(value), value)
                XCTAssertEqual(Conversion.encodeSRGB(value), value)
            }
        }
    }

    func testLinearSpaceUsesSignedExtendedTransfer() async {
        await MainActor.run {
            assertConvertedComponents(
                Conversion.encodedSRGB(from: .sRGBLinear, red: -0.25, green: 0.5, blue: 2),
                red: -0.5370987304831942, green: 0.7353569830524495, blue: 1.3532560461493863)
        }
    }

    func testDisplayP3PrimariesMatchIndependentVectors() async {
        await MainActor.run {
            assertConvertedComponents(
                Conversion.encodedSRGB(from: .displayP3, red: 1, green: 0, blue: 0),
                red: 1.0930663624351615, green: -0.22674197356975412, blue: -0.15013458093711954)
            assertConvertedComponents(
                Conversion.encodedSRGB(from: .displayP3, red: 0, green: 1, blue: 0),
                red: -0.5116049825853448, green: 1.0182656579378024, blue: -0.31067462129058276)
            assertConvertedComponents(
                Conversion.encodedSRGB(from: .displayP3, red: 0, green: 0, blue: 1),
                red: 0, green: 0, blue: 1.0420216193529392)
        }
    }

    func testDisplayP3InteriorAndOrangeMatchIndependentVectors() async {
        await MainActor.run {
            assertConvertedComponents(
                Conversion.encodedSRGB(from: .displayP3, red: 0.1, green: 0.2, blue: 0.3),
                red: 0.0593560814318018, green: 0.20308940658327412, blue: 0.30873040976082844)
            assertConvertedComponents(
                Conversion.encodedSRGB(from: .displayP3, red: 1, green: 0.5, blue: 0),
                red: 1.074044179460937, green: 0.46253291134998725, blue: -0.21049331292599333)
        }
    }

    func testDisplayP3ExtendedAndNegativeInputsMatchIndependentVectors() async {
        await MainActor.run {
            assertConvertedComponents(
                Conversion.encodedSRGB(from: .displayP3, red: 1.2, green: -0.2, blue: 0.5),
                red: 1.3129872225744519, green: -0.3462969102639354, blue: 0.49329992462243594)
            assertConvertedComponents(
                Conversion.encodedSRGB(from: .displayP3, red: -0.1, green: -0.2, blue: -0.3),
                red: -0.0593560814318018, green: -0.20308940658327412, blue: -0.30873040976082844)
        }
    }

    func testDisplayP3PreservesNeutralComponentsAwayFromTransferDiscontinuity() async {
        await MainActor.run {
            for value in [-2.0, -0.5, -0.02, -0.001, 0, 0.001, 0.02, 0.1, 0.5, 1, 1.25, 2] {
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .displayP3, red: value, green: value, blue: value),
                    red: value, green: value, blue: value)
            }
        }
    }

    func testDisplayP3DoesNotClampBeforeOrAfterTheMatrix() async {
        await MainActor.run {
            let extended = Conversion.encodedSRGB(from: .displayP3, red: 1.2, green: -0.2, blue: 0.5)
            let clippedInput = Conversion.encodedSRGB(from: .displayP3, red: 1, green: 0, blue: 0.5)
            XCTAssertGreaterThan(extended.red, 1)
            XCTAssertLessThan(extended.green, 0)
            XCTAssertGreaterThan(abs(extended.red - clippedInput.red), 0.1)
            XCTAssertGreaterThan(abs(extended.green - clippedInput.green), 0.1)
            XCTAssertEqual(Conversion.storedFloat(extended.red), Float(1.312987208366394))
            XCTAssertEqual(Conversion.storedFloat(extended.green), Float(-0.34629690647125244))
            XCTAssertEqual(Conversion.storedFloat(extended.blue), Float(0.4932999312877655))
        }
    }

    func testSRGBInvalidInputsAreReplacedIndividually() async {
        await MainActor.run {
            for invalid in [Double.nan, Double.infinity, -Double.infinity] {
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .sRGB, red: invalid, green: 0.25, blue: 0.75),
                    red: 0, green: 0.25, blue: 0.75, accuracy: 0)
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .sRGB, red: 0.125, green: invalid, blue: 2),
                    red: 0.125, green: 0, blue: 2, accuracy: 0)
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .sRGB, red: -1, green: 0.5, blue: invalid),
                    red: -1, green: 0.5, blue: 0, accuracy: 0)
            }
        }
    }

    func testLinearInvalidInputsAreReplacedIndividually() async {
        await MainActor.run {
            for invalid in [Double.nan, Double.infinity, -Double.infinity] {
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .sRGBLinear, red: invalid, green: 0.25, blue: 0.5),
                    red: 0, green: 0.5370987304831942, blue: 0.7353569830524495)
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .sRGBLinear, red: -0.25, green: invalid, blue: 2),
                    red: -0.5370987304831942, green: 0, blue: 1.3532560461493863)
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .sRGBLinear, red: 0.5, green: -0.25, blue: invalid),
                    red: 0.7353569830524495, green: -0.5370987304831942, blue: 0)
            }
        }
    }

    func testDisplayP3InvalidInputsAreReplacedBeforeCoupledConversion() async {
        await MainActor.run {
            for invalid in [Double.nan, Double.infinity, -Double.infinity] {
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .displayP3, red: invalid, green: 1, blue: 0),
                    red: -0.5116049825853448, green: 1.0182656579378024, blue: -0.31067462129058276)
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .displayP3, red: 1, green: invalid, blue: 0),
                    red: 1.0930663624351615, green: -0.22674197356975412, blue: -0.15013458093711954)
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .displayP3, red: 1, green: 0.5, blue: invalid),
                    red: 1.074044179460937, green: 0.46253291134998725, blue: -0.21049331292599333)
            }
        }
    }

    func testAllInvalidInputsResolveToZeroInEverySpace() async {
        await MainActor.run {
            for space in [Color.RGBColorSpace.sRGB, .sRGBLinear, .displayP3] {
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: space, red: .nan, green: .infinity, blue: -.infinity),
                    red: 0, green: 0, blue: 0, accuracy: 0)
            }
        }
    }

    func testDisplayP3DecodeOverflowInvalidatesAllRGBComponents() async {
        await MainActor.run {
            for extreme in [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .displayP3, red: extreme, green: 0.25, blue: 0.5),
                    red: 0, green: 0, blue: 0, accuracy: 0)
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .displayP3, red: 0.25, green: extreme, blue: 0.5),
                    red: 0, green: 0, blue: 0, accuracy: 0)
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .displayP3, red: 0.25, green: 0.5, blue: extreme),
                    red: 0, green: 0, blue: 0, accuracy: 0)
            }
        }
    }

    func testDisplayP3MatrixOverflowInvalidatesAllRGBComponents() async {
        await MainActor.run {
            // Decoding stays finite, but the red matrix product overflows.
            for extreme in [2.7e128, -2.7e128] {
                XCTAssertTrue(Conversion.decodeSRGB(extreme).isFinite)
                assertConvertedComponents(
                    Conversion.encodedSRGB(from: .displayP3, red: extreme, green: 0, blue: 0.5),
                    red: 0, green: 0, blue: 0, accuracy: 0)
            }

            // Here each red-row product is finite; adding them overflows.
            XCTAssertTrue(Conversion.decodeSRGB(2.6e128).isFinite)
            assertConvertedComponents(
                Conversion.encodedSRGB(from: .displayP3, red: 2.6e128, green: -2.6e128, blue: 0.5),
                red: 0, green: 0, blue: 0, accuracy: 0)
        }
    }

    func testStoredFloatPreservesExtendedRepresentableValues() async {
        await MainActor.run {
            for value in [-2.0, -0.5, 0, 0.25, 0.5, 1, 1.25, 2] {
                XCTAssertEqual(Conversion.storedFloat(value), Float(value))
            }
        }
    }

    func testStoredFloatPreservesSignedZeroAndSubnormalValues() async {
        await MainActor.run {
            XCTAssertEqual(Conversion.storedFloat(-0.0).bitPattern, (-0.0 as Float).bitPattern)
            XCTAssertEqual(Conversion.storedFloat(0.0).bitPattern, (0.0 as Float).bitPattern)
            for value in [Float.leastNonzeroMagnitude, Float.leastNormalMagnitude] {
                XCTAssertEqual(Conversion.storedFloat(Double(value)), value)
                XCTAssertEqual(Conversion.storedFloat(-Double(value)), -value)
            }
        }
    }

    func testStoredFloatMapsNonfiniteValuesToPositiveZero() async {
        await MainActor.run {
            for value in [Double.nan, Double.infinity, -Double.infinity] {
                XCTAssertEqual(Conversion.storedFloat(value).bitPattern, (0.0 as Float).bitPattern)
            }
        }
    }

    func testStoredFloatSaturatesFiniteOverflowToMatchingSign() async {
        await MainActor.run {
            let maximum = Double(Float.greatestFiniteMagnitude)
            for magnitude in [maximum.nextUp, maximum * 2, Double.greatestFiniteMagnitude] {
                XCTAssertTrue(magnitude.isFinite)
                XCTAssertEqual(Conversion.storedFloat(magnitude), Float.greatestFiniteMagnitude)
                XCTAssertEqual(Conversion.storedFloat(-magnitude), -Float.greatestFiniteMagnitude)
            }
        }
    }

    func testStoredFloatRetainsNearBoundaryPrecision() async {
        await MainActor.run {
            let maximum = Float.greatestFiniteMagnitude
            let preceding = maximum.nextDown
            XCTAssertEqual(Conversion.storedFloat(Double(maximum)), maximum)
            XCTAssertEqual(Conversion.storedFloat(-Double(maximum)), -maximum)
            XCTAssertEqual(Conversion.storedFloat(Double(preceding)), preceding)
            XCTAssertEqual(Conversion.storedFloat(-Double(preceding)), -preceding)
            XCTAssertEqual(Conversion.storedFloat(Double(maximum).nextDown), maximum)
            XCTAssertEqual(Conversion.storedFloat(-Double(maximum).nextDown), -maximum)
        }
    }

    func testFiniteLinearInputIsConvertedBeforeFloatNarrowing() async {
        await MainActor.run {
            let result = Conversion.encodedSRGB(from: .sRGBLinear, red: 1e60, green: -1e60, blue: 0.5)
            assertConvertedComponents(
                result, red: 1.0550000000000025e25, green: -1.0550000000000025e25,
                blue: 0.7353569830524495, accuracy: 1e12)
            XCTAssertEqual(result.blue, 0.7353569830524495, accuracy: 1e-12)
            XCTAssertEqual(Conversion.storedFloat(result.red), Float(1.0549999612874718e25))
            XCTAssertEqual(Conversion.storedFloat(result.green), Float(-1.0549999612874718e25))
        }
    }

    func testDisplayP3KeepsLargeFiniteIntermediateMathInDouble() async {
        await MainActor.run {
            // Linear intermediates exceed Float's range, but encoded RGB fits.
            let result = Conversion.encodedSRGB(from: .displayP3, red: 1e20, green: 0, blue: 0)
            assertConvertedComponents(
                result, red: 1.0882145615499166e20, green: -2.6705400338365334e19,
                blue: -1.944403610778385e19, accuracy: 1e8)
            XCTAssertEqual(Conversion.storedFloat(result.red), Float(1.0882145416247876e20))
            XCTAssertEqual(Conversion.storedFloat(result.green), Float(-2.6705400210307154e19))
            XCTAssertEqual(Conversion.storedFloat(result.blue), Float(-1.9444036304474472e19))
        }
    }
}

private func assertConvertedComponents(
    _ actual: Conversion.Components,
    red: Double,
    green: Double,
    blue: Double,
    accuracy: Double = 1e-12,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(actual.red.isFinite, file: file, line: line)
    XCTAssertTrue(actual.green.isFinite, file: file, line: line)
    XCTAssertTrue(actual.blue.isFinite, file: file, line: line)
    XCTAssertEqual(actual.red, red, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.green, green, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.blue, blue, accuracy: accuracy, file: file, line: line)
}
