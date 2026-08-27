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
            // Edge pixel (within the 2px border) should match semantic red.
            let edge = colorAt(bitmap, x: 0, y: 0)
            XCTAssertEqual(edge?.red ?? -1, Color.red.red, accuracy: 0.01)
            XCTAssertEqual(edge?.green ?? -1, Color.red.green, accuracy: 0.01)
            XCTAssertEqual(edge?.blue ?? -1, Color.red.blue, accuracy: 0.01)
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
                        c.green > 0.7, c.red < 0.3, c.blue < 0.4
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
            // The 20x20 ZStack is centered at (10,10) in its 40x40 frame.
            // Its offset moves the child to (20,15), ending at (40,35).
            let insideOffset = colorAt(bitmap, x: 25, y: 20)
            XCTAssertEqual(insideOffset?.red ?? 0, 1.0, accuracy: 0.05)
            // Each vacated strip independently verifies that the container's
            // horizontal and vertical offsets reach the descendant.
            let originalLeftStrip = colorAt(bitmap, x: 15, y: 20)
            XCTAssertEqual(originalLeftStrip?.red ?? 1, 0.0, accuracy: 0.05)
            let originalTopStrip = colorAt(bitmap, x: 25, y: 12)
            XCTAssertEqual(originalTopStrip?.red ?? 1, 0.0, accuracy: 0.05)
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
                    .contrast(2.0)
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
                    .saturation(0.0)
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
            XCTAssertEqual(center?.red ?? -1, 1 - Color.red.red, accuracy: 0.01)
            XCTAssertEqual(center?.green ?? -1, 1 - Color.red.green, accuracy: 0.01)
            XCTAssertEqual(center?.blue ?? -1, 1 - Color.red.blue, accuracy: 0.01)
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

    // `.blendMode` is carried onto the primitive and interpreted by
    // nobody: the HLSL declares `float blendMode;` and never reads it, and
    // the blend state is a fixed `ONE / INV_SRC_ALPHA`. These tests used to
    // assert the separable results the CPU rasterizer alone produced, which
    // meant they passed on a picture the user never saw.
    // `CPUGPUBlendModeContractTests` owns the decision and pins it on both
    // backends; what is left here is that the modifier stays inert rather
    // than becoming a partial, backend-specific effect again.

    func testBlendModeMultiplyCompositesSourceOver() async {
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
            // Source-over of opaque blue: plain blue, not blue x red = black.
            XCTAssertEqual(center?.red ?? -1, Color.blue.red, accuracy: 0.01)
            XCTAssertEqual(center?.green ?? -1, Color.blue.green, accuracy: 0.01)
            XCTAssertEqual(center?.blue ?? -1, Color.blue.blue, accuracy: 0.01)
        }
    }

    func testBlendModeScreenCompositesSourceOver() async {
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
            XCTAssertEqual(
                center?.red ?? -1, Color.blue.red, accuracy: 0.01, "screen would have lifted red toward 1")
            XCTAssertEqual(center?.blue ?? -1, Color.blue.blue, accuracy: 0.01)
        }
    }

    func testBlendModeOverlayCompositesSourceOver() async {
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
            XCTAssertEqual(center?.red ?? -1, 1, accuracy: 0.01, "overlay would have darkened white to ~0.5")
        }
    }

    func testBlendModePlusLighterCompositesSourceOver() async {
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
            XCTAssertEqual(center?.red ?? -1, Color.red.red, accuracy: 0.01)
            XCTAssertEqual(
                center?.green ?? -1, Color.red.green, accuracy: 0.01,
                "additive would have added the backdrop's green on top")
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

    nonisolated func testAnimationValueOnlyAnimatesChangedTriggerAndPreservesActiveMotion() async {
        await MainActor.run {
            struct Trigger: Equatable {
                var selection: Int
            }
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var trigger = Trigger(selection: 0)
            var opacity = 1.0
            host.setComponents {
                [
                    Text("MOVE")
                        .opacity(opacity)
                        .animation(.linear(duration: 0.4), value: trigger)
                        .makeComponent(context: context)
                ]
            }
            let node = runtime.root.children[0]
            XCTAssertTrue(node.animationStates.isEmpty, "configuration alone must not start an animation")

            opacity = 0.7
            host.reload()
            XCTAssertEqual(node.opacity, 0.7)
            XCTAssertTrue(node.animationStates.isEmpty, "an unchanged trigger must not animate an unrelated update")

            opacity = 0.2
            trigger = Trigger(selection: 1)
            host.reload()
            guard let animation = node.animationStates[.opacity] else {
                return XCTFail("Expected the changed Equatable trigger to animate opacity")
            }
            XCTAssertEqual(animation.startValue, 0.7)
            XCTAssertEqual(animation.endValue, 0.2)
            XCTAssertEqual(animation.duration, 0.4)
            XCTAssertEqual(animation.easing, .linear)

            runtime.tickAnimations(at: animation.startTime + 0.2)
            let presentedOpacity = node.opacity
            host.reload()
            XCTAssertEqual(node.animationStates[.opacity]?.startTime, animation.startTime)
            XCTAssertEqual(node.opacity, presentedOpacity, accuracy: 0.0001)

            runtime.tickAnimations(at: animation.startTime + 0.5)
            XCTAssertEqual(node.opacity, 0.2, accuracy: 0.0001)
            XCTAssertTrue(node.animationStates.isEmpty)
        }
    }

    nonisolated func testAnimationValuePropagatesToDescendantTransformsAndOpacity() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var expanded = false
            host.setComponents {
                [
                    VStack {
                        Text("MOVE")
                            .offset(x: expanded ? 60 : 0)
                            .opacity(expanded ? 0.25 : 1)
                        Text("SCALE")
                            .scaleEffect(expanded ? 1.5 : 1)
                    }
                    .animation(.linear(duration: 0.4), value: expanded)
                    .makeComponent(context: context)
                ]
            }
            let container = runtime.root.children[0]
            let movedNode = container.children[0]
            let scaledNode = container.children[1]

            expanded = true
            host.reload()

            XCTAssertEqual(movedNode.animationStates[.transformTranslationX]?.startValue, 0)
            XCTAssertEqual(movedNode.animationStates[.transformTranslationX]?.endValue, 60)
            XCTAssertEqual(movedNode.animationStates[.opacity]?.endValue, 0.25)
            XCTAssertEqual(scaledNode.animationStates[.transformScaleX]?.endValue, 1.5)
            XCTAssertEqual(scaledNode.animationStates[.transformScaleY]?.endValue, 1.5)
            XCTAssertEqual(scaledNode.animationStates[.transformScaleX]?.duration, 0.4)
        }
    }

    nonisolated func testAnimatedFixedFrameInterpolatesSizeAndSiblingPlacementAcrossRebuilds() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 400, height: 100) },
                invalidateHandler: {}
            )
            let clock = RuntimeTestClock()
            clock.now = 10
            runtime.clock = { clock.now }
            var width = 100.0
            var height = 20.0
            var animation: Animation? = .linear(duration: 1)
            host.setComponents {
                [
                    HStack(spacing: 10) {
                        Rectangle()
                            .frame(width: width, height: height)
                            .animation(animation, value: width)
                        Text("NEXT")
                    }
                    .makeComponent(context: context)
                ]
            }
            runtime.setRootSize(IntSize(width: 400, height: 100))
            _ = runtime.renderFrame()
            let row = runtime.root.children[0]
            let framedNode = row.children[0]
            let sibling = row.children[1]
            XCTAssertEqual(framedNode.resolvedFrame.size.width, 100, accuracy: 0.001)
            XCTAssertEqual(sibling.resolvedFrame.minX, 110, accuracy: 0.001)

            width = 200
            host.reload()
            clock.now = 10.5
            runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertEqual(framedNode.resolvedFrame.size.width, 150, accuracy: 0.001)
            XCTAssertEqual(framedNode.children[0].resolvedFrame.size.width, 150, accuracy: 0.001)
            XCTAssertEqual(sibling.resolvedFrame.minX, 160, accuracy: 0.001)

            host.reload()
            _ = runtime.renderFrame()
            XCTAssertEqual(framedNode.resolvedFrame.size.width, 150, accuracy: 0.001)
            XCTAssertEqual(sibling.resolvedFrame.minX, 160, accuracy: 0.001)

            clock.now = 11
            runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertEqual(framedNode.resolvedFrame.size.width, 200, accuracy: 0.001)
            XCTAssertEqual(sibling.resolvedFrame.minX, 210, accuracy: 0.001)
            XCTAssertFalse(runtime.hasActiveAnimations)

            animation = nil
            width = 100
            height = 100
            host.reload()
            _ = runtime.renderFrame()
            animation = .bouncy
            width = 1
            height = 1
            host.reload()
            clock.now = 11.35
            runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertGreaterThan(framedNode.preferredSize?.width ?? 0, 0)
            XCTAssertGreaterThan(framedNode.preferredSize?.height ?? 0, 0)
            XCTAssertLessThan(framedNode.resolvedFrame.size.width, 1)
            XCTAssertLessThan(framedNode.resolvedFrame.size.height, 1)
            XCTAssertLessThan(framedNode.children[0].resolvedFrame.size.width, 1)
            XCTAssertLessThan(framedNode.children[0].resolvedFrame.size.height, 1)
            XCTAssertEqual(sibling.resolvedFrame.minX, 10, accuracy: 0.001)

            // The spring's negative sample is visually collapsed, but must
            // retain its fixed-size identity through an unrelated rebuild.
            host.reload()
            _ = runtime.renderFrame()
            XCTAssertLessThan(framedNode.resolvedFrame.size.width, 1)
            XCTAssertEqual(sibling.resolvedFrame.minX, 10, accuracy: 0.001)
            XCTAssertEqual(framedNode.animationStates[.preferredWidth]?.startTime, 11)
            XCTAssertEqual(framedNode.animationStates[.preferredHeight]?.startTime, 11)

            clock.now = 14
            runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertEqual(framedNode.resolvedFrame.size, Size(width: 1, height: 1))
            XCTAssertEqual(sibling.resolvedFrame.minX, 11, accuracy: 0.001)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    nonisolated func testNilAnimationValueSuppressesOnlyTheUpdateThatChangesItsTrigger() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var trigger = false
            var opacity = 1.0
            host.setComponents {
                [
                    Text("CONDITIONAL")
                        .opacity(opacity)
                        .animation(nil, value: trigger)
                        .makeComponent(context: context)
                ]
            }
            let node = runtime.root.children[0]

            opacity = 0.6
            withAnimation(.linear(duration: 0.4)) {
                host.reload()
            }
            guard let animation = node.animationStates[.opacity] else {
                return XCTFail("An unchanged nil-animation trigger must leave the ambient transaction intact")
            }
            runtime.tickAnimations(at: animation.startTime + 1)

            trigger = true
            opacity = 0.2
            withAnimation(.linear(duration: 0.4)) {
                host.reload()
            }
            XCTAssertEqual(node.opacity, 0.2)
            XCTAssertTrue(node.animationStates.isEmpty)
        }
    }

    nonisolated func testTransactionModifiersTransformInheritedAnimationAndDisableNestedAnimations() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var faded = false
            host.setComponents {
                [
                    VStack {
                        Text("STILL")
                            .opacity(faded ? 0.25 : 1)
                            .transaction { $0.animation = nil }
                        Text("FASTER")
                            .opacity(faded ? 0.25 : 1)
                            .transaction { $0.animation = $0.animation?.speed(2) }
                        Text("DISABLED")
                            .opacity(faded ? 0.25 : 1)
                            .animation(.linear(duration: 0.8), value: faded)
                            .transaction { $0.disablesAnimations = true }
                    }
                    .animation(.linear(duration: 0.4), value: faded)
                    .makeComponent(context: context)
                ]
            }
            let children = runtime.root.children[0].children
            faded = true
            host.reload()

            XCTAssertEqual(children[0].opacity, 0.25)
            XCTAssertTrue(children[0].animationStates.isEmpty)
            XCTAssertEqual(children[1].animationStates[.opacity]?.duration, 0.2)
            XCTAssertEqual(children[1].animationStates[.opacity]?.endValue, 0.25)
            XCTAssertEqual(children[2].opacity, 0.25)
            XCTAssertTrue(children[2].animationStates.isEmpty)
        }
    }

    nonisolated func testReduceMotionSuppressesModifierAndAmbientAnimations() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var faded = false
            host.setComponents {
                [
                    VStack {
                        Text("QUIET")
                            .opacity(faded ? 0.25 : 1)
                            .animation(.linear(duration: 0.4), value: faded)
                    }
                    .animation(.linear(duration: 0.4), value: faded)
                    .environment(\.accessibilityReduceMotion, true)
                    .makeComponent(context: context)
                ]
            }
            let node = runtime.root.children[0].children[0]
            faded = true
            withAnimation(.linear(duration: 0.4)) {
                host.reload()
            }
            XCTAssertEqual(node.opacity, 0.25)
            XCTAssertTrue(node.animationStates.isEmpty)
        }
    }

    nonisolated func testUnconditionalAnimationModifierStartsOnlyWhenAPropertyChanges() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var opacity = 1.0
            host.setComponents {
                [
                    Text("ANIM")
                        .opacity(opacity)
                        .animation(.easeInOut(duration: 0.3))
                        .makeComponent(context: context)
                ]
            }
            let node = runtime.root.children[0]
            XCTAssertTrue(node.animationStates.isEmpty)
            XCTAssertFalse(runtime.hasActiveAnimations)

            opacity = 0.4
            host.reload()
            XCTAssertEqual(node.animationStates[.opacity]?.duration, 0.3)
            XCTAssertEqual(node.animationStates[.opacity]?.endValue, 0.4)
            XCTAssertTrue(runtime.hasActiveAnimations)
        }
    }
}
