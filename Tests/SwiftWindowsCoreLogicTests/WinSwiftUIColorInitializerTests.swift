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
