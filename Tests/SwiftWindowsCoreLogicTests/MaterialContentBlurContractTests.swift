import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics

/// Descriptor, exact-copy and allocation admission checks. These use scene
/// values only; no renderer or platform device is needed to establish them.
@MainActor
final class MaterialContentBlurContractTests: XCTestCase {
    func testNegativeOriginRetainsTransparentHaloAndExactParentCopy() async throws {
        let pass = isolatedPass(size: IntSize(width: 108, height: 108), radius: 3)
        let image = consumer(pass, x: -4, y: -4)
        let mapping = try XCTUnwrap(
            pass.isolatedBackdropMapping(for: image, parentSize: IntSize(width: 100, height: 100)))

        XCTAssertEqual(mapping.originX, -4)
        XCTAssertEqual(mapping.originY, -4)
        XCTAssertEqual(mapping.size, IntSize(width: 108, height: 108))
        XCTAssertEqual(mapping.childOffsetX, 4)
        XCTAssertEqual(mapping.childOffsetY, 4)
        XCTAssertEqual(
            mapping.parentCopyRegion,
            SubTextureRegion(originX: 0, originY: 0, width: 100, height: 100, textureWidth: 100, textureHeight: 100))
        XCTAssertEqual(
            mapping.validChildRegion,
            SubTextureRegion(originX: 4, originY: 4, width: 100, height: 100, textureWidth: 108, textureHeight: 108))
        XCTAssertTrue(defects(pass, image).isEmpty)
    }

    func testOddExtentsAndViewportEdgesKeepOnlyAvailableParentPixels() async throws {
        let pass = isolatedPass(size: IntSize(width: 5, height: 3))
        let parentSize = IntSize(width: 10, height: 8)
        let cases: [(x: Int, y: Int, left: Int, top: Int, width: Int, height: Int, dx: Int, dy: Int)] = [
            (2, 2, 2, 2, 5, 3, 0, 0),
            (-2, 2, 0, 2, 3, 3, 2, 0),
            (8, 2, 8, 2, 2, 3, 0, 0),
            (2, -2, 2, 0, 5, 1, 0, 2),
            (2, 6, 2, 6, 5, 2, 0, 0),
            (-2, -2, 0, 0, 3, 1, 2, 2),
            (8, 6, 8, 6, 2, 2, 0, 0),
        ]
        for item in cases {
            let image = consumer(pass, x: Float(item.x), y: Float(item.y))
            let mapping = try XCTUnwrap(pass.isolatedBackdropMapping(for: image, parentSize: parentSize))
            XCTAssertEqual(mapping.childOffsetX, item.dx)
            XCTAssertEqual(mapping.childOffsetY, item.dy)
            XCTAssertEqual(
                mapping.parentCopyRegion,
                SubTextureRegion(
                    originX: item.left, originY: item.top, width: item.width, height: item.height,
                    textureWidth: 10, textureHeight: 8))
            XCTAssertEqual(
                mapping.validChildRegion,
                SubTextureRegion(
                    originX: item.dx, originY: item.dy, width: item.width, height: item.height,
                    textureWidth: 5, textureHeight: 3))
            XCTAssertTrue(defects(pass, image).isEmpty)
        }
    }

    func testNonOverlappingPlacementHasNoInventedBackdropPixels() async throws {
        let pass = isolatedPass(size: IntSize(width: 5, height: 3))
        let limit = Float(GPUISceneLimits.maxSurfaceDimension)
        let origins: [(Float, Float)] = [
            (-6, 0), (10, 0), (0, -4), (0, 8), (-limit, 0), (limit, 0), (0, -limit), (0, limit),
        ]
        for (x, y) in origins {
            let image = consumer(pass, x: x, y: y)
            let mapping = try XCTUnwrap(
                pass.isolatedBackdropMapping(for: image, parentSize: IntSize(width: 10, height: 8)))
            XCTAssertNil(mapping.parentCopyRegion)
            XCTAssertNil(mapping.validChildRegion)
            XCTAssertEqual(mapping.childOffsetX, 0)
            XCTAssertEqual(mapping.childOffsetY, 0)
            XCTAssertTrue(defects(pass, image).isEmpty, "Structural validation must not invent a target extent")
        }
    }

    func testMappingChecksActualParentDimensionsWithoutChangingStaticAdmission() async throws {
        let pass = isolatedPass(size: IntSize(width: 5, height: 3))
        let image = consumer(pass, x: 6, y: 2)
        XCTAssertTrue(defects(pass, image).isEmpty)
        let wider = try XCTUnwrap(
            pass.isolatedBackdropMapping(for: image, parentSize: IntSize(width: 12, height: 8)))
        let narrower = try XCTUnwrap(
            pass.isolatedBackdropMapping(for: image, parentSize: IntSize(width: 8, height: 8)))
        XCTAssertEqual(wider.parentCopyRegion?.width, 5)
        XCTAssertEqual(narrower.parentCopyRegion?.width, 2)
        XCTAssertEqual(narrower.validChildRegion?.width, 2)
        XCTAssertEqual(narrower.size.width, 5, "The transparent output buffer is not cropped to the parent copy")

        let invalidSizes = [
            IntSize(width: 0, height: 8), IntSize(width: 8, height: 0),
            IntSize(width: -1, height: 8), IntSize(width: 8, height: -1),
            IntSize(width: Int32(GPUISceneLimits.maxSurfaceDimension + 1), height: 8),
            IntSize(width: 8, height: Int32(GPUISceneLimits.maxSurfaceDimension + 1)),
            IntSize(width: .max, height: .max),
        ]
        for size in invalidSizes {
            XCTAssertNil(pass.isolatedBackdropMapping(for: image, parentSize: size))
        }
    }

    func testOriginsMustBeFiniteBoundedEvenDevicePixels() async {
        let pass = isolatedPass()
        let image = consumer(pass)
        let limit = Float(GPUISceneLimits.maxSurfaceDimension)
        let fields: [WritableKeyPath<ImagePrimitive, Float>] = [\.screenX, \.screenY]
        for field in fields {
            for value in [Float.nan, .infinity, -.infinity, 0.5, -0.5, 1, -1, limit + 2, -limit - 2] {
                var invalid = image
                invalid[keyPath: field] = value
                XCTAssertNotNil(pass.isolatedBackdropImageDefect(invalid))
                XCTAssertNil(pass.isolatedBackdropMapping(for: invalid, parentSize: IntSize(width: 8, height: 8)))
                XCTAssertTrue(hasPassDefect(defects(pass, invalid)))
            }
        }
    }

    func testConsumerRequiresMatchingSourceFullUVsAndIdentityOneToOnePlacement() async {
        let pass = isolatedPass()
        let image = consumer(pass)
        let changes: [(WritableKeyPath<ImagePrimitive, Float>, Float)] = [
            (\.screenW, 3), (\.screenH, 3), (\.screenW, .nan), (\.screenH, .infinity),
            (\.uvX, 0.25), (\.uvY, 0.25), (\.uvW, 0.5), (\.uvH, 0.5),
            (\.uvX, .nan), (\.uvY, .infinity), (\.uvW, .nan), (\.uvH, .infinity),
            (\.rotationRadians, 0.25), (\.rotationRadians, .nan),
            (\.affineA, 2), (\.affineB, 0.25), (\.affineC, 0.25), (\.affineD, 2),
            (\.affineA, .nan), (\.affineB, .infinity), (\.affineC, .nan), (\.affineD, .infinity),
        ]
        for (field, value) in changes {
            var invalid = image
            invalid[keyPath: field] = value
            XCTAssertNotNil(pass.isolatedBackdropImageDefect(invalid))
            XCTAssertNil(pass.isolatedBackdropMapping(for: invalid, parentSize: IntSize(width: 8, height: 8)))
            XCTAssertTrue(hasPassDefect(defects(pass, invalid)))
        }
        var wrongID = image
        wrongID.textureID += 1
        XCTAssertNotNil(pass.isolatedBackdropImageDefect(wrongID))
        XCTAssertNil(pass.isolatedBackdropMapping(for: wrongID, parentSize: IntSize(width: 8, height: 8)))

        var negative = pass
        negative.textureID = -1
        XCTAssertTrue(hasPassDefect(defects(negative, consumer(negative))))
        XCTAssertNil(
            negative.isolatedBackdropMapping(for: consumer(negative), parentSize: IntSize(width: 8, height: 8)))
    }

    func testConsumerRejectsCapsTilesAndNoncanonicalLegacyFields() async {
        let pass = isolatedPass()
        let image = consumer(pass)
        let fields: [WritableKeyPath<ImagePrimitive, Float>] = [
            \.sourceCapLeft, \.sourceCapTop, \.sourceCapRight, \.sourceCapBottom,
            \.destinationCapLeft, \.destinationCapTop, \.destinationCapRight, \.destinationCapBottom,
            \.centerRepeatX, \.centerRepeatY, \.samplingPadding,
        ]
        for field in fields {
            var invalid = image
            invalid[keyPath: field] += 0.25
            XCTAssertNotNil(pass.isolatedBackdropImageDefect(invalid))
            XCTAssertNil(pass.isolatedBackdropMapping(for: invalid, parentSize: IntSize(width: 8, height: 8)))
            XCTAssertTrue(hasPassDefect(defects(pass, invalid)))
        }
        for kind in [Int32(1), 2, -1, .max] {
            var invalid = image
            invalid.samplingKind = kind
            XCTAssertNotNil(pass.isolatedBackdropImageDefect(invalid))
            XCTAssertNil(pass.isolatedBackdropMapping(for: invalid, parentSize: IntSize(width: 8, height: 8)))
            XCTAssertTrue(hasPassDefect(defects(pass, invalid)))
        }
        XCTAssertEqual(ImagePrimitive.byteSize, 128)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.stride, 128)
    }

    func testSourceRequiresTransparentClearBoundedRadiusAndNoPostFilters() async {
        let pass = isolatedPass()
        let image = consumer(pass)
        let parentSize = IntSize(width: 8, height: 8)
        for clear in [Color.black, Color(red: 1, green: 0, blue: 0, alpha: 0)] {
            var invalid = pass
            invalid.scene.clearColor = clear
            XCTAssertNotNil(invalid.isolatedBackdropSourceDefect)
            XCTAssertNil(invalid.isolatedBackdropMapping(for: image, parentSize: parentSize))
            XCTAssertTrue(hasPassDefect(defects(invalid, image)))
        }
        var filtered = pass
        filtered.colorEffects = [.brightness(0)]
        XCTAssertNotNil(filtered.isolatedBackdropSourceDefect, "Even identity filter chains are outside this contract")
        XCTAssertNil(filtered.isolatedBackdropMapping(for: image, parentSize: parentSize))
        XCTAssertTrue(hasPassDefect(defects(filtered, image)))

        for radius in [Int32.min, -1, Int32(GPUISceneLimits.maxBlurRadius) + 1, .max] {
            var invalid = pass
            invalid.contentBlurRadius = radius
            XCTAssertNotNil(invalid.isolatedBackdropSourceDefect)
            XCTAssertNil(invalid.isolatedBackdropMapping(for: image, parentSize: parentSize))
            XCTAssertTrue(hasPassDefect(defects(invalid, image)))
        }
        for radius in [Int32(0), Int32(GPUISceneLimits.maxBlurRadius)] {
            let valid = isolatedPass(radius: radius)
            XCTAssertNil(valid.isolatedBackdropSourceDefect)
            XCTAssertNotNil(valid.isolatedBackdropMapping(for: consumer(valid), parentSize: parentSize))
            XCTAssertTrue(defects(valid, consumer(valid)).isEmpty)
        }
    }

    func testOtherInputsKeepZeroRadiusAndCurrentTargetMappingContracts() async {
        let size = IntSize(width: 3, height: 3)
        let parentSize = IntSize(width: 8, height: 8)
        for input in [GPUISceneImageRenderPassInput.independent, .currentTarget] {
            var pass = GPUISceneImageRenderPass(
                textureID: 7, scene: GPUIScene(clearColor: .clear), size: size, input: input)
            let image = consumer(pass, x: 2, y: 2)
            XCTAssertEqual(pass.contentBlurRadius, 0)
            XCTAssertTrue(defects(pass, image).isEmpty)
            XCTAssertNil(pass.isolatedBackdropMapping(for: image, parentSize: parentSize))
            pass.contentBlurRadius = 1
            XCTAssertTrue(hasPassDefect(defects(pass, image)))
            XCTAssertNil(pass.currentTargetRegion(for: image, parentSize: parentSize))
        }

        let pass = GPUISceneImageRenderPass(
            textureID: 7, scene: GPUIScene(clearColor: .clear), size: size, input: .currentTarget)
        XCTAssertEqual(
            pass.currentTargetRegion(for: consumer(pass, x: 2, y: 2), parentSize: parentSize),
            SubTextureRegion(originX: 2, originY: 2, width: 3, height: 3, textureWidth: 8, textureHeight: 8))
        for image in [consumer(pass, x: -2), consumer(pass, x: 1), consumer(pass, x: 6)] {
            XCTAssertNil(pass.currentTargetRegion(for: image, parentSize: parentSize))
        }
        XCTAssertEqual(
            pass.currentTargetImageDefect(consumer(pass, x: -2)),
            "current-target images require bounded nonnegative even pixel origins")
        var opaque = pass
        opaque.scene.clearColor = .black
        XCTAssertEqual(
            opaque.currentTargetSourceDefect, "current-target sources must declare a transparent clear color")
        var filtered = pass
        filtered.colorEffects = [.brightness(0)]
        XCTAssertEqual(filtered.currentTargetSourceDefect, "current-target sources do not support post-filter chains")
    }

    func testInvalidExtentsRejectMappingAndLeaveReservationCountersUnchanged() async {
        let sizes = [
            IntSize(width: 0, height: 2), IntSize(width: 2, height: 0),
            IntSize(width: -1, height: 2), IntSize(width: 2, height: -1),
            IntSize(width: 2049, height: 2048),
            IntSize(width: Int32(GPUISceneLimits.maxSurfaceDimension + 1), height: 1),
            IntSize(width: 1, height: Int32(GPUISceneLimits.maxSurfaceDimension + 1)),
            IntSize(width: .max, height: .max), IntSize(width: .min, height: .min),
        ]
        for size in sizes {
            let pass = isolatedPass(size: size)
            var budget = GPUISceneImageRenderPassBudget(maxPasses: 2, maxPixels: 64)
            XCTAssertFalse(pass.hasValidExtent)
            XCTAssertFalse(budget.consume(pass))
            XCTAssertEqual(budget.remainingPasses, 2)
            XCTAssertEqual(budget.remainingPixels, 64)
            XCTAssertNil(pass.isolatedBackdropMapping(for: consumer(pass), parentSize: IntSize(width: 8, height: 8)))
            XCTAssertTrue(defects(pass, consumer(pass)).contains { $0.description.contains("extent") })
        }
    }

    func testReservationsChargeEightPlanesAtomicallyAtEveryDependentOccurrence() async {
        let pass = isolatedPass()
        XCTAssertEqual(GPUISceneBackdropIsolationLimits.scratchPlaneCount, 8)
        var short = GPUISceneImageRenderPassBudget(maxPasses: 2, maxPixels: 63)
        XCTAssertTrue(short.consume(pass))
        XCTAssertEqual(short.remainingPasses, 1)
        XCTAssertEqual(short.remainingPixels, 31)
        XCTAssertFalse(short.consume(pass), "The same texture ID still realizes a fresh backdrop on its next use")
        XCTAssertEqual(short.remainingPasses, 1)
        XCTAssertEqual(short.remainingPixels, 31)

        var exact = GPUISceneImageRenderPassBudget(maxPasses: 2, maxPixels: 64)
        XCTAssertTrue(exact.consume(pass))
        XCTAssertTrue(exact.consume(pass))
        XCTAssertEqual(exact.remainingPasses, 0)
        XCTAssertEqual(exact.remainingPixels, 0)
        XCTAssertFalse(exact.consume(pass))

        var countLimited = GPUISceneImageRenderPassBudget(maxPasses: 1, maxPixels: 64)
        XCTAssertTrue(countLimited.consume(pass))
        XCTAssertFalse(countLimited.consume(pass))
        XCTAssertEqual(countLimited.remainingPasses, 0)
        XCTAssertEqual(countLimited.remainingPixels, 32)

        let largest = isolatedPass(size: IntSize(width: 2048, height: 2048))
        var full = GPUISceneImageRenderPassBudget(maxPasses: .max, maxPixels: .max)
        XCTAssertTrue(largest.hasValidExtent)
        XCTAssertFalse(full.consume(largest), "Eight scratch planes cannot fit by raising the existing frame ceiling")
        XCTAssertEqual(full.remainingPasses, 1024)
        XCTAssertEqual(full.remainingPixels, 16_777_216)
        XCTAssertTrue(
            defects(largest, consumer(largest)).contains { $0.description.contains("cumulative source pixels") })
    }

    func testNestedCurrentTargetChargesCoverageButIndependentPassKeepsItsOriginalCost() async {
        var pass = isolatedPass()
        pass.input = .currentTarget
        var nested = GPUISceneImageRenderPassBudget(maxPasses: 2, maxPixels: 64)
        XCTAssertTrue(nested.consume(pass, inBackdropIsolation: true))
        XCTAssertEqual(nested.remainingPasses, 1)
        XCTAssertEqual(nested.remainingPixels, 32)
        XCTAssertTrue(nested.consume(pass, inBackdropIsolation: true))
        XCTAssertEqual(nested.remainingPixels, 0)

        var ordinary = GPUISceneImageRenderPassBudget(maxPasses: 3, maxPixels: 12)
        XCTAssertTrue(ordinary.consume(pass))
        XCTAssertEqual(ordinary.remainingPixels, 8)
        pass.input = .independent
        XCTAssertTrue(ordinary.consume(pass, inBackdropIsolation: true))
        XCTAssertEqual(ordinary.remainingPixels, 4)
        XCTAssertTrue(ordinary.consume(size: pass.size))
        XCTAssertEqual(ordinary.remainingPasses, 0)
        XCTAssertEqual(ordinary.remainingPixels, 0)
    }

    func testStructuralReservationContextEntersInheritsAndResetsAtIndependentPasses() async {
        // These are declarations, never allocated surfaces. Two 1024-square
        // current-target children reserve 16,777,216 scratch pixels only inside isolation.
        let large = IntSize(width: 1024, height: 1024)
        let tiny = IntSize(width: 1, height: 1)
        let leaf = GPUIScene(clearColor: .clear)
        let inner = wrap(leaf, size: large, input: .currentTarget)
        let chain = wrap(inner, size: large, input: .currentTarget)
        XCTAssertTrue(chain.validate().isEmpty, "Ordinary current-target declarations retain their original cost")
        let isolated = wrap(chain, size: tiny, input: .isolatedBackdrop)
        XCTAssertTrue(isolated.validate().contains { $0.description.contains("cumulative source pixels") })

        let reset = wrap(wrap(chain, size: tiny, input: .independent), size: tiny, input: .isolatedBackdrop)
        XCTAssertTrue(reset.validate().isEmpty, "An independent child does not inherit enclosing backdrop state")
        let reentered = wrap(isolated, size: tiny, input: .independent)
        XCTAssertTrue(reentered.validate().contains { $0.description.contains("cumulative source pixels") })
    }

    func testIsolationKeepsExistingDepthAndCountCeilings() async {
        let tiny = IntSize(width: 1, height: 1)
        var nested = GPUIScene(clearColor: .clear)
        for _ in 0..<GPUISceneLimits.maxImageRenderPassDepth {
            nested = wrap(nested, size: tiny, input: .isolatedBackdrop)
        }
        XCTAssertTrue(nested.validate().isEmpty)
        XCTAssertTrue(
            wrap(nested, size: tiny, input: .isolatedBackdrop).validate().contains {
                $0.description.contains("nesting exceeds 32 passes")
            })

        var wide = GPUIScene(clearColor: .clear)
        for _ in 0..<GPUISceneLimits.maxImageRenderPassCount {
            wide.registerImageRenderPass(GPUIScene(clearColor: .clear), size: tiny, input: .isolatedBackdrop)
        }
        XCTAssertTrue(wide.validate().isEmpty)
        wide.registerImageRenderPass(GPUIScene(clearColor: .clear), size: tiny, input: .isolatedBackdrop)
        XCTAssertTrue(wide.validate().contains { $0.description.contains("image-pass count exceeds 1024") })
    }

    func testRegistrationTranslationAndReplayPreserveRadiusAndChildNamespace() async throws {
        let size = IntSize(width: 8, height: 8)
        var child = GPUIScene(clearColor: .clear)
        let childID = child.registerImageRenderPass(
            GPUIScene(clearColor: .clear), size: IntSize(width: 3, height: 5), input: .isolatedBackdrop,
            contentBlurRadius: 0)
        child.addImage(ImagePrimitive(screenW: 3, screenH: 5, textureID: childID))
        child.finish()

        var original = GPUIScene(clearColor: .clear)
        let originalID = original.registerImageRenderPass(
            child, size: size, input: .isolatedBackdrop, contentBlurRadius: 7)
        XCTAssertEqual(childID, originalID, "The child intentionally uses its own texture namespace")
        original.addImage(ImagePrimitive(screenX: -4, screenY: -4, screenW: 8, screenH: 8, textureID: originalID))
        original.finish()
        let translated = original.translatedPrimitives(by: Point(x: 2, y: 4))
        XCTAssertEqual(translated.imageRenderPasses, original.imageRenderPasses)

        var replay = GPUIScene(clearColor: .clear)
        let occupiedID = replay.registerImageResource(
            BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 255, 255])))
        XCTAssertEqual(occupiedID, originalID)
        XCTAssertEqual(replay.replay(0..<translated.paintRecordCount, from: translated), .success)
        replay.finish()
        let rebound = try XCTUnwrap(replay.imageRenderPasses.first)
        XCTAssertNotEqual(rebound.textureID, occupiedID)
        XCTAssertEqual(rebound.input, .isolatedBackdrop)
        XCTAssertEqual(rebound.contentBlurRadius, 7)
        XCTAssertEqual(rebound.scene, child)
        XCTAssertEqual(rebound.scene.imageRenderPasses.first?.textureID, childID)
        XCTAssertEqual(rebound.scene.imageRenderPasses.first?.contentBlurRadius, 0)
        let image = try XCTUnwrap(replay.layers.flatMap(\.images).first)
        XCTAssertEqual(image.textureID, rebound.textureID)
        XCTAssertEqual(image.screenX, -2)
        XCTAssertEqual(image.screenY, 0)
        XCTAssertNotNil(rebound.isolatedBackdropMapping(for: image, parentSize: IntSize(width: 16, height: 16)))
        XCTAssertTrue(replay.validate().isEmpty)

        var changed = rebound
        changed.contentBlurRadius = 6
        XCTAssertNotEqual(changed, rebound, "Replay/cache equality includes the content-filter radius")
    }

    private func isolatedPass(
        size: IntSize = IntSize(width: 2, height: 2), radius: Int32 = 0
    ) -> GPUISceneImageRenderPass {
        GPUISceneImageRenderPass(
            textureID: 7, scene: GPUIScene(clearColor: .clear), size: size,
            input: .isolatedBackdrop, contentBlurRadius: radius)
    }

    private func consumer(_ pass: GPUISceneImageRenderPass, x: Float = 0, y: Float = 0) -> ImagePrimitive {
        ImagePrimitive(
            screenX: x, screenY: y, screenW: Float(pass.size.width), screenH: Float(pass.size.height),
            textureID: pass.textureID)
    }

    private func defects(_ pass: GPUISceneImageRenderPass, _ image: ImagePrimitive) -> [SceneDefect] {
        // Bypass sanitation so malformed consumer fields remain observable.
        var scene = GPUIScene(clearColor: .clear, imageRenderPasses: [pass])
        scene.installHandBuiltLayers([
            GPUILayer(images: [image], paintOperations: [GPUIPaintOperation(kind: .image, startIndex: 0)])
        ])
        return scene.validate()
    }

    private func hasPassDefect(_ defects: [SceneDefect]) -> Bool {
        defects.contains {
            if case .invalidImageRenderPass = $0.kind { return true }
            return false
        }
    }

    private func wrap(_ child: GPUIScene, size: IntSize, input: GPUISceneImageRenderPassInput) -> GPUIScene {
        GPUIScene(
            clearColor: .clear,
            imageRenderPasses: [GPUISceneImageRenderPass(textureID: 0, scene: child, size: size, input: input)])
    }
}
