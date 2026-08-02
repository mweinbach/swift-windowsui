import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Pins the corner-arc geometry `BorderSegments` emits for a rounded border.
///
/// The annular-sector bounding box used to be computed as if the ring's outer
/// edge always lay at `+x`/`-y` — true only for the top-right quadrant. The
/// other three corners came out narrower than the ring by exactly the border
/// width, and the sub-boxes nearest the straight edges inverted and were
/// dropped outright, so a rounded border on a container with children (the
/// segment path) rendered visibly thin or gapped at three corners out of four.
/// These tests measure all four quadrants rather than the one whose maths was
/// right.
@MainActor
final class BorderCornerArcGeometryTests: XCTestCase {

    private static let frame = Rect(x: 0, y: 0, width: 40, height: 40)
    private static let radius = 8.0
    private static let borderWidth = 2.0

    /// The four corners, with the outward diagonal of each in the
    /// top-left-origin space the segments are emitted in.
    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomRight, bottomLeft

        var direction: (x: Double, y: Double) {
            switch self {
            case .topLeft: return (-1, -1)
            case .topRight: return (1, -1)
            case .bottomRight: return (1, 1)
            case .bottomLeft: return (-1, 1)
            }
        }

        /// Centre of the corner's arc, i.e. the frame corner pulled inward by
        /// the radius along both axes.
        func arcCenter(in frame: Rect, radius: Double) -> Point {
            let direction = direction
            return Point(
                x: (direction.x < 0 ? frame.minX + radius : frame.maxX - radius),
                y: (direction.y < 0 ? frame.minY + radius : frame.maxY - radius)
            )
        }

        /// The `radius × radius` square the corner's arc geometry occupies.
        func zone(in frame: Rect, radius: Double) -> Rect {
            let direction = direction
            return Rect(
                x: direction.x < 0 ? frame.minX : frame.maxX - radius,
                y: direction.y < 0 ? frame.minY : frame.maxY - radius,
                width: radius,
                height: radius
            )
        }
    }

    /// Arc pieces carry a pill radius; straight edge spans are emitted with
    /// `cornerRadius == 0` (butt caps), so shape discriminates the two.
    private func arcSegments(_ segments: [BorderSegment]) -> [BorderSegment] {
        segments.filter { $0.cornerRadius > 0 }
    }

    private func arcSegments(_ segments: [BorderSegment], for corner: Corner) -> [BorderSegment] {
        let frame = Self.frame
        return arcSegments(segments).filter { segment in
            let onRight = segment.rect.midX > frame.midX
            let onBottom = segment.rect.midY > frame.midY
            return (corner.direction.x > 0) == onRight && (corner.direction.y > 0) == onBottom
        }
    }

    private func unionBounds(_ segments: [BorderSegment]) -> Rect? {
        guard let first = segments.first else { return nil }
        var minX = first.rect.minX
        var minY = first.rect.minY
        var maxX = first.rect.maxX
        var maxY = first.rect.maxY
        for segment in segments.dropFirst() {
            minX = min(minX, segment.rect.minX)
            minY = min(minY, segment.rect.minY)
            maxX = max(maxX, segment.rect.maxX)
            maxY = max(maxY, segment.rect.maxY)
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func uniformSolidSegments() -> [BorderSegment] {
        BorderSegments.solidSegments(
            frame: Self.frame, width: Self.borderWidth, cornerRadius: Self.radius)
    }

    private func perCornerSolidSegments() -> [BorderSegment] {
        BorderSegments.solidSegments(
            frame: Self.frame,
            width: Self.borderWidth,
            cornerRadii: RetainedCornerRadii(uniform: Self.radius)
        )
    }

    // MARK: - Ring coverage

    /// The midpoint of the ring at 45° — `(r - width/2)` from the arc centre
    /// along the corner's outward diagonal — is the pixel a thin corner drops
    /// first. Every corner's arc boxes must cover it.
    func testEveryCornerCoversTheRingMidpointAtFortyFiveDegrees() async {
        for (label, segments) in [
            ("uniform", uniformSolidSegments()), ("per-corner", perCornerSolidSegments()),
        ] {
            for corner in Corner.allCases {
                let center = corner.arcCenter(in: Self.frame, radius: Self.radius)
                let offset = (Self.radius - Self.borderWidth * 0.5) * cos(Double.pi / 4)
                let midpoint = Point(
                    x: center.x + corner.direction.x * offset,
                    y: center.y + corner.direction.y * offset
                )
                XCTAssertTrue(
                    arcSegments(segments, for: corner).contains { $0.rect.contains(midpoint) },
                    "\(label): \(corner) arc boxes must cover the ring midpoint \(midpoint)")
            }
        }
    }

    /// The union of a corner's arc boxes is exactly the corner's
    /// `radius × radius` square: the arcs reach the outer frame edges on both
    /// axes. Assuming a fixed outer side left three corners short by the
    /// border width (a 6×8, 8×6 or 6×6 union instead of 8×8).
    func testEveryCornerArcUnionSpansTheFullCornerSquare() async {
        for (label, segments) in [
            ("uniform", uniformSolidSegments()), ("per-corner", perCornerSolidSegments()),
        ] {
            for corner in Corner.allCases {
                guard let union = unionBounds(arcSegments(segments, for: corner)) else {
                    XCTFail("\(label): \(corner) emitted no arc segments")
                    continue
                }
                let zone = corner.zone(in: Self.frame, radius: Self.radius)
                XCTAssertEqual(union.minX, zone.minX, accuracy: 1e-9, "\(label): \(corner) minX")
                XCTAssertEqual(union.minY, zone.minY, accuracy: 1e-9, "\(label): \(corner) minY")
                XCTAssertEqual(union.maxX, zone.maxX, accuracy: 1e-9, "\(label): \(corner) maxX")
                XCTAssertEqual(union.maxY, zone.maxY, accuracy: 1e-9, "\(label): \(corner) maxY")
            }
        }
    }

    /// Congruent corners emit congruent geometry: same sub-arc count, and
    /// total arc-box area within 20 % across the four quadrants. Inverted
    /// sub-boxes used to be dropped, which showed up here as both a lower
    /// count and a smaller area.
    func testCornerArcAreasAndCountsAgreeAcrossQuadrants() async {
        for (label, segments) in [
            ("uniform", uniformSolidSegments()), ("per-corner", perCornerSolidSegments()),
        ] {
            var areas: [Double] = []
            var counts: [Int] = []
            for corner in Corner.allCases {
                let arcs = arcSegments(segments, for: corner)
                counts.append(arcs.count)
                areas.append(arcs.reduce(0) { $0 + $1.rect.size.width * $1.rect.size.height })
            }
            XCTAssertEqual(
                Set(counts).count, 1,
                "\(label): every corner must emit the same number of sub-arcs, got \(counts)")
            guard let smallest = areas.min(), let largest = areas.max(), smallest > 0 else {
                XCTFail("\(label): every corner must emit arc area, got \(areas)")
                continue
            }
            XCTAssertLessThanOrEqual(
                largest / smallest, 1.2,
                "\(label): corner arc areas must agree within 20 %, got \(areas)")
        }
    }

    /// No sub-arc may invert. An inverted box is silently dropped, which is
    /// how corners lost geometry next to the straight edges.
    func testNoSubArcInverts() async {
        for (label, segments) in [
            ("uniform", uniformSolidSegments()), ("per-corner", perCornerSolidSegments()),
        ] {
            for segment in arcSegments(segments) {
                XCTAssertGreaterThan(segment.rect.size.width, 0, "\(label): \(segment)")
                XCTAssertGreaterThan(segment.rect.size.height, 0, "\(label): \(segment)")
            }
        }
    }

    /// A border as wide as the radius (`innerR == 0`) is the degenerate case
    /// that dropped whole corners: with the outer side pinned, three corners'
    /// boxes collapsed to zero on one axis.
    func testFullWidthBorderStillEmitsEveryCorner() async {
        let segments = BorderSegments.solidSegments(
            frame: Self.frame, width: Self.radius, cornerRadius: Self.radius)
        for corner in Corner.allCases {
            XCTAssertFalse(
                arcSegments(segments, for: corner).isEmpty,
                "\(corner) must emit arc geometry when the border is as wide as the radius")
        }
    }

    // MARK: - Dashed borders

    /// The same geometry drives dashed borders. With a dash pattern long
    /// enough to cover the whole perimeter, every corner's arc union is again
    /// the full corner square.
    func testDashedFullCoverageSpansEveryCornerSquare() async {
        let style = StrokeStyle(lineWidth: Self.borderWidth, dashPattern: [10_000, 1], lineCap: .butt)
        let segments =
            BorderSegments.dashedSegments(
                frame: Self.frame,
                width: Self.borderWidth,
                cornerRadius: Self.radius,
                strokeStyle: style
            ) ?? []
        XCTAssertFalse(segments.isEmpty)
        for corner in Corner.allCases {
            guard let union = unionBounds(arcSegments(segments, for: corner)) else {
                XCTFail("\(corner) emitted no dashed arc segments")
                continue
            }
            let zone = corner.zone(in: Self.frame, radius: Self.radius)
            XCTAssertEqual(union.minX, zone.minX, accuracy: 1e-9, "\(corner) minX")
            XCTAssertEqual(union.minY, zone.minY, accuracy: 1e-9, "\(corner) minY")
            XCTAssertEqual(union.maxX, zone.maxX, accuracy: 1e-9, "\(corner) maxX")
            XCTAssertEqual(union.maxY, zone.maxY, accuracy: 1e-9, "\(corner) maxY")
        }
    }
}
