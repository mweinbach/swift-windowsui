import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class WinSwiftUIVisualControlTests: XCTestCase {

    // MARK: - Helpers

    private func render<V: View>(
        _ view: V,
        size: IntSize = IntSize(width: 200, height: 100),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0)
    ) -> BitmapSurface {
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: size,
            displayScale: 1,
            clearColor: clearColor
        )
        return GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
    }

    private func colorAt(_ bitmap: BitmapSurface, x: Int, y: Int) -> Color? {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else { return nil }
        let offset = (y * Int(bitmap.width) + x) * 4
        guard offset + 3 < bitmap.pixels.count else { return nil }
        return Color(
            red: Float(bitmap.pixels[offset + 2]) / 255,
            green: Float(bitmap.pixels[offset + 1]) / 255,
            blue: Float(bitmap.pixels[offset]) / 255,
            alpha: Float(bitmap.pixels[offset + 3]) / 255
        )
    }

    private func isNonTransparent(_ color: Color?) -> Bool {
        guard let color else { return false }
        return color.alpha > 0.05
    }

    // MARK: - Button

    func testButtonRendersTextPixels() async {
        await MainActor.run {
            let bitmap = render(Button("Tap Me") {})
            // Search for non-transparent pixels in the center area where text should be
            var foundText = false
            for y in 20..<80 {
                for x in 20..<180 {
                    if isNonTransparent(colorAt(bitmap, x: x, y: y)) {
                        foundText = true
                        break
                    }
                }
                if foundText { break }
            }
            XCTAssertTrue(foundText, "Button should render non-transparent pixels")
        }
    }

    // MARK: - Toggle

    func testToggleRendersNonTransparentPixels() async {
        await MainActor.run {
            let bitmap = render(Toggle("Enable", isOn: .constant(true)))
            var foundPixels = false
            for y in 10..<90 {
                for x in 10..<190 {
                    if isNonTransparent(colorAt(bitmap, x: x, y: y)) {
                        foundPixels = true
                        break
                    }
                }
                if foundPixels { break }
            }
            XCTAssertTrue(foundPixels, "Toggle should render non-transparent pixels")
        }
    }

    // MARK: - Slider

    func testSliderRendersTrackPixels() async {
        await MainActor.run {
            let bitmap = render(Slider(value: .constant(0.5)))
            var foundPixels = false
            for y in 10..<90 {
                for x in 10..<190 {
                    if isNonTransparent(colorAt(bitmap, x: x, y: y)) {
                        foundPixels = true
                        break
                    }
                }
                if foundPixels { break }
            }
            XCTAssertTrue(foundPixels, "Slider should render non-transparent pixels")
        }
    }

    // MARK: - ProgressView

    func testLinearProgressViewRendersBarPixels() async {
        await MainActor.run {
            let bitmap = render(ProgressView("Loading", value: 0.5, total: 1.0))
            var foundPixels = false
            for y in 10..<90 {
                for x in 10..<190 {
                    if isNonTransparent(colorAt(bitmap, x: x, y: y)) {
                        foundPixels = true
                        break
                    }
                }
                if foundPixels { break }
            }
            XCTAssertTrue(foundPixels, "ProgressView should render non-transparent pixels")
        }
    }

    // MARK: - TextField

    func testTextFieldRendersBackgroundPixels() async {
        await MainActor.run {
            let bitmap = render(TextField("Name", text: .constant("Alice")))
            var foundPixels = false
            for y in 10..<90 {
                for x in 10..<190 {
                    if isNonTransparent(colorAt(bitmap, x: x, y: y)) {
                        foundPixels = true
                        break
                    }
                }
                if foundPixels { break }
            }
            XCTAssertTrue(foundPixels, "TextField should render non-transparent pixels")
        }
    }

    // MARK: - TextEditor

    func testTextEditorRendersBackgroundPixels() async {
        await MainActor.run {
            let bitmap = render(TextEditor(text: .constant("Hello\nWorld")))
            var foundPixels = false
            for y in 10..<90 {
                for x in 10..<190 {
                    if isNonTransparent(colorAt(bitmap, x: x, y: y)) {
                        foundPixels = true
                        break
                    }
                }
                if foundPixels { break }
            }
            XCTAssertTrue(foundPixels, "TextEditor should render non-transparent pixels")
        }
    }

    // MARK: - DatePicker

    func testDatePickerRendersNonTransparentPixels() async {
        await MainActor.run {
            let bitmap = render(DatePicker("Date", selection: .constant(Date())))
            var foundPixels = false
            for y in 10..<90 {
                for x in 10..<190 {
                    if isNonTransparent(colorAt(bitmap, x: x, y: y)) {
                        foundPixels = true
                        break
                    }
                }
                if foundPixels { break }
            }
            XCTAssertTrue(foundPixels, "DatePicker should render non-transparent pixels")
        }
    }

    // MARK: - ColorPicker

    func testColorPickerRendersSwatchPixels() async {
        await MainActor.run {
            let bitmap = render(ColorPicker("Color", selection: .constant(.red)))
            var foundPixels = false
            for y in 10..<90 {
                for x in 10..<190 {
                    if isNonTransparent(colorAt(bitmap, x: x, y: y)) {
                        foundPixels = true
                        break
                    }
                }
                if foundPixels { break }
            }
            XCTAssertTrue(foundPixels, "ColorPicker should render non-transparent pixels")
        }
    }

    // MARK: - Stepper

    func testStepperRendersButtonPixels() async {
        await MainActor.run {
            let bitmap = render(Stepper("Count", onIncrement: {}, onDecrement: {}))
            var foundPixels = false
            for y in 10..<90 {
                for x in 10..<190 {
                    if isNonTransparent(colorAt(bitmap, x: x, y: y)) {
                        foundPixels = true
                        break
                    }
                }
                if foundPixels { break }
            }
            XCTAssertTrue(foundPixels, "Stepper should render non-transparent pixels")
        }
    }
}
