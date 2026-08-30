import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Playback consumes completed scene values and native animation values only.
/// These fixtures never create a ViewNode, invoke a painter, or render pixels.
@MainActor
final class RetainedLazyListRemovalPaintTests: XCTestCase {
    private let surfaceSize = IntSize(width: 64, height: 64)

    func testExistingEaseInKeepsItsOriginalPhaseAfterDeparture() async throws {
        let source = try quadSource()
        var paint = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(transform: .translation(x: 10, y: 0)),
                animation: animation(
                    [.transformTranslationX: state(0, 40, easing: .easeIn)], resolvedAt: 0.5)))

        let initial = try rendered(paint)
        XCTAssertEqual(initial.image.affineA, 1)
        XCTAssertEqual(initial.image.affineD, 1)
        XCTAssertEqual(initial.image.screenX, 4)
        XCTAssertEqual(initial.image.screenY, 6)

        paint.advance(to: 0.75)
        let continued = try rendered(paint)
        XCTAssertEqual(continued.image.affineA, 1)
        XCTAssertEqual(continued.image.affineD, 1)
        XCTAssertEqual(continued.image.screenX, 16.5)
        XCTAssertEqual(10 + continued.image.screenX - initial.image.screenX, 22.5)
        XCTAssertNotEqual(continued.image.screenX, 11.5)
        XCTAssertEqual(continued.image.screenY, 6)
        XCTAssertEqual(continued.pass.scene, source.scene)
    }

    func testFreshRemovalStartsAtTheLastPresentedOpacityAndTransform() async throws {
        let source = try quadSource(opacity: 0.4)
        var paint = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(opacity: 0.4, transform: .translation(x: 6, y: 0)),
                animation: animation(
                    [
                        .opacity: state(1, 0, time: 10),
                        .transformTranslationX: state(0, 14, time: 10),
                    ], resolvedAt: 10, removalProperties: [.opacity, .transformTranslationX])))

        let initial = try rendered(paint)
        XCTAssertEqual(initial.image.affineA, 1)
        XCTAssertEqual(initial.image.opacity, 1)
        XCTAssertEqual(initial.pass.scene.layers[0].quads[0].startA, 0.4)

        paint.advance(to: 10.5)
        let halfway = try rendered(paint)
        XCTAssertEqual(halfway.image.affineA, 1)
        XCTAssertEqual(halfway.image.screenX, 8)
        XCTAssertEqual(halfway.image.screenY, 6)
        XCTAssertEqual(halfway.image.opacity, 1)
        XCTAssertEqual(halfway.pass.scene.layers[0].quads[0].startA, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(source.scene.layers[0].quads[0].startA, 0.4)
    }

    func testUnfinishedFrameAndOutlineStatesRejectEvenWhenTheirEndpointsAreEqual() async throws {
        let source = try quadSource()
        for property in [AnimatableProperty.frameWidth, .outlineWidth] {
            for end in [10.0, 30.0] {
                XCTAssertNil(
                    RetainedLazyListRemovalPaint(
                        source: source, pose: pose(),
                        animation: animation(
                            [
                                .opacity: state(1, 0, time: 1),
                                property: state(10, end, duration: 2),
                            ], resolvedAt: 1)))
            }

            let completed = state(10, 30)
            let paint = try XCTUnwrap(
                RetainedLazyListRemovalPaint(
                    source: source, pose: pose(),
                    animation: animation(
                        [.opacity: state(1, 0, time: 1), property: completed], resolvedAt: 1)))
            XCTAssertEqual(try rendered(paint).image.affineA, 1)
            XCTAssertNil(
                RetainedLazyListRemovalPaint(
                    source: source, pose: pose(),
                    animation: animation([property: completed], resolvedAt: 1)))
        }
    }

    func testCapturedClippingAndNonrectangularInheritedClipsRejectGeometryChanges() async throws {
        let clipped = try quadSource(clip: Rect(x: 5, y: 0, width: 40, height: 64))
        XCTAssertTrue(clipped.wasClipped)
        let movement = animation([.transformTranslationX: state(0, 8)])
        XCTAssertNil(RetainedLazyListRemovalPaint(source: clipped, pose: pose(), animation: movement))

        var fade = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: clipped, pose: pose(), animation: animation([.opacity: state(1, 0)])))
        fade.advance(to: 0.5)
        let faded = try rendered(fade)
        XCTAssertEqual(faded.image.affineA, 1)
        XCTAssertEqual(faded.pass.scene.layers[0].quads[0].startA, 0.5)
        XCTAssertEqual(
            faded.pass.scene.layers[0].quads[0].contentMask,
            clipped.scene.layers[0].quads[0].contentMask)

        let source = try quadSource()
        XCTAssertFalse(source.wasClipped)
        let bounds = Rect(x: 0, y: 0, width: 64, height: 64)
        let clips = [
            RuntimeClipShape(rect: bounds, uniformRadius: 8, space: .painted),
            RuntimeClipShape(rect: bounds, rotation: .pi / 4, space: .painted),
        ]
        for clip in clips {
            XCTAssertNil(
                RetainedLazyListRemovalPaint(source: source, pose: pose(clip: clip), animation: movement))
        }
    }

    func testDependentMaterialOnlyFadesInItsOriginalPixelDomain() async throws {
        let source = try quadSource(opacity: 0.8, blurRadius: 2)
        XCTAssertEqual(source.input, .isolatedBackdrop)
        XCTAssertEqual(source.size, surfaceSize)
        XCTAssertNil(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(opacity: 0.8),
                animation: animation([.transformTranslationX: state(0, 8)])))
        var paint = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(opacity: 0.8),
                animation: animation([.opacity: state(1, 0)], removalProperties: [.opacity])))

        paint.advance(to: 0.5)
        let faded = try rendered(paint)
        XCTAssertEqual(faded.image.opacity, 1)
        XCTAssertEqual(faded.image.affineA, 1)
        XCTAssertEqual(faded.image.screenW, 64)
        XCTAssertEqual(faded.pass.input, .isolatedBackdrop)
        XCTAssertEqual(faded.pass.scene.layers[0].quads[0].blurRadius, 2)
        XCTAssertEqual(faded.pass.scene.layers[0].quads[0].startA, 0.4)
        XCTAssertEqual(source.scene.layers[0].quads[0].startA, 0.8)
        XCTAssertNil(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(opacity: 0.8, rootOpacityIsInPrimitives: false),
                animation: animation([.opacity: state(1, 0)])))
        XCTAssertTrue(paint.permitsDisplayScale(1))
        XCTAssertFalse(paint.permitsDisplayScale(1.5))
        let changedDPI = scene(for: paint, displayScale: 1.5)
        XCTAssertEqual(changedDPI.primitiveCount, 0)
        XCTAssertTrue(changedDPI.imageRenderPasses.isEmpty)
    }

    func testZeroOpacityMaterialRootIsCulledWhileAnUnrelatedTimelineFinishes() async throws {
        let source = try quadSource(opacity: 1, blurRadius: 2)
        var paint = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(),
                animation: animation([
                    .opacity: state(1, 0),
                    .transformTranslationX: state(0, 0, duration: 2),
                ])))
        paint.advance(to: 1)
        XCTAssertFalse(paint.isComplete)
        let invisible = scene(for: paint)
        XCTAssertEqual(invisible.primitiveCount, 0)
        XCTAssertTrue(invisible.imageRenderPasses.isEmpty)
    }

    func testOpacitySamplingClampsOvershootAndRejectsAnAlreadySaturatedRootPose() async throws {
        let source = try quadSource(opacity: 0.3)
        let paint = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(),
                animation: animation([.opacity: state(1.2, 1.2, duration: 2)], resolvedAt: 1)))
        let result = try rendered(paint)
        XCTAssertEqual(result.image.opacity, 1)
        XCTAssertEqual(result.pass.scene.layers[0].quads[0].startA, 0.3)
        for opacity in [0.0, -0.5, 1.2, 2.0] {
            XCTAssertNil(
                RetainedLazyListRemovalPaint(
                    source: source, pose: pose(opacity: opacity),
                    animation: animation([.opacity: state(opacity, 0)])))
        }
    }

    func testIndependentRootEffectsAndBlurBitmapRejectAmbiguousOpacity() async throws {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(QuadPrimitive(width: 8, height: 8, startA: 0.8, endA: 0.8))
        let effectCases: [[SceneColorEffect]] = [[.brightness(0.2)], [.luminanceToAlpha]]
        for effects in effectCases {
            var scene = GPUIScene(clearColor: .clear)
            let id = scene.registerImageRenderPass(
                child, size: IntSize(width: 8, height: 8), colorEffects: effects)
            scene.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: id))
            let source = try captured(scene)
            XCTAssertEqual(source.input, .independent)
            XCTAssertNil(
                RetainedLazyListRemovalPaint(
                    source: source, pose: pose(rootOpacityIsInPrimitives: false),
                    animation: animation([.opacity: state(1, 0)])))

            // A descendant-owned effect has a different opacity boundary.
            var inherited = try XCTUnwrap(
                RetainedLazyListRemovalPaint(
                    source: source, pose: pose(), animation: animation([.opacity: state(1, 0)])))
            inherited.advance(to: 0.5)
            let faded = try rendered(inherited)
            XCTAssertEqual(faded.image.opacity, 1)
            XCTAssertEqual(faded.pass.scene.layers[0].images[0].opacity, 0.5)
            XCTAssertEqual(faded.pass.scene.imageRenderPasses, source.scene.imageRenderPasses)
        }

        // The frame path may have already baked the root's blur into a bitmap.
        // Its bytes cannot establish where the root's opacity was applied.
        var bitmapScene = GPUIScene(clearColor: .clear)
        bitmapScene.bindImageResource(
            BitmapSurface(width: 2, height: 2, bytesPerRow: 8, pixels: Data(repeating: 128, count: 16)),
            for: 3)
        bitmapScene.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: 3))
        let bitmapSource = try captured(bitmapScene)
        XCTAssertEqual(bitmapSource.input, .independent)
        XCTAssertNil(
            RetainedLazyListRemovalPaint(
                source: bitmapSource, pose: pose(rootOpacityIsInPrimitives: false),
                animation: animation([.opacity: state(1, 0)])))
    }

    func testSingularPresentedGeometryRejectsMotionButAllowsOpacityOnlyPlayback() async throws {
        let source = try quadSource()
        let collapsed = pose(transform: Transform2D(scaleX: 0))
        XCTAssertNil(
            RetainedLazyListRemovalPaint(
                source: source, pose: collapsed, animation: animation([.transformTranslationX: state(0, 8)])))

        var paint = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: collapsed, animation: animation([.opacity: state(1, 0)])))
        paint.advance(to: 0.5)
        let faded = try rendered(paint)
        XCTAssertEqual(faded.image.affineA, 1)
        XCTAssertEqual(faded.image.affineD, 1)
        XCTAssertEqual(faded.image.screenX, 4)
        XCTAssertEqual(faded.pass.scene.layers[0].quads[0].startA, 0.5)
    }

    func testClockIsMonotonicAndTheLastDeadlinePermanentlyEndsPlayback() async throws {
        let source = try quadSource()
        var paint = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(),
                animation: animation(
                    [
                        .opacity: state(1, 0.5, time: 2),
                        .transformTranslationX: state(0, 8, time: 2, duration: 2),
                    ], resolvedAt: 2)))
        paint.advance(to: 3)
        let halfway = try rendered(paint)
        XCTAssertFalse(paint.isComplete)
        XCTAssertEqual(halfway.image.screenX, 8)
        XCTAssertEqual(halfway.pass.scene.layers[0].quads[0].startA, 0.5)
        for time in [2.5, Double.nan, Double.infinity, -Double.infinity] {
            paint.advance(to: time)
            let unchanged = try rendered(paint)
            XCTAssertEqual(unchanged.image, halfway.image)
            XCTAssertEqual(unchanged.pass.scene, halfway.pass.scene)
        }

        XCTAssertTrue(paint.permitsDisplayScale(2))
        for scale in [0, -1, Double.nan, Double.infinity] {
            XCTAssertFalse(paint.permitsDisplayScale(scale))
        }
        let doubled = try rendered(paint, displayScale: 2)
        XCTAssertEqual(doubled.image.affineA, 2)
        XCTAssertEqual(doubled.image.affineD, 2)
        XCTAssertEqual(doubled.image.screenX, 20)
        XCTAssertEqual(doubled.image.screenY, 17)

        paint.advance(to: 3.999)
        XCTAssertFalse(paint.isComplete)
        paint.advance(to: 4)
        XCTAssertTrue(paint.isComplete)
        paint.advance(to: 2)
        XCTAssertTrue(paint.isComplete)
        let completed = scene(for: paint)
        XCTAssertEqual(completed.primitiveCount, 0)
        XCTAssertTrue(completed.imageRenderPasses.isEmpty)
    }

    func testRootScaleAndRotationRejectInsteadOfChangingPrimitiveTransformOrder() async throws {
        let rotation = Transform2D(rotation: .pi / 2)
        let halfwayScale = Transform2D(scaleX: 1.5)
        let localBounds = Rect(x: -10, y: -10, width: 20, height: 20)
        let ordinary = localBounds.applying(transform: halfwayScale).applying(transform: rotation)
        let frozen = localBounds.applying(transform: rotation).applying(transform: halfwayScale)
        XCTAssertEqual(ordinary.size.width, 20, accuracy: 0.000_001)
        XCTAssertEqual(ordinary.size.height, 30, accuracy: 0.000_001)
        XCTAssertEqual(frozen.size.width, 30, accuracy: 0.000_001)
        XCTAssertEqual(frozen.size.height, 20, accuracy: 0.000_001)

        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(
            QuadPrimitive(x: 40, y: 40, width: 20, height: 20, rotationRadians: .pi / 2))
        let source = try captured(scene)
        let presented = pose(pivot: Point(x: 50, y: 50))
        for property in [AnimatableProperty.transformScaleX, .transformScaleY] {
            XCTAssertNil(
                RetainedLazyListRemovalPaint(
                    source: source, pose: presented, animation: animation([property: state(1, 2)])))
        }
        XCTAssertNil(
            RetainedLazyListRemovalPaint(
                source: source, pose: presented, animation: animation([.transformRotation: state(0, .pi / 2)])))
        XCTAssertNil(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(transform: Transform2D(scaleX: 2)),
                animation: animation([.transformScaleX: state(1, 1, time: 2)])))

        var translated = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: presented, animation: animation([.transformTranslationX: state(0, 10)])))
        translated.advance(to: 0.5)
        let moved = try rendered(translated)
        XCTAssertEqual(moved.image.affineA, 1)
        XCTAssertEqual(moved.image.affineD, 1)
        XCTAssertEqual(moved.image.screenX, Float(source.bounds.minX + 5), accuracy: 0.000_001)
    }

    func testDelayedTranslationDoesNotReplaceThePresentedPoseBeforeItsStart() async throws {
        let source = try quadSource()
        var paint = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(transform: .translation(x: 10, y: 0)),
                animation: animation([.transformTranslationX: state(20, 40, time: 2)])))
        let initial = try rendered(paint)
        XCTAssertEqual(initial.image.screenX, 4)
        paint.advance(to: 1.5)
        XCTAssertEqual(try rendered(paint).image, initial.image)

        paint.advance(to: 2)
        XCTAssertEqual(try rendered(paint).image.screenX, 14)
        paint.advance(to: 2.5)
        XCTAssertEqual(try rendered(paint).image.screenX, 24)
    }

    func testEqualClockValuesDoNotTurnAnExistingTimelineIntoAFreshRemovalState() async throws {
        let source = try quadSource(opacity: 0.4)
        var paint = try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source, pose: pose(opacity: 0.4, transform: .translation(x: 10, y: 0)),
                animation: animation(
                    [
                        .opacity: state(1, 0, time: 10),
                        .transformTranslationX: state(20, 40, time: 10, duration: 2),
                    ], resolvedAt: 10, removalProperties: [.opacity])))
        let initial = try rendered(paint)
        XCTAssertEqual(initial.image.screenX, 14)
        XCTAssertEqual(initial.pass.scene.layers[0].quads[0].startA, 0.4)
        paint.advance(to: 10.5)
        let continued = try rendered(paint)
        XCTAssertEqual(continued.image.screenX, 19)
        XCTAssertEqual(continued.pass.scene.layers[0].quads[0].startA, 0.2, accuracy: 0.000_001)
    }

    private func captured(_ scene: GPUIScene) throws -> RetainedLazyListPaintSource {
        guard
            case .captured(let source) = RetainedLazyListPaintSource.capture(
                scene: scene, ranges: [0..<scene.paintRecordCount], surfaceSize: surfaceSize)
        else {
            XCTFail("Expected an immutable capture of the supplied scene values")
            throw CaptureFailure.expectedSource
        }
        return source
    }

    private func quadSource(
        opacity: Float = 1, clip: Rect? = nil, blurRadius: Float = 0
    ) throws -> RetainedLazyListPaintSource {
        var scene = GPUIScene(clearColor: .clear)
        var quad = QuadPrimitive(
            x: 4, y: 6, width: 8, height: 10, startR: 1, startA: opacity, endR: 1, endA: opacity,
            blurRadius: blurRadius)
        quad.contentMask = GPUIContentMask(bounds: clip)
        scene.addQuad(quad)
        return try captured(scene)
    }

    private func pose(
        opacity: Double = 1, transform: Transform2D = .identity, pivot: Point = Point(x: 8, y: 11),
        clip: RuntimeClipShape? = nil, rootOpacityIsInPrimitives: Bool = true
    ) -> RetainedLazyListPaintPose {
        RetainedLazyListPaintPose(
            opacity: opacity, transform: transform, pivot: pivot, clip: clip, displayScale: 1,
            rootOpacityIsInPrimitives: rootOpacityIsInPrimitives)
    }

    private func state(
        _ start: Double, _ end: Double, time: Double = 0, duration: Double = 1,
        easing: AnimationEasing = .linear
    ) -> AnimationState {
        AnimationState(startValue: start, endValue: end, startTime: time, duration: duration, easing: easing)
    }

    private func animation(
        _ states: [AnimatableProperty: AnimationState], resolvedAt: Double = 0,
        removalProperties: Set<AnimatableProperty> = []
    ) -> RetainedRemovalTransitionAnimation {
        RetainedRemovalTransitionAnimation(
            initialOpacity: 1, initialTransform: .identity, frame: Rect(x: 4, y: 6, width: 8, height: 10),
            states: states, removalProperties: removalProperties, resolvedAt: resolvedAt)
    }

    private func scene(for paint: RetainedLazyListRemovalPaint, displayScale: Double = 1) -> GPUIScene {
        var scene = GPUIScene(clearColor: .clear)
        paint.append(to: &scene, targetSize: surfaceSize, displayScale: displayScale)
        return scene
    }

    private func rendered(
        _ paint: RetainedLazyListRemovalPaint, displayScale: Double = 1
    ) throws -> (image: ImagePrimitive, pass: GPUISceneImageRenderPass) {
        let output = scene(for: paint, displayScale: displayScale)
        let images = output.layers.flatMap(\.images)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(output.imageRenderPasses.count, 1)
        let image = try XCTUnwrap(images.first)
        let pass = try XCTUnwrap(output.imageRenderPasses.first)
        XCTAssertEqual(image.textureID, pass.textureID)
        return (image, pass)
    }

    private enum CaptureFailure: Error {
        case expectedSource
    }
}
