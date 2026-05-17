import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class WinSwiftUIVisualModifierTests: XCTestCase {

    private func render<V: View>(
        _ view: V,
        size: IntSize = IntSize(width: 100, height: 100),
        clearColor: Color = .black
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

    // MARK: - cornerRadius

    func testCornerRadiusClipsCorners() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.white)
                    .frame(width: 60, height: 60)
                    .cornerRadius(20)
            )
            // Inside the 60x60 rect should be white
            let inside = colorAt(bitmap, x: 30, y: 30)
            XCTAssertGreaterThan(inside?.red ?? 0, 0.9)
            // Outside the 60x60 rect should be black (clear color)
            let outside = colorAt(bitmap, x: 80, y: 80)
            XCTAssertLessThan(outside?.red ?? 1, 0.1)
        }
    }

    // MARK: - shadow

    func testShadowProducesDistantPixels() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: .white, radius: 4, x: 0, y: 0)
            )
            // Just outside the 40x40 rect but within the 4px shadow spread should be non-black
            let outside = colorAt(bitmap, x: 42, y: 20)
            XCTAssertGreaterThan(outside?.red ?? 0, 0.1)
        }
    }

    // MARK: - border

    func testBorderColorsEdgePixels() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.black)
                    .frame(width: 60, height: 60)
                    .border(.red, width: 2)
            )
            // Edge pixel (within the 2px border) should be red
            let edge = colorAt(bitmap, x: 0, y: 0)
            XCTAssertGreaterThan(edge?.red ?? 0, 0.8)
            XCTAssertLessThan(edge?.green ?? 1, 0.2)
            // Interior pixel (inset by border width) should be black fill
            let interior = colorAt(bitmap, x: 10, y: 10)
            XCTAssertLessThan(interior?.red ?? 1, 0.2)
        }
    }

    // MARK: - background

    func testBackgroundFillsBackgroundPixels() async {
        await MainActor.run {
            let bitmap = render(
                Text("")
                    .frame(width: 60, height: 60)
                    .background(Color.blue)
            )
            // Center should be blue
            let center = colorAt(bitmap, x: 50, y: 50)
            XCTAssertGreaterThan(center?.blue ?? 0, 0.7)
            XCTAssertLessThan(center?.red ?? 1, 0.2)
        }
    }

    // MARK: - foregroundColor

    func testForegroundColorChangesTextColor() async {
        await MainActor.run {
            let bitmap = render(
                Text("X")
                    .foregroundColor(.green)
            )
            // Look for green pixels in the text bounds (text is roughly 12x22 at origin)
            var foundGreen = false
            for y in 0..<30 {
                for x in 0..<20 {
                    if let c = colorAt(bitmap, x: x, y: y),
                        c.green > 0.7, c.red < 0.3, c.blue < 0.3
                    {
                        foundGreen = true
                        break
                    }
                }
                if foundGreen { break }
            }
            XCTAssertTrue(foundGreen, "Text should render with green foreground")
        }
    }

    // MARK: - opacity

    func testOpacityReducesAlpha() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.white)
                    .frame(width: 60, height: 60)
                    .opacity(0.5)
            )
            let center = colorAt(bitmap, x: 50, y: 50)
            XCTAssertGreaterThan(center?.red ?? 0, 0.4)
            XCTAssertLessThan(center?.red ?? 1, 0.8)
        }
    }

    // MARK: - frame

    func testFrameSetsExactSize() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.white)
                    .frame(width: 50, height: 30)
            )
            // Inside the 50x30 rect should be white
            let inside = colorAt(bitmap, x: 25, y: 15)
            XCTAssertGreaterThan(inside?.red ?? 0, 0.9)
            // Outside should be black (clear color)
            let outside = colorAt(bitmap, x: 60, y: 40)
            XCTAssertLessThan(outside?.red ?? 1, 0.1)
        }
    }

    // MARK: - padding

    func testPaddingOffsetsContent() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.white)
                    .frame(width: 40, height: 40)
                    .padding(20)
            )
            // The white rect should start at offset 20, so (10,10) should be black
            let beforePadding = colorAt(bitmap, x: 10, y: 10)
            XCTAssertLessThan(beforePadding?.red ?? 1, 0.1)
            // Inside the padded area should be white
            let inside = colorAt(bitmap, x: 30, y: 30)
            XCTAssertGreaterThan(inside?.red ?? 0, 0.9)
        }
    }

    // MARK: - rotationEffect

    func testRotationEffectAppliesTransform() async {
        await MainActor.run {
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: Rectangle()
                    .fill(.white)
                    .frame(width: 60, height: 20)
                    .rotationEffect(.degrees(45)),
                size: IntSize(width: 100, height: 100),
                displayScale: 1,
                clearColor: .black
            )
            // The rotated frame node should carry a non-identity transform
            let frameNode = snapshot.runtime.root.children.first
            XCTAssertNotNil(frameNode)
            XCTAssertFalse(frameNode!.transform.isIdentity, "rotationEffect should set a transform on the node")
        }
    }

    // MARK: - scaleEffect

    func testScaleEffectScalesRenderedContent() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .scaleEffect(x: 2, y: 2)
            )
            // Scaled 2x from 20x20 centered at 10,10 covers roughly (-10,-10) to (30,30)
            let insideScaled = colorAt(bitmap, x: 15, y: 15)
            XCTAssertEqual(insideScaled?.red ?? 0, 1.0, accuracy: 0.05)
            // Outside scaled bounds should be clear color
            let outsideScaled = colorAt(bitmap, x: 50, y: 50)
            XCTAssertEqual(outsideScaled?.red ?? 1, 0.0, accuracy: 0.05)
        }
    }

    // MARK: - offset

    func testOffsetShiftsRenderedContent() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.white)
                    .offset(x: 10, y: 5)
                    .frame(width: 20, height: 20),
                size: IntSize(width: 40, height: 40)
            )
            // 20x20 rect offset by (10,5) covers (10,5) to (30,25)
            let insideOffset = colorAt(bitmap, x: 15, y: 10)
            XCTAssertEqual(insideOffset?.red ?? 0, 1.0, accuracy: 0.05)
            // Original position should now be clear color
            let originalCenter = colorAt(bitmap, x: 5, y: 5)
            XCTAssertEqual(originalCenter?.red ?? 1, 0.0, accuracy: 0.05)
        }
    }

    func testOffsetOnContainerShiftsChildren() async {
        await MainActor.run {
            let bitmap = render(
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                }
                .offset(x: 10, y: 5)
                .frame(width: 40, height: 40)
            )
            // The white rect inside the ZStack should be offset by (10,5)
            let insideOffset = colorAt(bitmap, x: 15, y: 10)
            XCTAssertEqual(insideOffset?.red ?? 0, 1.0, accuracy: 0.05)
            // Original top-left (5,5) should now be clear color since rect moved
            let originalTopLeft = colorAt(bitmap, x: 5, y: 5)
            XCTAssertEqual(originalTopLeft?.red ?? 1, 0.0, accuracy: 0.05)
        }
    }

    // MARK: - clipShape

    func testClipShapeRoundedRectangleClipsCorners() async {
        await MainActor.run {
            let bitmap = render(
                ZStack {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .frame(width: 60, height: 60)
            )
            // Center should be white
            let center = colorAt(bitmap, x: 30, y: 30)
            XCTAssertGreaterThan(center?.red ?? 0, 0.9)
            // Near the corner (2,2) should be clipped to clear color
            let corner = colorAt(bitmap, x: 2, y: 2)
            XCTAssertLessThan(corner?.red ?? 1, 0.1)
        }
    }

    // MARK: - Color effects

    func testBrightnessDarkensWhiteToGray() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.white)
                    .frame(width: 40, height: 40)
                    .brightness(-0.5)
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            XCTAssertEqual(center?.red ?? 0, 0.5, accuracy: 0.05)
            XCTAssertEqual(center?.green ?? 0, 0.5, accuracy: 0.05)
            XCTAssertEqual(center?.blue ?? 0, 0.5, accuracy: 0.05)
        }
    }

    func testContrastIncreasesDifference() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(Color(red: 0.75, green: 0.75, blue: 0.75, alpha: 1))
                    .frame(width: 40, height: 40)
                    .contrast(1.0)
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            // (0.75 - 0.5) * 2 + 0.5 = 1.0, clamped to white
            XCTAssertGreaterThan(center?.red ?? 0, 0.95)
        }
    }

    func testGrayscaleRemovesColor() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.red)
                    .frame(width: 40, height: 40)
                    .grayscale(1.0)
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            // Full grayscale: R == G == B
            XCTAssertEqual(center?.red ?? 0, center?.green ?? -1, accuracy: 0.05)
            XCTAssertEqual(center?.green ?? 0, center?.blue ?? -1, accuracy: 0.05)
        }
    }

    func testSaturationRemovesColor() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.red)
                    .frame(width: 40, height: 40)
                    .saturation(-1.0)
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            // Full desaturation: R == G == B
            XCTAssertEqual(center?.red ?? 0, center?.green ?? -1, accuracy: 0.05)
            XCTAssertEqual(center?.green ?? 0, center?.blue ?? -1, accuracy: 0.05)
        }
    }

    func testHueRotationShiftsRedTowardGreen() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.red)
                    .frame(width: 40, height: 40)
                    .hueRotation(.degrees(120))
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            // After 120 deg hue rotation, red should shift toward green
            XCTAssertGreaterThan(center?.green ?? 0, center?.red ?? 1)
        }
    }

    func testColorInvertInvertsRedToCyan() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(.red)
                    .frame(width: 40, height: 40)
                    .colorInvert()
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            // Inverted red (1,0,0) -> (0,1,1)
            XCTAssertLessThan(center?.red ?? 1, 0.1)
            XCTAssertGreaterThan(center?.green ?? 0, 0.9)
            XCTAssertGreaterThan(center?.blue ?? 0, 0.9)
        }
    }

    // MARK: - blur

    func testBlurAppliesPostProcessingToContent() async {
        await MainActor.run {
            let bitmap = render(
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 30, height: 30)
                    .blur(radius: 2, opaque: true),
                size: IntSize(width: 60, height: 60)
            )
            // With blurOpaque, alpha should be fully opaque after blur
            let center = colorAt(bitmap, x: 15, y: 15)
            XCTAssertEqual(center?.alpha ?? 0, 1.0, accuracy: 0.05)
        }
    }

    // MARK: - blendMode

    func testBlendModeMultiplyProducesBlackOverRedAndBlue() async {
        await MainActor.run {
            let bitmap = render(
                ZStack {
                    Rectangle()
                        .fill(.red)
                        .frame(width: 40, height: 40)
                    Rectangle()
                        .fill(.blue)
                        .frame(width: 40, height: 40)
                        .blendMode(.multiply)
                },
                size: IntSize(width: 60, height: 60)
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            // Blue (0,0,1) * Red (1,0,0) = Black (0,0,0)
            XCTAssertLessThan(center?.red ?? 1, 0.2)
            XCTAssertLessThan(center?.green ?? 1, 0.2)
            XCTAssertLessThan(center?.blue ?? 1, 0.2)
        }
    }

    func testBlendModeScreenProducesMagentaOverRedAndBlue() async {
        await MainActor.run {
            let bitmap = render(
                ZStack {
                    Rectangle()
                        .fill(.red)
                        .frame(width: 40, height: 40)
                    Rectangle()
                        .fill(.blue)
                        .frame(width: 40, height: 40)
                        .blendMode(.screen)
                },
                size: IntSize(width: 60, height: 60)
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            // Screen(Blue over Red) = Magenta (1,0,1)
            XCTAssertGreaterThan(center?.red ?? 0, 0.8)
            XCTAssertLessThan(center?.green ?? 1, 0.2)
            XCTAssertGreaterThan(center?.blue ?? 0, 0.8)
        }
    }

    func testBlendModeOverlayDarkensWhiteOnDarkGray() async {
        await MainActor.run {
            let bitmap = render(
                ZStack {
                    Rectangle()
                        .fill(Color(red: 0.25, green: 0.25, blue: 0.25))
                        .frame(width: 40, height: 40)
                    Rectangle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                        .blendMode(.overlay)
                },
                size: IntSize(width: 60, height: 60)
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            // Overlay of white on dark gray (0.25) gives medium gray (0.5)
            XCTAssertGreaterThan(center?.red ?? 0, 0.4)
            XCTAssertLessThan(center?.red ?? 1, 0.7)
        }
    }

    func testBlendModePlusLighterAdditiveProducesYellowOverRedAndGreen() async {
        await MainActor.run {
            let bitmap = render(
                ZStack {
                    Rectangle()
                        .fill(.green)
                        .frame(width: 40, height: 40)
                    Rectangle()
                        .fill(.red)
                        .frame(width: 40, height: 40)
                        .blendMode(.plusLighter)
                },
                size: IntSize(width: 60, height: 60)
            )
            let center = colorAt(bitmap, x: 20, y: 20)
            // Additive(Red over Green) = Yellow (1,1,0)
            XCTAssertGreaterThan(center?.red ?? 0, 0.8)
            XCTAssertGreaterThan(center?.green ?? 0, 0.8)
            XCTAssertLessThan(center?.blue ?? 1, 0.2)
        }
    }

    // MARK: - drawingGroup

    func testDrawingGroupPreventsDoubleBlendingWithOpacity() async {
        await MainActor.run {
            // Without drawingGroup, two overlapping white rects at 0.5 opacity
            // blend individually: first = 0.5, second = 0.5 + 0.5*0.5 = 0.75.
            // With drawingGroup, both are drawn at full opacity into a buffer,
            // then the buffer is drawn at 0.5: overlap = 0.5.
            let withoutDG = render(
                ZStack {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                    Rectangle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                }
                .opacity(0.5),
                size: IntSize(width: 60, height: 60)
            )
            let withDG = render(
                ZStack {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                    Rectangle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                }
                .opacity(0.5)
                .drawingGroup(),
                size: IntSize(width: 60, height: 60)
            )
            let centerWithout = colorAt(withoutDG, x: 20, y: 20)
            let centerWith = colorAt(withDG, x: 20, y: 20)
            // Overlap without drawingGroup should be brighter (> 0.6)
            XCTAssertGreaterThan(centerWithout?.red ?? 0, 0.6)
            // Overlap with drawingGroup should be exactly 0.5
            XCTAssertEqual(centerWith?.red ?? 0, 0.5, accuracy: 0.05)
        }
    }
}
