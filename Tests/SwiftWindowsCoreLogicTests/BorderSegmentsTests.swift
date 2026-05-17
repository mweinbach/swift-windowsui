import Foundation
import Testing

@testable import SwiftWindowsCore
@testable import SwiftWindowsGraphics
@testable import SwiftWindowsUI

@MainActor
@Suite("BorderSegments")
struct BorderSegmentsTests {

    // MARK: - Square corners

    @Test("Square dashed border produces edge segments")
    func squareDashedBorderProducesEdgeSegments() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 20, height: 10),
            width: 2,
            cornerRadius: 0,
            strokeStyle: StrokeStyle(lineWidth: 2, dashPattern: [4, 2])
        )

        guard let segments else {
            Issue.record("Expected segments")
            return
        }

        #expect(segments.count > 0)
        // First segment should be on the top edge
        #expect(segments[0].rect.origin.y == 0)
        #expect(segments[0].rect.size.height == 2)
    }

    @Test("Square border with empty dash pattern returns nil")
    func emptyDashPatternReturnsNil() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 20, height: 10),
            width: 2,
            cornerRadius: 0,
            strokeStyle: StrokeStyle(lineWidth: 2, dashPattern: [])
        )

        #expect(segments == nil)
    }

    @Test("Square border without stroke style returns nil")
    func noStrokeStyleReturnsNil() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 20, height: 10),
            width: 2,
            cornerRadius: 0,
            strokeStyle: nil
        )

        #expect(segments == nil)
    }

    // MARK: - Rounded corners

    @Test("Rounded rect dashed border produces segments")
    func roundedRectDashedBorderProducesSegments() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 40, height: 30),
            width: 2,
            cornerRadius: 8,
            strokeStyle: StrokeStyle(lineWidth: 2, dashPattern: [6, 3])
        )

        guard let segments else {
            Issue.record("Expected segments for rounded rect dashed border")
            return
        }

        #expect(segments.count > 0)
    }

    @Test("Rounded rect dashed border includes straight edge segments")
    func roundedRectDashedBorderIncludesStraightEdges() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 40, height: 30),
            width: 2,
            cornerRadius: 8,
            strokeStyle: StrokeStyle(lineWidth: 2, dashPattern: [6, 3])
        )

        guard let segments else {
            Issue.record("Expected segments")
            return
        }

        // Top straight edge should have segments at y == 0 with height == 2
        var topEdgeCount = 0
        for seg in segments {
            if seg.rect.origin.y == 0 && seg.rect.size.height == 2 {
                topEdgeCount += 1
            }
        }
        #expect(topEdgeCount > 0)
    }

    @Test("Rounded rect dashed border includes corner arc segments")
    func roundedRectDashedBorderIncludesArcSegments() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 40, height: 30),
            width: 2,
            cornerRadius: 8,
            strokeStyle: StrokeStyle(lineWidth: 2, dashPattern: [6, 3])
        )

        guard let segments else {
            Issue.record("Expected segments")
            return
        }

        // Top-right corner area should have small segments
        var cornerCount = 0
        for seg in segments {
            if seg.rect.origin.x > 20 && seg.rect.origin.y < 10 && seg.rect.size.width < 12 && seg.rect.size.height < 12
            {
                cornerCount += 1
            }
        }
        #expect(cornerCount > 0)
    }

    @Test("Rounded rect with zero dash pattern falls back to nil")
    func roundedRectZeroDashReturnsNil() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 40, height: 30),
            width: 2,
            cornerRadius: 8,
            strokeStyle: StrokeStyle(lineWidth: 2, dashPattern: [])
        )

        #expect(segments == nil)
    }

    @Test("Very small rounded rect with large dash pattern still produces segments")
    func smallRoundedRectWithLargeDash() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 10, height: 10),
            width: 1,
            cornerRadius: 2,
            strokeStyle: StrokeStyle(lineWidth: 1, dashPattern: [20, 5])
        )

        guard let segments else {
            Issue.record("Expected segments")
            return
        }

        // A single long dash should wrap around and produce at least one segment
        #expect(segments.count > 0)
    }

    @Test("Round line caps on rounded rect produce corner radius on segments")
    func roundedRectRoundLineCaps() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 40, height: 30),
            width: 2,
            cornerRadius: 8,
            strokeStyle: StrokeStyle(lineWidth: 2, dashPattern: [6, 3], lineCap: .round)
        )

        guard let segments else {
            Issue.record("Expected segments")
            return
        }

        // At least one segment should have a non-zero corner radius from the round cap
        var roundedCount = 0
        for seg in segments {
            if seg.cornerRadius > 0 {
                roundedCount += 1
            }
        }
        #expect(roundedCount > 0)
    }
}
