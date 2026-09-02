import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics

final class OriginalAnchorClipSanitationTests: XCTestCase {
    func testDefaultClipExtensionFieldsStayAbsentAndZero() {
        let fixture = PackedFixture()
        XCTAssertTrue(fixture.shapes.allSatisfy { $0 == nil })
        XCTAssertEqual(fixture.rawShapes, Array(repeating: [0, 0, 0, 0], count: 4))
        XCTAssertEqual(fixture.radii, Array(repeating: [0, 0, 0, 0], count: 4))
        let path = rectanglePath()
        XCTAssertNil(path.clipShapeBounds)
        XCTAssertEqual(pathRadii(path), [0, 0, 0, 0])
    }

    func testTypedEmptyAnchorsStayExplicitAndAreRejected() {
        for shape in [
            Rect(x: 0, y: 0, width: 0, height: 0),
            Rect(x: 4, y: 6, width: 0, height: 0),
            Rect(x: 0, y: 0, width: 0, height: 10),
            Rect(x: 0, y: 0, width: 10, height: -1),
        ] {
            var fixture = PackedFixture()
            fixture.setShape(shape)
            XCTAssertTrue(fixture.shapes.allSatisfy { $0 != nil })
            for raw in fixture.rawShapes {
                XCTAssertEqual(raw[2], GPUIClipEncoding.emptyExtent)
                XCTAssertEqual(raw[3], GPUIClipEncoding.emptyExtent)
            }
            assertRejected(fixture)
            fixture.setRejection(Rect(x: 0, y: 0, width: 10, height: 10))
            assertRejected(fixture)
        }
    }

    func testTypedPositiveExtentsCannotUnderflowIntoAbsentAnchor() {
        for shape in [
            Rect(x: 0, y: 0, width: 1e-100, height: 1e-100),
            Rect(x: 0, y: 0, width: 1e-100, height: 10),
            Rect(x: 0, y: 0, width: 10, height: 1e-100),
        ] {
            var fixture = PackedFixture()
            fixture.setShape(shape)
            XCTAssertTrue(fixture.shapes.allSatisfy { $0 != nil })
            for raw in fixture.rawShapes {
                XCTAssertEqual(raw[2], GPUIClipEncoding.emptyExtent)
                XCTAssertEqual(raw[3], GPUIClipEncoding.emptyExtent)
            }
            assertRejected(fixture)
            fixture.setRejection(Rect(x: 0, y: 0, width: 10, height: 10))
            assertRejected(fixture)
        }
    }

    func testTinyRepresentableFloatAnchorStaysExplicit() throws {
        let extent = Double(Float.leastNonzeroMagnitude)
        let shape = Rect(x: 0, y: 0, width: extent, height: extent)
        var fixture = PackedFixture()
        fixture.setShape(shape)
        let stored = try fixture.sanitized()
        XCTAssertEqual(stored.shapes, Array(repeating: Optional(shape), count: 4))
        XCTAssertEqual(stored.scene.paintRecordCount, 5)
    }

    func testTypedOverflowAndNonFiniteAnchorsAreRejected() {
        for shape in [
            Rect(x: Double.nan, y: 0, width: 10, height: 10),
            Rect(x: 0, y: Double.infinity, width: 10, height: 10),
            Rect(x: 0, y: 0, width: Double.infinity, height: 10),
            Rect(x: 0, y: 0, width: 10, height: Double.nan),
            Rect(x: Double.greatestFiniteMagnitude, y: 0, width: 10, height: 10),
            Rect(x: 0, y: 0, width: Double.greatestFiniteMagnitude, height: 10),
        ] {
            var fixture = PackedFixture()
            fixture.setShape(shape)
            XCTAssertTrue(fixture.shapes.allSatisfy { $0 != nil })
            assertRejected(fixture)
        }
    }

    func testRawNonFiniteAnchorsAreRejectedEvenWithoutRejectionClip() {
        for component in 0..<4 {
            for bad in [Float.nan, .infinity, -.infinity] {
                for active in [false, true] {
                    var raw: [Float] = [0, 0, 10, 10]
                    raw[component] = bad
                    var fixture = PackedFixture()
                    fixture.setRawShape(raw)
                    fixture.setRejection(active ? Rect(x: 0, y: 0, width: 10, height: 10) : nil)
                    assertRejected(fixture)
                }
            }
        }
    }

    func testRawCollapsedAnchorsAreRejectedExceptExactAbsentSentinel() {
        let invalid: [[Float]] = [
            [0, 0, -1, -1], [3, 4, 0, 0], [0, 0, 0, 10],
            [0, 0, 10, 0], [0, 0, -2, 10], [0, 0, 10, -2],
        ]
        for raw in invalid {
            for active in [false, true] {
                var fixture = PackedFixture()
                fixture.setRawShape(raw)
                fixture.setRejection(active ? Rect(x: 0, y: 0, width: 10, height: 10) : nil)
                assertRejected(fixture)
            }
        }
        XCTAssertEqual(PackedFixture().scene.paintRecordCount, 5)
    }

    func testFourFloatRadiiRetainExistingFinitePolicyInEveryFamily() throws {
        let limit = GPUISceneLimits.maxCoordinate
        let cases: [(Float, Float)] = [
            (.nan, 0), (.infinity, limit), (-.infinity, 0), (-8, 0), (1e30, limit), (7, 7),
        ]
        for (input, expected) in cases {
            var fixture = PackedFixture()
            fixture.setShape(Rect(x: 0, y: 0, width: 10, height: 10))
            fixture.setRadii(Array(repeating: input, count: 4))
            let stored = try fixture.sanitized()
            XCTAssertEqual(stored.radii, Array(repeating: Array(repeating: expected, count: 4), count: 4))
        }
    }

    func testFourPathRadiiRetainDoubleNonFiniteToZeroPolicy() throws {
        let cases: [(Double, Double)] = [
            (.nan, 0), (.infinity, 0), (-.infinity, 0), (-8, 0),
            (1e30, Double(GPUISceneLimits.maxCoordinate)), (7, 7),
        ]
        for (input, expected) in cases {
            var path = rectanglePath()
            path.clipCornerRadius = input
            path.clipCornerRadiusTopLeft = input
            path.clipCornerRadiusTopRight = input
            path.clipCornerRadiusBottomRight = input
            path.clipCornerRadiusBottomLeft = input
            let stored = try XCTUnwrap(GPUISceneSanitizer.sanitized(path))
            XCTAssertEqual(pathRadii(stored), Array(repeating: expected, count: 4))
            XCTAssertEqual(stored.clipCornerRadius, expected)
        }
    }

    func testWellFormedAnchorsAndRadiiSurviveAdmissionIdentically() throws {
        var fixture = PackedFixture()
        fixture.setRejection(Rect(x: 0, y: 0, width: 10, height: 10))
        fixture.setShape(Rect(x: 0.25, y: 1.5, width: 100.75, height: 80.25))
        fixture.setRadii([3, 0, 7, 11])
        XCTAssertEqual(try fixture.sanitized(), fixture)
        let scene = fixture.scene
        XCTAssertEqual(scene.paintRecordCount, 5)
        XCTAssertEqual(scene.layers[0].quads.first, fixture.quad)
        XCTAssertEqual(scene.layers[0].glyphs.first, fixture.glyph)
        XCTAssertEqual(scene.layers[0].pixelGlyphs.first, fixture.glyph)
        XCTAssertEqual(scene.layers[0].images.first, fixture.image)
        XCTAssertEqual(scene.layers[0].shadows.first, fixture.shadow)

        var path = rectanglePath()
        path.clipBounds = Rect(x: 0, y: 0, width: 10, height: 10)
        path.clipShapeBounds = Rect(x: 0.25, y: 1.5, width: 100.75, height: 80.25)
        path.clipCornerRadiusTopLeft = 3
        path.clipCornerRadiusBottomRight = 7
        XCTAssertEqual(GPUISceneSanitizer.sanitized(path), path)
    }

    func testValidAnchorWithAbsentPackedClipIsRetained() throws {
        let shape = Rect(x: 20, y: 20, width: 60, height: 60)
        var fixture = PackedFixture()
        fixture.setShape(shape)
        fixture.setRadii([40, 0, 8, 0])
        let stored = try fixture.sanitized()
        XCTAssertEqual(stored.shapes, Array(repeating: Optional(shape), count: 4))
        XCTAssertEqual(stored.scene.paintRecordCount, 5)
        XCTAssertNil(stored.quad.contentMask.bounds)
        XCTAssertNil(stored.glyph.contentMask.bounds)
        XCTAssertNil(stored.image.contentMask.bounds)
        XCTAssertNil(stored.shadow.contentMask.bounds)
    }

    func testLaterLegacyWritesDoNotMaterializeDefaultAnchorOrRadii() throws {
        var fixture = PackedFixture()
        fixture.quad.clipCornerRadius = 12
        fixture.glyph.clipCornerRadius = 12
        fixture.image.clipCornerRadius = 12
        fixture.shadow.clipCornerRadius = 12
        let rejection = Rect(x: 4, y: 6, width: 8, height: 10)
        fixture.setRejection(rejection)
        let stored = try fixture.sanitized()
        XCTAssertTrue(stored.shapes.allSatisfy { $0 == nil })
        XCTAssertEqual(stored.rawShapes, Array(repeating: [0, 0, 0, 0], count: 4))
        XCTAssertEqual(stored.radii, Array(repeating: [0, 0, 0, 0], count: 4))
        XCTAssertEqual(stored.quad.contentMask.bounds, rejection)
        XCTAssertEqual(stored.glyph.contentMask.bounds, rejection)
        XCTAssertEqual(stored.image.contentMask.bounds, rejection)
        XCTAssertEqual(stored.shadow.contentMask.bounds, rejection)
        XCTAssertEqual(
            [
                stored.quad.clipCornerRadius, stored.glyph.clipCornerRadius,
                stored.image.clipCornerRadius, stored.shadow.clipCornerRadius,
            ], [12, 12, 12, 12])
    }

    func testExplicitShapeCoordinatesUseExistingCoordinateLimits() throws {
        var fixture = PackedFixture()
        fixture.setRawShape([1e30, -1e30, 1e30, 1e30])
        let stored = try fixture.sanitized()
        let limit = GPUISceneLimits.maxCoordinate
        XCTAssertEqual(stored.rawShapes, Array(repeating: [limit, -limit, limit, limit], count: 4))
    }

    func testPathRejectsPresentEmptyOrNonFiniteAnchorEvenWithNilClipBounds() {
        let invalid = [
            Rect(x: 0, y: 0, width: 0, height: 0),
            Rect(x: 2, y: 3, width: 0, height: 10),
            Rect(x: 0, y: 0, width: 10, height: -1),
            Rect(x: Double.nan, y: 0, width: 10, height: 10),
            Rect(x: 0, y: Double.infinity, width: 10, height: 10),
            Rect(x: 0, y: 0, width: Double.infinity, height: 10),
            Rect(x: 0, y: 0, width: 10, height: Double.nan),
        ]
        for shape in invalid {
            for rejection in [Optional(Rect(x: 0, y: 0, width: 10, height: 10)), nil] {
                var path = rectanglePath()
                path.clipBounds = rejection
                path.clipShapeBounds = shape
                XCTAssertNil(GPUISceneSanitizer.sanitized(path))
                var scene = GPUIScene()
                scene.addPath(path, toLayer: 0)
                XCTAssertEqual(scene.paintRecordCount, 0)
            }
        }
    }

    func testPathTinyAnchorKeepsPresenceUntilCheckedFloatTransport() throws {
        let shape = Rect(x: 0, y: 0, width: 1e-100, height: 1e-100)
        var path = rectanglePath()
        path.clipShapeBounds = shape
        let stored = try XCTUnwrap(GPUISceneSanitizer.sanitized(path))
        XCTAssertEqual(stored.clipShapeBounds, shape)
        let image = ImagePrimitive(screenW: 10, screenH: 10, clipShapeBounds: stored.clipShapeBounds)
        XCTAssertNotNil(image.clipShapeBounds)
        XCTAssertEqual(image.clipShapeWidth, GPUIClipEncoding.emptyExtent)
        XCTAssertEqual(image.clipShapeHeight, GPUIClipEncoding.emptyExtent)
        XCTAssertNil(GPUISceneSanitizer.sanitized(image))
    }

    private func assertRejected(
        _ fixture: PackedFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertNil(GPUISceneSanitizer.sanitized(fixture.quad), file: file, line: line)
        XCTAssertNil(GPUISceneSanitizer.sanitized(fixture.glyph), file: file, line: line)
        XCTAssertNil(GPUISceneSanitizer.sanitized(fixture.image), file: file, line: line)
        XCTAssertNil(GPUISceneSanitizer.sanitized(fixture.shadow), file: file, line: line)
        XCTAssertEqual(fixture.scene.paintRecordCount, 0, file: file, line: line)
    }

    private func rectanglePath() -> PathPrimitive {
        PathPrimitive(
            elements: [
                .moveTo(Point(x: 0, y: 0)), .lineTo(Point(x: 10, y: 0)),
                .lineTo(Point(x: 10, y: 10)), .lineTo(Point(x: 0, y: 10)), .close,
            ],
            bounds: Rect(x: 0, y: 0, width: 10, height: 10), fillColor: .white)
    }

    private func pathRadii(_ path: PathPrimitive) -> [Double] {
        [
            path.clipCornerRadiusTopLeft, path.clipCornerRadiusTopRight,
            path.clipCornerRadiusBottomRight, path.clipCornerRadiusBottomLeft,
        ]
    }

    private struct PackedFixture: Equatable {
        var quad = QuadPrimitive(width: 10, height: 10)
        var glyph = GlyphPrimitive(screenW: 10, screenH: 10)
        var image = ImagePrimitive(screenW: 10, screenH: 10)
        var shadow = ShadowPrimitive(width: 10, height: 10, blurRadius: 0)

        var shapes: [Rect?] {
            [quad.clipShapeBounds, glyph.clipShapeBounds, image.clipShapeBounds, shadow.clipShapeBounds]
        }

        var rawShapes: [[Float]] {
            [
                [quad.clipShapeX, quad.clipShapeY, quad.clipShapeWidth, quad.clipShapeHeight],
                [glyph.clipShapeX, glyph.clipShapeY, glyph.clipShapeWidth, glyph.clipShapeHeight],
                [image.clipShapeX, image.clipShapeY, image.clipShapeWidth, image.clipShapeHeight],
                [shadow.clipShapeX, shadow.clipShapeY, shadow.clipShapeWidth, shadow.clipShapeHeight],
            ]
        }

        var radii: [[Float]] {
            [
                [
                    quad.clipCornerRadiusTopLeft, quad.clipCornerRadiusTopRight,
                    quad.clipCornerRadiusBottomRight, quad.clipCornerRadiusBottomLeft,
                ],
                [
                    glyph.clipCornerRadiusTopLeft, glyph.clipCornerRadiusTopRight,
                    glyph.clipCornerRadiusBottomRight, glyph.clipCornerRadiusBottomLeft,
                ],
                [
                    image.clipCornerRadiusTopLeft, image.clipCornerRadiusTopRight,
                    image.clipCornerRadiusBottomRight, image.clipCornerRadiusBottomLeft,
                ],
                [
                    shadow.clipCornerRadiusTopLeft, shadow.clipCornerRadiusTopRight,
                    shadow.clipCornerRadiusBottomRight, shadow.clipCornerRadiusBottomLeft,
                ],
            ]
        }

        var scene: GPUIScene {
            var result = GPUIScene()
            result.addQuad(quad)
            result.addGlyph(glyph)
            result.addPixelGlyph(glyph)
            result.addImage(image)
            result.addShadow(shadow)
            return result
        }

        mutating func setShape(_ shape: Rect?) {
            quad.clipShapeBounds = shape
            glyph.clipShapeBounds = shape
            image.clipShapeBounds = shape
            shadow.clipShapeBounds = shape
        }

        mutating func setRejection(_ bounds: Rect?) {
            let mask = GPUIContentMask(bounds: bounds)
            quad.contentMask = mask
            glyph.contentMask = mask
            image.contentMask = mask
            shadow.contentMask = mask
        }

        mutating func setRawShape(_ raw: [Float]) {
            quad.clipShapeX = raw[0]
            quad.clipShapeY = raw[1]
            quad.clipShapeWidth = raw[2]
            quad.clipShapeHeight = raw[3]
            glyph.clipShapeX = raw[0]
            glyph.clipShapeY = raw[1]
            glyph.clipShapeWidth = raw[2]
            glyph.clipShapeHeight = raw[3]
            image.clipShapeX = raw[0]
            image.clipShapeY = raw[1]
            image.clipShapeWidth = raw[2]
            image.clipShapeHeight = raw[3]
            shadow.clipShapeX = raw[0]
            shadow.clipShapeY = raw[1]
            shadow.clipShapeWidth = raw[2]
            shadow.clipShapeHeight = raw[3]
        }

        mutating func setRadii(_ values: [Float]) {
            quad.clipCornerRadiusTopLeft = values[0]
            quad.clipCornerRadiusTopRight = values[1]
            quad.clipCornerRadiusBottomRight = values[2]
            quad.clipCornerRadiusBottomLeft = values[3]
            glyph.clipCornerRadiusTopLeft = values[0]
            glyph.clipCornerRadiusTopRight = values[1]
            glyph.clipCornerRadiusBottomRight = values[2]
            glyph.clipCornerRadiusBottomLeft = values[3]
            image.clipCornerRadiusTopLeft = values[0]
            image.clipCornerRadiusTopRight = values[1]
            image.clipCornerRadiusBottomRight = values[2]
            image.clipCornerRadiusBottomLeft = values[3]
            shadow.clipCornerRadiusTopLeft = values[0]
            shadow.clipCornerRadiusTopRight = values[1]
            shadow.clipCornerRadiusBottomRight = values[2]
            shadow.clipCornerRadiusBottomLeft = values[3]
        }

        func sanitized() throws -> PackedFixture {
            var result = self
            result.quad = try XCTUnwrap(GPUISceneSanitizer.sanitized(quad))
            result.glyph = try XCTUnwrap(GPUISceneSanitizer.sanitized(glyph))
            result.image = try XCTUnwrap(GPUISceneSanitizer.sanitized(image))
            result.shadow = try XCTUnwrap(GPUISceneSanitizer.sanitized(shadow))
            return result
        }
    }
}
