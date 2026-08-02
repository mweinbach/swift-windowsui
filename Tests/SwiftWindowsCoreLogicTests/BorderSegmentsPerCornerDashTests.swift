import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Pins the per-corner variant of `BorderSegments.dashedSegments`:
/// zero-radius corners contribute no arc region (dashed borders no longer
/// paint arcs at deliberately square corners), and four equal radii
/// produce exactly the same segments as the historic uniform variant —
/// both overloads share one dash walk, so uniform-radius output is
/// unchanged at rest.
final class BorderSegmentsPerCornerDashTests: XCTestCase {

    private static let frame = Rect(x: 10, y: 20, width: 120, height: 80)

    func testEqualRadiiMatchUniformVariantExactly() async {
        await MainActor.run {
            let frame = Self.frame
            let style = StrokeStyle(dashPattern: [8, 4])
            let uniform = BorderSegments.dashedSegments(
                frame: frame, width: 3, cornerRadius: 10, strokeStyle: style)
            let perCorner = BorderSegments.dashedSegments(
                frame: frame, width: 3,
                cornerRadii: RetainedCornerRadii(uniform: 10), strokeStyle: style)
            XCTAssertNotNil(uniform)
            XCTAssertEqual(uniform, perCorner)
        }
    }

    func testEqualRadiiMatchUniformVariantWithOffsetAndRoundCaps() async {
        await MainActor.run {
            let frame = Self.frame
            let style = StrokeStyle(dashPattern: [7, 3, 2, 3], dashOffset: 5, lineCap: .round)
            let uniform = BorderSegments.dashedSegments(
                frame: frame, width: 4, cornerRadius: 12, strokeStyle: style)
            let perCorner = BorderSegments.dashedSegments(
                frame: frame, width: 4,
                cornerRadii: RetainedCornerRadii(uniform: 12), strokeStyle: style)
            XCTAssertNotNil(uniform)
            XCTAssertEqual(uniform, perCorner)
        }
    }

    func testAllZeroRadiiMatchSquareUniformVariant() async {
        await MainActor.run {
            let frame = Self.frame
            let style = StrokeStyle(dashPattern: [8, 4])
            let uniform = BorderSegments.dashedSegments(
                frame: frame, width: 3, cornerRadius: 0, strokeStyle: style)
            let perCorner = BorderSegments.dashedSegments(
                frame: frame, width: 3,
                cornerRadii: RetainedCornerRadii(), strokeStyle: style)
            XCTAssertNotNil(uniform)
            XCTAssertEqual(uniform, perCorner)
        }
    }

    func testSquareCornersEmitNoArcSegments() async {
        await MainActor.run {
            let frame = Self.frame
            // Butt caps so only true arc pieces carry a pill corner radius
            // (edge segments get capRadius 0). Every quadrant is exercised:
            // the single rounded corner emits arc pieces, and they all stay
            // inside that corner's zone.
            let style = StrokeStyle(dashPattern: [6, 2], lineCap: .butt)
            let radius = 10.0
            let cases: [(name: String, radii: RetainedCornerRadii, zone: Rect)] = [
                (
                    "top-left", RetainedCornerRadii(topLeft: radius),
                    Rect(x: frame.minX, y: frame.minY, width: radius, height: radius)
                ),
                (
                    "top-right", RetainedCornerRadii(topRight: radius),
                    Rect(x: frame.maxX - radius, y: frame.minY, width: radius, height: radius)
                ),
                (
                    "bottom-right", RetainedCornerRadii(bottomRight: radius),
                    Rect(x: frame.maxX - radius, y: frame.maxY - radius, width: radius, height: radius)
                ),
                (
                    "bottom-left", RetainedCornerRadii(bottomLeft: radius),
                    Rect(x: frame.minX, y: frame.maxY - radius, width: radius, height: radius)
                ),
            ]

            for testCase in cases {
                let segments = BorderSegments.dashedSegments(
                    frame: frame, width: 3, cornerRadii: testCase.radii, strokeStyle: style)
                let pillSegments = (segments ?? []).filter { $0.cornerRadius > 0 }

                XCTAssertFalse(
                    pillSegments.isEmpty,
                    "the rounded \(testCase.name) corner must emit arc pieces")
                for segment in pillSegments {
                    let centre = Point(x: segment.rect.midX, y: segment.rect.midY)
                    XCTAssertTrue(
                        testCase.zone.contains(centre),
                        "arc piece \(segment.rect) outside the rounded \(testCase.name) corner zone")
                }
            }
        }
    }

    func testUniformRadiusEmitsArcSegmentsAtRoundedCorners() async {
        await MainActor.run {
            let frame = Self.frame
            // Contrast case for the square-corner pin: with a uniform
            // radius, pill (arc) segments appear in all four corner zones.
            // The bottom-left corner used to be exempt here — the shared
            // corner-arc bounding box assumed the ring's outer side lay at
            // +x/-y, which dropped pieces in the positive-sin quadrants —
            // and is now held to the same bar as the rest.
            let style = StrokeStyle(dashPattern: [6, 2], lineCap: .butt)
            let segments =
                BorderSegments.dashedSegments(
                    frame: frame, width: 3, cornerRadius: 10, strokeStyle: style
                ) ?? []
            let pillSegments = segments.filter { $0.cornerRadius > 0 }
            let zones = [
                Rect(x: frame.minX, y: frame.minY, width: 10, height: 10),
                Rect(x: frame.maxX - 10, y: frame.minY, width: 10, height: 10),
                Rect(x: frame.maxX - 10, y: frame.maxY - 10, width: 10, height: 10),
                Rect(x: frame.minX, y: frame.maxY - 10, width: 10, height: 10),
            ]
            for zone in zones {
                XCTAssertTrue(
                    pillSegments.contains { $0.rect.intersected(with: zone) != nil },
                    "uniform radius must emit arc pieces in corner zone \(zone)")
            }
        }
    }

    func testEdgeSpansShrinkByJoiningCornerRadii() async {
        await MainActor.run {
            let frame = Self.frame
            // One dash covering the whole perimeter, butt caps: the top
            // edge segment must span exactly between the two corner zones
            // instead of stopping at a uniform maxRadius inset.
            let style = StrokeStyle(dashPattern: [10000, 1], lineCap: .butt)
            let segments =
                BorderSegments.dashedSegments(
                    frame: frame, width: 3,
                    cornerRadii: RetainedCornerRadii(topLeft: 10, bottomRight: 6),
                    strokeStyle: style
                ) ?? []

            let topEdge = segments.filter {
                // Horizontal edge segments only: the right edge also
                // starts at the frame's top when topRight is square, so
                // discriminate by shape (height == border width).
                $0.rect.origin.y == frame.origin.y
                    && $0.cornerRadius == 0
                    && abs($0.rect.size.height - 3) < 0.001
            }
            XCTAssertEqual(topEdge.count, 1)
            XCTAssertEqual(topEdge[0].rect.origin.x, frame.origin.x + 10, accuracy: 0.001)
            // Top-right radius is 0, so the top edge reaches maxX exactly.
            XCTAssertEqual(topEdge[0].rect.maxX, frame.maxX, accuracy: 0.001)
        }
    }
}
