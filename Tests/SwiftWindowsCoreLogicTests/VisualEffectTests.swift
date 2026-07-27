import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import Testing

@testable import SwiftWindowsUI

@MainActor
@Suite("Visual Effect Encoding and Rendering Tests")
struct VisualEffectTests {

    // MARK: - Encoding Tests

    @Test("Encode brightness effect")
    func encodeBrightness() async {
        let effects: [RetainedColorEffect] = [.brightness(0.25)]
        let (type, intensity, p1, p2, p3, p4) = ScenePainter.encodeColorEffects(effects)
        #expect(type == 1)
        #expect(intensity == 0.25)
        #expect(p1 == 0)
        #expect(p2 == 0)
        #expect(p3 == 0)
        #expect(p4 == 0)
    }

    @Test("Encode contrast effect")
    func encodeContrast() async {
        let effects: [RetainedColorEffect] = [.contrast(0.5)]
        let (type, intensity, p1, p2, p3, p4) = ScenePainter.encodeColorEffects(effects)
        #expect(type == 2)
        #expect(intensity == 0.5)
        #expect(p1 == 0)
        #expect(p2 == 0)
        #expect(p3 == 0)
        #expect(p4 == 0)
    }

    @Test("Encode saturation effect")
    func encodeSaturation() async {
        let effects: [RetainedColorEffect] = [.saturation(-0.3)]
        let (type, intensity, p1, p2, p3, p4) = ScenePainter.encodeColorEffects(effects)
        #expect(type == 3)
        #expect(intensity == -0.3)
        #expect(p1 == 0)
        #expect(p2 == 0)
        #expect(p3 == 0)
        #expect(p4 == 0)
    }

    @Test("Encode grayscale effect")
    func encodeGrayscale() async {
        let effects: [RetainedColorEffect] = [.grayscale(1.0)]
        let (type, intensity, p1, p2, p3, p4) = ScenePainter.encodeColorEffects(effects)
        #expect(type == 4)
        #expect(intensity == 1.0)
        #expect(p1 == 0)
        #expect(p2 == 0)
        #expect(p3 == 0)
        #expect(p4 == 0)
    }

    @Test("Encode colorInvert effect")
    func encodeColorInvert() async {
        let effects: [RetainedColorEffect] = [.colorInvert]
        let (type, intensity, p1, p2, p3, p4) = ScenePainter.encodeColorEffects(effects)
        #expect(type == 5)
        #expect(intensity == 0)
        #expect(p1 == 0)
        #expect(p2 == 0)
        #expect(p3 == 0)
        #expect(p4 == 0)
    }

    @Test("Encode hueRotation effect")
    func encodeHueRotation() async {
        let effects: [RetainedColorEffect] = [.hueRotation(Double.pi / 4)]
        let (type, intensity, p1, p2, p3, p4) = ScenePainter.encodeColorEffects(effects)
        #expect(type == 6)
        #expect(intensity == 0)
        #expect(p1 == Float(Double.pi / 4))
        #expect(p2 == 0)
        #expect(p3 == 0)
        #expect(p4 == 0)
    }

    @Test("Encode colorMultiply effect")
    func encodeColorMultiply() async {
        // Assert against live system color components (macOS HIG values), not
        // pure primaries, so this test verifies effect-parameter propagation.
        let multiply = Color.red
        let effects: [RetainedColorEffect] = [.colorMultiply(multiply)]
        let (type, intensity, p1, p2, p3, p4) = ScenePainter.encodeColorEffects(effects)
        let tolerance: Float = 1e-5
        #expect(type == 7)
        #expect(intensity == 0)
        #expect(abs(p1 - multiply.red) <= tolerance)
        #expect(abs(p2 - multiply.green) <= tolerance)
        #expect(abs(p3 - multiply.blue) <= tolerance)
        #expect(p4 == 0)
    }

    @Test("Encode luminanceToAlpha effect")
    func encodeLuminanceToAlpha() async {
        let effects: [RetainedColorEffect] = [.luminanceToAlpha]
        let (type, intensity, p1, p2, p3, p4) = ScenePainter.encodeColorEffects(effects)
        #expect(type == 8)
        #expect(intensity == 0)
        #expect(p1 == 0)
        #expect(p2 == 0)
        #expect(p3 == 0)
        #expect(p4 == 0)
    }

    @Test("Empty effects encode to none")
    func encodeEmpty() async {
        let effects: [RetainedColorEffect] = []
        let (type, intensity, p1, p2, p3, p4) = ScenePainter.encodeColorEffects(effects)
        #expect(type == 0)
        #expect(intensity == 0)
        #expect(p1 == 0)
        #expect(p2 == 0)
        #expect(p3 == 0)
        #expect(p4 == 0)
    }

    // MARK: - Quad Primitive Effect Field Tests

    @Test("QuadPrimitive carries effect fields")
    func quadPrimitiveEffects() async {
        let quad = QuadPrimitive(
            x: 10, y: 20, width: 100, height: 50,
            cornerRadius: 8,
            startR: 1, startG: 0, startB: 0, startA: 1,
            endR: 0, endG: 1, endB: 0, endA: 1,
            gradientAxis: 0,
            clipX: 0, clipY: 0, clipWidth: 200, clipHeight: 200,
            effectType: 2,
            effectIntensity: 0.5,
            effectParam1: 0.25,
            effectParam2: 0.75
        )
        #expect(quad.effectType == 2)
        #expect(quad.effectIntensity == 0.5)
        #expect(quad.effectParam1 == 0.25)
        #expect(quad.effectParam2 == 0.75)
        #expect(quad.effectParam3 == 0)
        #expect(quad.effectParam4 == 0)
        // 144 after adding per-corner radii + 3 reserved padding floats
        // for HLSL 16-byte structured-buffer alignment.
        #expect(QuadPrimitive.byteSize == 144)
    }

    // MARK: - Scene Integration Test

    @Test("ScenePainter encodes effects into quad primitives")
    func scenePainterEncodesEffects() async {
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            colorEffects: [.brightness(0.25)]
        )

        let scene = ScenePainter.paint(
            root: root,
            clearColor: .black,
            surfaceSize: Size(width: 100, height: 100),
            displayScale: 1
        )

        guard let firstLayer = scene.layers.first else {
            Issue.record("Expected at least one layer")
            return
        }

        guard let quad = firstLayer.quads.first else {
            Issue.record("Expected at least one quad")
            return
        }

        #expect(quad.effectType == 1)
        #expect(quad.effectIntensity == 0.25)
    }

    @Test("ScenePainter encodes hueRotation into quad primitives")
    func scenePainterEncodesHueRotation() async {
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            colorEffects: [.hueRotation(Double.pi / 2)]
        )

        let scene = ScenePainter.paint(
            root: root,
            clearColor: .black,
            surfaceSize: Size(width: 100, height: 100),
            displayScale: 1
        )

        guard let firstLayer = scene.layers.first else {
            Issue.record("Expected at least one layer")
            return
        }

        guard let quad = firstLayer.quads.first else {
            Issue.record("Expected at least one quad")
            return
        }

        #expect(quad.effectType == 6)
        #expect(quad.effectParam1 == Float(Double.pi / 2))
    }

    @Test("ScenePainter encodes colorMultiply into quad primitives")
    func scenePainterEncodesColorMultiply() async {
        // Assert against live system color components (macOS HIG values), not
        // pure primaries, so this test verifies effect-parameter propagation.
        let multiply = Color.green
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
            colorEffects: [.colorMultiply(multiply)]
        )

        let scene = ScenePainter.paint(
            root: root,
            clearColor: .black,
            surfaceSize: Size(width: 100, height: 100),
            displayScale: 1
        )

        guard let firstLayer = scene.layers.first else {
            Issue.record("Expected at least one layer")
            return
        }

        guard let quad = firstLayer.quads.first else {
            Issue.record("Expected at least one quad")
            return
        }

        let tolerance: Float = 1e-5
        #expect(quad.effectType == 7)
        #expect(abs(quad.effectParam1 - multiply.red) <= tolerance)
        #expect(abs(quad.effectParam2 - multiply.green) <= tolerance)
        #expect(abs(quad.effectParam3 - multiply.blue) <= tolerance)
    }

    // MARK: - Blur Tests

    @Test("QuadPrimitive carries blur fields")
    func quadPrimitiveBlurFields() async {
        let quad = QuadPrimitive(
            x: 10, y: 20, width: 100, height: 50,
            blurRadius: 4,
            blurOpaque: 1
        )
        #expect(quad.blurRadius == 4)
        #expect(quad.blurOpaque == 1)
    }

    @Test("ScenePainter encodes blur into quad primitives")
    func scenePainterEncodesBlur() async {
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            blurRadius: 8,
            blurOpaque: true
        )

        let scene = ScenePainter.paint(
            root: root,
            clearColor: .black,
            surfaceSize: Size(width: 100, height: 100),
            displayScale: 1
        )

        guard let firstLayer = scene.layers.first else {
            Issue.record("Expected at least one layer")
            return
        }

        guard let quad = firstLayer.quads.first else {
            Issue.record("Expected at least one quad")
            return
        }

        #expect(quad.blurRadius == 8)
        #expect(quad.blurOpaque == 1)
    }

    @Test("CPU rasterizer applies blur post-processing")
    func cpuRasterizerAppliesBlur() async {
        let clearColor = Color(red: 0, green: 0, blue: 0, alpha: 0.5)

        var noBlurScene = GPUIScene(clearColor: clearColor)
        noBlurScene.addQuad(
            QuadPrimitive(
                x: 10, y: 10, width: 20, height: 20,
                startR: 1, startG: 1, startB: 1, startA: 0.5,
                endR: 1, endG: 1, endB: 1, endA: 0.5
            ), toLayer: 0)
        noBlurScene.finish()

        var blurScene = GPUIScene(clearColor: clearColor)
        blurScene.addQuad(
            QuadPrimitive(
                x: 10, y: 10, width: 20, height: 20,
                startR: 1, startG: 1, startB: 1, startA: 0.5,
                endR: 1, endG: 1, endB: 1, endA: 0.5,
                blurRadius: 2,
                blurOpaque: 1
            ), toLayer: 0)
        blurScene.finish()

        let noBlurBitmap = GPUIRawSceneRasterizer.rasterize(noBlurScene, size: IntSize(width: 40, height: 40))
        let blurBitmap = GPUIRawSceneRasterizer.rasterize(blurScene, size: IntSize(width: 40, height: 40))

        let sampleOffset = (15 * 40 + 15) * 4
        let noBlurAlpha = noBlurBitmap.pixels[sampleOffset + 3]
        let blurAlpha = blurBitmap.pixels[sampleOffset + 3]

        #expect(blurAlpha > noBlurAlpha, "Blur opaque should increase alpha")
    }
}
