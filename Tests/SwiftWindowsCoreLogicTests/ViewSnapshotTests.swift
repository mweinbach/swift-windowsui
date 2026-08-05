import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

final class ViewSnapshotTests: XCTestCase {

    func testRendersSolidColorRectangle() async throws {
        try await MainActor.run {
            let bitmap = try ViewSnapshot.rasterize(
                component: UI.panel(
                    frame: Rect(origin: .zero, size: Size(width: 100, height: 50)),
                    backgroundColor: .red
                ),
                size: Size(width: 110, height: 60),
                clearColor: .black
            )

            XCTAssertEqual(bitmap.width, 110)
            XCTAssertEqual(bitmap.height, 60)

            // Center pixel inside the red rect should match the semantic system red.
            let center = bitmap.pixelColor(atX: 50, y: 25)
            XCTAssertNotNil(center)
            XCTAssertEqual(Double(center?.red ?? 0), Double(Color.red.red), accuracy: 0.01)
            XCTAssertEqual(Double(center?.green ?? 0), Double(Color.red.green), accuracy: 0.01)
            XCTAssertEqual(Double(center?.blue ?? 0), Double(Color.red.blue), accuracy: 0.01)
            XCTAssertEqual(Double(center?.alpha ?? 0), Double(Color.red.alpha), accuracy: 0.01)

            // Corner pixel outside the rect should be black (clear color)
            let corner = bitmap.pixelColor(atX: 105, y: 55)
            XCTAssertNotNil(corner)
            XCTAssertEqual(Double(corner?.red ?? 0), 0, accuracy: 0.01)
            XCTAssertEqual(Double(corner?.green ?? 0), 0, accuracy: 0.01)
            XCTAssertEqual(Double(corner?.blue ?? 0), 0, accuracy: 0.01)
        }
    }

    func testRendersGradientRectangle() async throws {
        try await MainActor.run {
            let bitmap = try ViewSnapshot.rasterize(
                component: UI.panel(
                    frame: Rect(origin: .zero, size: Size(width: 100, height: 50)),
                    backgroundGradient: .linear(
                        LinearGradient(
                            startColor: .blue,
                            endColor: .green,
                            axis: .horizontal
                        ))
                ),
                size: Size(width: 100, height: 50),
                clearColor: .white
            )

            // Left edge should be blue-ish
            let left = bitmap.pixelColor(atX: 5, y: 25)
            XCTAssertGreaterThan(left?.blue ?? 0, 0.5)

            // Right edge should be green-ish
            let right = bitmap.pixelColor(atX: 95, y: 25)
            XCTAssertGreaterThan(right?.green ?? 0, 0.5)
        }
    }

    func testRendersRoundedCorners() async throws {
        try await MainActor.run {
            let bitmap = try ViewSnapshot.rasterize(
                component: UI.panel(
                    frame: Rect(origin: .zero, size: Size(width: 40, height: 40)),
                    backgroundColor: .white,
                    cornerRadius: 10
                ),
                size: Size(width: 40, height: 40),
                clearColor: .black
            )

            // Center should be white
            let center = bitmap.pixelColor(atX: 20, y: 20)
            XCTAssertEqual(Double(center?.red ?? 0), 1, accuracy: 0.05)

            // Very corner should be black (clear color, clipped by rounded corner)
            let extremeCorner = bitmap.pixelColor(atX: 1, y: 1)
            XCTAssertEqual(Double(extremeCorner?.red ?? 0), 0, accuracy: 0.05)
        }
    }

    func testProducesValidBMPFile() async throws {
        try await MainActor.run {
            let bitmap = try ViewSnapshot.rasterize(
                component: UI.panel(
                    frame: Rect(origin: .zero, size: Size(width: 8, height: 8)),
                    backgroundColor: .white
                ),
                size: Size(width: 8, height: 8),
                clearColor: .black
            )

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("swift_windows_ui_test.bmp")
            try bitmap.writeBMP(to: tempURL)

            let data = try Data(contentsOf: tempURL)
            // BMP magic bytes
            XCTAssertEqual(data.prefix(2), Data([0x42, 0x4D]))
            // Pixel offset at bytes 10-13
            let pixelOffset = data.subdata(in: 10..<14).withUnsafeBytes { $0.load(as: Int32.self) }
            XCTAssertEqual(pixelOffset, 54)  // 14 + 40

            // Clean up
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    func testRendersTextAsNonTransparentPixels() async throws {
        try await MainActor.run {
            let bitmap = try ViewSnapshot.rasterize(
                component: UI.label("A"),
                size: Size(width: 32, height: 32),
                clearColor: .black
            )

            // At least some pixel should be non-black (the glyph)
            var foundGlyph = false
            for y in 0..<Int(bitmap.height) {
                for x in 0..<Int(bitmap.width) {
                    if let color = bitmap.pixelColor(atX: x, y: y),
                        color.red > 0.1 || color.green > 0.1 || color.blue > 0.1
                    {
                        foundGlyph = true
                        break
                    }
                }
                if foundGlyph { break }
            }
            XCTAssertTrue(foundGlyph, "Expected at least one non-black pixel from text rendering")
        }
    }

    func testOffsetShiftsRenderedPixels() async throws {
        try await MainActor.run {
            let bitmap = try ViewSnapshot.rasterize(
                component: UI.panel(
                    frame: Rect(origin: .zero, size: Size(width: 20, height: 20)),
                    backgroundColor: .white
                )
                .offset(x: 10, y: 5),
                size: Size(width: 40, height: 40),
                clearColor: .black
            )

            // Before offset, rect is at (0,0); after offset it should be at (10,5)
            let insideOffset = bitmap.pixelColor(atX: 15, y: 10)
            XCTAssertEqual(Double(insideOffset?.red ?? 0), 1, accuracy: 0.05)

            // Original position should now be clear color
            let originalCenter = bitmap.pixelColor(atX: 5, y: 5)
            XCTAssertEqual(Double(originalCenter?.red ?? 0), 0, accuracy: 0.05)
        }
    }

    func testScaleEffectScalesRenderedPixels() async throws {
        try await MainActor.run {
            let bitmap = try ViewSnapshot.rasterize(
                component: UI.panel(
                    frame: Rect(origin: .zero, size: Size(width: 20, height: 20)),
                    backgroundColor: .white
                )
                .scaleEffect(x: 2, y: 2),
                size: Size(width: 60, height: 60),
                clearColor: .black
            )

            // Scaled 2x from 20x20 centered at 10,10 → covers roughly (-10,-10) to (30,30)
            let insideScaled = bitmap.pixelColor(atX: 15, y: 15)
            XCTAssertEqual(Double(insideScaled?.red ?? 0), 1, accuracy: 0.05)

            // Outside scaled bounds should be clear color
            let outsideScaled = bitmap.pixelColor(atX: 50, y: 50)
            XCTAssertEqual(Double(outsideScaled?.red ?? 0), 0, accuracy: 0.05)
        }
    }

    /// A snapshot of a host's *first* build shows the view, not the first
    /// frame of a fade it should never have played.
    ///
    /// These two used to assert the opposite — an invisible centre pixel —
    /// which was the bug rather than the contract: `reload()` fired an
    /// insertion transition for every transition-bearing node in a window's
    /// initial tree, because `applyNewNodeTransitionsRecursively` keys off
    /// `!hasAppeared` and on a first build nothing has appeared. SwiftUI plays
    /// a transition on insertion *into* a container, not on the container's own
    /// first render, and a snapshot renderer is the clearest case: it builds
    /// once and rasterises, so under the old rule every `.transition()` in an
    /// offscreen render came out at its "from" value.
    ///
    /// The insertion case — where these values *are* correct — is driven
    /// through a live host in `InteractionTimelineFidelityTests`.
    func testTransitionOpacityDoesNotPlayOnAFirstBuild() async throws {
        try await MainActor.run {
            let bitmap = try ViewSnapshot.rasterize(
                component: Component { _ in
                    let node = ViewNode(
                        frame: Rect(origin: .zero, size: Size(width: 20, height: 20)),
                        backgroundColor: .white,
                        transition: RetainedTransition(kind: .opacity)
                    )
                    return node
                },
                size: Size(width: 30, height: 30),
                clearColor: .black
            )

            let center = bitmap.pixelColor(atX: 10, y: 10)
            XCTAssertEqual(Double(center?.red ?? 0), 1, accuracy: 0.05)
        }
    }

    func testTransitionScaleDoesNotPlayOnAFirstBuild() async throws {
        try await MainActor.run {
            let bitmap = try ViewSnapshot.rasterize(
                component: Component { _ in
                    let node = ViewNode(
                        frame: Rect(origin: .zero, size: Size(width: 20, height: 20)),
                        backgroundColor: .white,
                        transition: RetainedTransition(kind: .scale(scaleX: 0, scaleY: 0, anchorX: 0.5, anchorY: 0.5))
                    )
                    return node
                },
                size: Size(width: 30, height: 30),
                clearColor: .black
            )

            let center = bitmap.pixelColor(atX: 10, y: 10)
            XCTAssertEqual(Double(center?.red ?? 0), 1, accuracy: 0.05)
        }
    }
}
