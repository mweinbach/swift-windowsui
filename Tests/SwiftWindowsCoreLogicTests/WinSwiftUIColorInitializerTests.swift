import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSwiftUI
import XCTest

final class WinSwiftUIColorInitializerTests: XCTestCase {
    func testRGBInitializerAcceptsIntegerLiterals() async {
        await MainActor.run {
            let color = Color(red: 1, green: 0, blue: 0)
            let qualified = WinSwiftUI.Color(red: 0, green: 1, blue: 0)
            let contextual: Color = .init(red: 0, green: 0, blue: 1)

            assertColorComponents(color, red: 1, green: 0, blue: 0, alpha: 1)
            assertColorComponents(qualified, red: 0, green: 1, blue: 0, alpha: 1)
            assertColorComponents(contextual, red: 0, green: 0, blue: 1, alpha: 1)
        }
    }

    func testRGBInitializerAcceptsFractionalLiterals() async {
        await MainActor.run {
            let color = Color(red: 0.25, green: 0.5, blue: 0.75)

            assertColorComponents(color, red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        }
    }

    func testRGBInitializerAcceptsMixedLiterals() async {
        await MainActor.run {
            assertColorComponents(Color(red: 1, green: 0.5, blue: 0), red: 1, green: 0.5, blue: 0, alpha: 1)
            assertColorComponents(Color(red: 0.25, green: 1, blue: 0), red: 0.25, green: 1, blue: 0, alpha: 1)
            assertColorComponents(Color(red: 0, green: 1, blue: 0.75), red: 0, green: 1, blue: 0.75, alpha: 1)
        }
    }

    func testRGBInitializerAcceptsDoubleVariables() async {
        await MainActor.run {
            let red: Double = 0.25
            let green: Double = 0.5
            let blue: Double = 0.75
            let opacity: Double = 0.625

            assertColorComponents(
                Color(red: red, green: green, blue: blue),
                red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
            assertColorComponents(
                Color(red: red, green: green, blue: blue, opacity: opacity),
                red: 0.25, green: 0.5, blue: 0.75, alpha: 0.625)
            assertColorComponents(
                Color(red: red, green: 1, blue: 0.5),
                red: 0.25, green: 1, blue: 0.5, alpha: 1)
        }
    }

    func testRGBInitializerAcceptsFloatVariables() async {
        await MainActor.run {
            let red: Float = 0.25
            let green: Float = 0.5
            let blue: Float = 0.75
            let alpha: Float = 0.625

            assertColorComponents(
                Color(red: red, green: green, blue: blue),
                red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
            assertColorComponents(
                Color(red: red, green: green, blue: blue, alpha: alpha),
                red: 0.25, green: 0.5, blue: 0.75, alpha: 0.625)
            assertColorComponents(
                Color(red: red, green: 1, blue: 0.5),
                red: 0.25, green: 1, blue: 0.5, alpha: 1)
        }
    }

    func testRGBInitializerPreservesAlphaAndOpacityLabels() async {
        await MainActor.run {
            let alphaInitializer: (Float, Float, Float, Float) -> Color =
                Color.init(red:green:blue:alpha:)
            let opacityInitializer: (Double, Double, Double, Double) -> Color =
                Color.init(red:green:blue:opacity:)

            assertColorComponents(
                Color(red: 1, green: 0, blue: 0, alpha: 0.25),
                red: 1, green: 0, blue: 0, alpha: 0.25)
            assertColorComponents(
                Color(red: 1, green: 0, blue: 0, opacity: 0.25),
                red: 1, green: 0, blue: 0, alpha: 0.25)
            XCTAssertEqual(alphaInitializer(0.25, 0.5, 0.75, 0.625), opacityInitializer(0.25, 0.5, 0.75, 0.625))
        }
    }

    func testRGBColorSpaceInitializerAcceptsLiteralsAndDoubleVariables() async {
        await MainActor.run {
            assertColorComponents(
                Color(.sRGB, red: 1, green: 0, blue: 0),
                red: 1, green: 0, blue: 0, alpha: 1)
            assertColorComponents(
                Color(.sRGB, red: 0.25, green: 1, blue: 0.5, opacity: 0.625),
                red: 0.25, green: 1, blue: 0.5, alpha: 0.625)

            let red: Double = 0.25
            let green: Double = 0.5
            let blue: Double = 0.75
            for colorSpace in [Color.RGBColorSpace.sRGB, .sRGBLinear, .displayP3] {
                let opaque = Color(colorSpace, red: red, green: green, blue: blue)
                let translucent = Color(colorSpace, red: red, green: green, blue: blue, opacity: 0.625)
                XCTAssertEqual(opaque, Color(colorSpace, red: red, green: green, blue: blue, opacity: 1))
                XCTAssertEqual(opaque.alpha, 1)
                XCTAssertEqual(translucent.red, opaque.red)
                XCTAssertEqual(translucent.green, opaque.green)
                XCTAssertEqual(translucent.blue, opaque.blue)
                XCTAssertEqual(translucent.alpha, 0.625)
            }

            let linear = Color(.sRGBLinear, red: 0.25, green: 0.5, blue: 0.75)
            XCTAssertEqual(linear.red, 0.5370987, accuracy: 0.000001)
            XCTAssertEqual(linear.green, 0.735357, accuracy: 0.000001)
            XCTAssertEqual(linear.blue, 0.880825, accuracy: 0.000001)
        }
    }

    func testRGBInitializersKeepExtendedComponents() async {
        await MainActor.run {
            assertColorComponents(
                Color(red: 1.25, green: -0.5, blue: 0.75, opacity: 1.5),
                red: 1.25, green: -0.5, blue: 0.75, alpha: 1.5)
            assertColorComponents(
                Color(red: 1.25, green: -0.5, blue: 0.75, alpha: 1.5),
                red: 1.25, green: -0.5, blue: 0.75, alpha: 1.5)
        }
    }

    func testCanonicalInitializerFunctionKeepsColorSpaceAndOpacityArguments() async {
        await MainActor.run {
            let initializer: (Color.RGBColorSpace, Double, Double, Double, Double) -> Color =
                Color.init(_:red:green:blue:opacity:)
            let value = initializer(.sRGBLinear, -0.25, 0.5, 2, 0.625)
            XCTAssertEqual(value.red, -0.53709873, accuracy: 0.000001)
            XCTAssertEqual(value.green, 0.73535698, accuracy: 0.000001)
            XCTAssertEqual(value.blue, 1.35325605, accuracy: 0.000001)
            XCTAssertEqual(value.alpha, 0.625)
        }
    }

    func testDisplayP3StoresConvertedExtendedComponentsWithoutPremultiplication() async {
        await MainActor.run {
            for opacity in [0.0, 0.25, 0.625, 1.0, 1.5] {
                let color = Color(.displayP3, red: 1, green: 0, blue: 0, opacity: opacity)
                XCTAssertEqual(color.red, 1.09306636, accuracy: 0.000001)
                XCTAssertEqual(color.green, -0.22674197, accuracy: 0.000001)
                XCTAssertEqual(color.blue, -0.15013458, accuracy: 0.000001)
                XCTAssertEqual(color.alpha, Float(opacity))
            }
        }
    }

    func testCanonicalSRGBKeepsFiniteComponentsAndNormalOpacity() async {
        await MainActor.run {
            for opacity in [0.0, 0.25, 0.5, 1.0] {
                assertColorComponents(
                    Color(.sRGB, red: 1.25, green: -0.5, blue: 0.75, opacity: opacity),
                    red: 1.25, green: -0.5, blue: 0.75, alpha: Float(opacity))
            }
        }
    }

    func testCanonicalInvalidRGBPolicyDoesNotChangeOtherInputs() async {
        await MainActor.run {
            for colorSpace in [Color.RGBColorSpace.sRGB, .sRGBLinear, .displayP3] {
                for invalid in [Double.nan, .infinity, -.infinity] {
                    let actual = Color(colorSpace, red: invalid, green: 0.25, blue: 0.5, opacity: 0.625)
                    let expected = Color(colorSpace, red: 0, green: 0.25, blue: 0.5, opacity: 0.625)
                    XCTAssertEqual(actual, expected)
                    XCTAssertTrue(actual.red.isFinite && actual.green.isFinite && actual.blue.isFinite)
                    XCTAssertEqual(actual.alpha, 0.625)
                }
            }
        }
    }

    func testCanonicalFloatOverflowPolicySaturatesAfterConversion() async {
        await MainActor.run {
            let limit = Float.greatestFiniteMagnitude
            let srgb = Color(
                .sRGB, red: Double.greatestFiniteMagnitude, green: -Double.greatestFiniteMagnitude, blue: 2)
            assertColorComponents(srgb, red: limit, green: -limit, blue: 2, alpha: 1)

            let linear = Color(.sRGBLinear, red: 1e100, green: -1e100, blue: 0.25)
            XCTAssertEqual(linear.red, limit)
            XCTAssertEqual(linear.green, -limit)
            XCTAssertEqual(linear.blue, 0.53709873, accuracy: 0.000001)

            let p3 = Color(.displayP3, red: Double.greatestFiniteMagnitude, green: 0.25, blue: 0.5, opacity: 0.625)
            assertColorComponents(p3, red: 0, green: 0, blue: 0, alpha: 0.625)
        }
    }

    func testCanonicalRGBConversionLeavesExistingAlphaPolicyUnchanged() async {
        await MainActor.run {
            for colorSpace in [Color.RGBColorSpace.sRGB, .sRGBLinear, .displayP3] {
                let opaque = Color(colorSpace, red: 0.1, green: 0.2, blue: 0.3)
                for opacity in [Double.nan, .infinity, -.infinity, -0.25, 1.5] {
                    let color = Color(colorSpace, red: 0.1, green: 0.2, blue: 0.3, opacity: opacity)
                    XCTAssertEqual(color.red, opaque.red)
                    XCTAssertEqual(color.green, opaque.green)
                    XCTAssertEqual(color.blue, opaque.blue)
                    if opacity.isNaN {
                        XCTAssertTrue(color.alpha.isNaN)
                    } else {
                        XCTAssertEqual(color.alpha, Float(opacity))
                    }
                }
            }
        }
    }

    func testLegacyOverloadsRetainTheirRawNonfiniteAndExtendedStorage() async {
        await MainActor.run {
            let legacy: (Float, Float, Float, Float) -> Color = Color.init(red:green:blue:alpha:)
            let unqualified: (Double, Double, Double, Double) -> Color = Color.init(red:green:blue:opacity:)
            for color in [legacy(.infinity, -.infinity, .nan, 1.5), unqualified(.infinity, -.infinity, .nan, 1.5)] {
                XCTAssertEqual(color.red, .infinity)
                XCTAssertEqual(color.green, -.infinity)
                XCTAssertTrue(color.blue.isNaN)
                XCTAssertEqual(color.alpha, 1.5)
            }
        }
    }

    func testWhiteInitializersKeepTheirExistingBoundedBehaviorOutsideThisRGBSlice() async {
        await MainActor.run {
            assertColorComponents(Color(.sRGBLinear, white: -1, opacity: 1.5), red: 0, green: 0, blue: 0, alpha: 1)
            assertColorComponents(Color(.displayP3, white: 2, opacity: -0.25), red: 1, green: 1, blue: 1, alpha: 0)
            assertColorComponents(Color(white: 2, opacity: -0.25), red: 1, green: 1, blue: 1, alpha: 0)
        }
    }

    func testExtendedComponentStorageIsSeparateFromTheExistingSceneAndBGRA8Clipping() async {
        await MainActor.run {
            let color = Color(.displayP3, red: 1, green: 0, blue: 0)
            // Sample the full interior, not the quad's antialiased edge.
            let quad = QuadPrimitive(
                x: -2, y: -2, width: 5, height: 5,
                startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
                endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha)
            XCTAssertGreaterThan(quad.startR, 1)
            XCTAssertLessThan(quad.startG, 0)
            var scene = GPUIScene(clearColor: .clear)
            scene.addQuad(quad)
            XCTAssertEqual(scene.layers[0].quads[0].startR, 1)
            XCTAssertEqual(scene.layers[0].quads[0].startG, 0)
            XCTAssertEqual(scene.layers[0].quads[0].startB, 0)
            XCTAssertEqual(
                Array(GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 1, height: 1)).pixels),
                [0, 0, 255, 255])
            XCTAssertGreaterThan(color.red, 1, "Output clipping must not mutate the retained color value")
        }
    }

    func testInGamutP3AndItsExplicitSRGBEquivalentReachTheSameCPUBytes() async {
        await MainActor.run {
            func pixel(_ color: Color) -> [UInt8] {
                var scene = GPUIScene(clearColor: .clear)
                scene.addQuad(
                    QuadPrimitive(
                        x: -2, y: -2, width: 5, height: 5,
                        startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
                        endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha))
                return Array(GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 1, height: 1)).pixels)
            }
            let p3 = Color(.displayP3, red: 0.1, green: 0.2, blue: 0.3)
            let srgb = Color(.sRGB, red: 0.0593560814318018, green: 0.20308940658327412, blue: 0.30873040976082844)
            XCTAssertEqual(pixel(p3), pixel(srgb))
            XCTAssertEqual(pixel(p3), [79, 52, 15, 255])
        }
    }
}

private func assertColorComponents(
    _ color: Color,
    red: Float,
    green: Float,
    blue: Float,
    alpha: Float,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(color.red, red, file: file, line: line)
    XCTAssertEqual(color.green, green, file: file, line: line)
    XCTAssertEqual(color.blue, blue, file: file, line: line)
    XCTAssertEqual(color.alpha, alpha, file: file, line: line)
}
