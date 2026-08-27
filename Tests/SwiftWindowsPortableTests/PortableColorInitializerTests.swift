import SwiftWindowsCore
import XCTest

final class PortableColorInitializerTests: XCTestCase {
    func testRGBLiteralsKeepDefaultAlphaWithoutWinSwiftUI() {
        let integer = Color(red: 1, green: 0, blue: 0)
        let fractional = Color(red: 0.25, green: 0.5, blue: 0.75)
        let mixed = Color(red: 1, green: 0.5, blue: 0)
        let contextual: Color = .init(red: 0, green: 0, blue: 1)

        XCTAssertEqual(integer, Color(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(fractional, Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        XCTAssertEqual(mixed, Color(red: 1, green: 0.5, blue: 0, alpha: 1))
        XCTAssertEqual(contextual, Color(red: 0, green: 0, blue: 1, alpha: 1))
    }

    func testRGBFloatVariablesKeepDefaultAlphaWithoutWinSwiftUI() {
        let red: Float = 0.25
        let green: Float = 0.5
        let blue: Float = 0.75
        let color = Color(red: red, green: green, blue: blue)
        let mixed = Color(red: red, green: 1, blue: 0.5)

        XCTAssertEqual(color.red, red)
        XCTAssertEqual(color.green, green)
        XCTAssertEqual(color.blue, blue)
        XCTAssertEqual(color.alpha, 1)
        XCTAssertEqual(mixed, Color(red: 0.25, green: 1, blue: 0.5, alpha: 1))
    }

    func testRGBAlphaLabelAndInitializerFunctionRemainAvailable() {
        let initializer: (Float, Float, Float, Float) -> Color = Color.init(red:green:blue:alpha:)
        let alpha: Float = 0.625
        let color = Color(red: 0.25, green: 0.5, blue: 0.75, alpha: alpha)

        XCTAssertEqual(initializer(0.25, 0.5, 0.75, alpha), color)
        XCTAssertEqual(color.red, 0.25)
        XCTAssertEqual(color.green, 0.5)
        XCTAssertEqual(color.blue, 0.75)
        XCTAssertEqual(color.alpha, alpha)
    }

    func testRGBInitializerKeepsUnclampedStoredComponents() {
        let color = Color(red: 1.25, green: -0.5, blue: 0.75, alpha: 1.5)

        XCTAssertEqual(color.red, 1.25)
        XCTAssertEqual(color.green, -0.5)
        XCTAssertEqual(color.blue, 0.75)
        XCTAssertEqual(color.alpha, 1.5)
    }
}
