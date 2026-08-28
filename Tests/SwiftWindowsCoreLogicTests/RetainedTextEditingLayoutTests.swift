import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

final class RetainedTextEditingLayoutTests: XCTestCase {
    func testSoftWrappingUsesWholeProportionalFragmentMeasurements() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                syntheticEditingLine(text, style: style) { $0 == "W" ? 13 : 3 }
            } perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "WiWi", style: editingStyle(), contentWidth: 16, displayScale: 1))

                XCTAssertEqual(layout.lines.map(\.text), ["Wi", "Wi"])
                XCTAssertEqual(layout.lines.map(\.sourceRange), [0..<2, 2..<4])
                XCTAssertEqual(layout.lines.map { $0.rect.width }, [16, 16])
                XCTAssertEqual(layout.contentSize, Size(width: 16, height: 40))
                let caret = try XCTUnwrap(layout.caret(onLine: 1, nearestX: 13.2))
                XCTAssertEqual(caret.position.characterOffset, 3)
                XCTAssertEqual(caret.rect.minX, 13)
            }
        }
    }

    func testNearestXCanBeReusedAcrossShorterVisualLines() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                syntheticEditingLine(text, style: style) { $0 == "W" ? 13 : 3 }
            } perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "WW\nii\nWii", style: editingStyle(), contentWidth: 100, displayScale: 1))

                XCTAssertEqual(layout.caret(onLine: 1, nearestX: 18)?.position.characterOffset, 5)
                XCTAssertEqual(layout.caret(onLine: 2, nearestX: 18)?.position.characterOffset, 9)
                XCTAssertEqual(layout.caret(onLine: 0, nearestX: 18)?.position.characterOffset, 1)
            }
        }
    }

    func testWrappingPreservesAllSpacesTabsAndOriginalNewlineSequences() async throws {
        try await MainActor.run {
            try withEditingMetrics(perform: {
                let text = "  a\tb \r\n\r\nc\r\n"
                let characters = Array(text)
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: text, style: editingStyle(), contentWidth: 10, displayScale: 1))
                var reconstructed = ""
                for line in layout.lines {
                    XCTAssertEqual(line.text, String(characters[line.sourceRange]))
                    reconstructed += line.text
                    if let hardBreak = line.hardBreakRange {
                        let separator = String(characters[hardBreak])
                        XCTAssertEqual(separator, "\r\n")
                        reconstructed += separator
                    }
                }

                XCTAssertEqual(reconstructed, text)
                XCTAssertEqual(layout.characterCount, characters.count)
                XCTAssertEqual(layout.lines.compactMap(\.hardBreakRange).count, 3)
                XCTAssertEqual(layout.lines.last?.text, "")
                XCTAssertEqual(layout.lines.last?.sourceRange, characters.count..<characters.count)
                XCTAssertEqual(
                    layout.caret(at: .init(characterOffset: characters.count))?.lineIndex, layout.lines.count - 1)
            })
        }
    }

    func testLFCRAndCRLFPreserveCharacterOffsetsAndEmptyTrailingLines() async throws {
        try await MainActor.run {
            try withEditingMetrics(perform: {
                for separator in ["\n", "\r", "\r\n"] {
                    let text = "a\(separator)b\(separator)"
                    let layout = try XCTUnwrap(
                        RetainedTextMetrics.editingLayout(
                            of: text, style: editingStyle(), contentWidth: 100, displayScale: 1))

                    XCTAssertEqual(layout.characterCount, 4)
                    XCTAssertEqual(layout.lines.map(\.text), ["a", "b", ""])
                    XCTAssertEqual(layout.lines.map(\.sourceRange), [0..<1, 2..<3, 4..<4])
                    XCTAssertEqual(layout.lines.compactMap(\.hardBreakRange), [1..<2, 3..<4])
                    XCTAssertEqual(layout.caret(at: .init(characterOffset: 1))?.lineIndex, 0)
                    XCTAssertEqual(layout.caret(at: .init(characterOffset: 2))?.lineIndex, 1)
                    XCTAssertEqual(layout.caret(at: .init(characterOffset: 4))?.lineIndex, 2)
                }
            })
        }
    }

    func testEmptyTextHasOneFullHeightCaretLine() async throws {
        try await MainActor.run {
            try withEditingMetrics(perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(of: "", style: editingStyle(), contentWidth: 50, displayScale: 1))

                XCTAssertTrue(layout.hasCompleteCaretGeometry)
                XCTAssertEqual(layout.lines.count, 1)
                XCTAssertEqual(layout.lines[0].rect, Rect(x: 0, y: 0, width: 0, height: 20))
                XCTAssertEqual(
                    layout.caret(at: .init(characterOffset: 0))?.rect, Rect(x: 0, y: 0, width: 0, height: 20))
                XCTAssertEqual(layout.hitTest(Point(x: 100, y: 100))?.position.characterOffset, 0)
                XCTAssertTrue(layout.selectionRects(for: 0..<0).isEmpty)
            })
        }
    }

    func testSoftWrapAffinityAndPointerHitsRoundTripToTheSameVisualLine() async throws {
        try await MainActor.run {
            try withEditingMetrics(perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "abcd", style: editingStyle(), contentWidth: 10, displayScale: 1))
                let upstream = try XCTUnwrap(layout.caret(at: .init(characterOffset: 2, affinity: .upstream)))
                let downstream = try XCTUnwrap(layout.caret(at: .init(characterOffset: 2, affinity: .downstream)))

                XCTAssertEqual(upstream.lineIndex, 0)
                XCTAssertEqual(upstream.rect.origin, Point(x: 10, y: 0))
                XCTAssertEqual(downstream.lineIndex, 1)
                XCTAssertEqual(downstream.rect.origin, Point(x: 0, y: 20))
                let firstLineHit = try XCTUnwrap(layout.hitTest(Point(x: 100, y: 5)))
                let secondLineHit = try XCTUnwrap(layout.hitTest(Point(x: -100, y: 25)))
                XCTAssertEqual(firstLineHit.position, upstream.position)
                XCTAssertEqual(secondLineHit.position, downstream.position)
                XCTAssertEqual(layout.caret(at: firstLineHit.position), firstLineHit)
                XCTAssertEqual(layout.caret(at: secondLineHit.position), secondLineHit)
            })
        }
    }

    func testHardNewlineSeparatesTheTwoLogicalBoundaryOffsets() async throws {
        try await MainActor.run {
            try withEditingMetrics(perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "ab\ncd", style: editingStyle(), contentWidth: 100, displayScale: 1))

                XCTAssertEqual(layout.caret(at: .init(characterOffset: 2))?.lineIndex, 0)
                XCTAssertEqual(layout.caret(at: .init(characterOffset: 3, affinity: .upstream))?.lineIndex, 1)
                XCTAssertEqual(layout.caret(at: .init(characterOffset: Int.min))?.position.characterOffset, 0)
                XCTAssertEqual(layout.caret(at: .init(characterOffset: Int.max))?.position.characterOffset, 5)
            })
        }
    }

    func testGraphemeWrappingDoesNotSplitCombiningOrJoinedEmojiSequences() async throws {
        try await MainActor.run {
            try withEditingMetrics(perform: {
                let text = "a👨‍👩‍👧‍👦e\u{301}b"
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(of: text, style: editingStyle(), contentWidth: 5, displayScale: 1)
                )

                XCTAssertEqual(layout.characterCount, 4)
                XCTAssertEqual(layout.lines.map(\.text), Array(text).map(String.init))
                XCTAssertEqual(layout.lines.map(\.sourceRange), [0..<1, 1..<2, 2..<3, 3..<4])
                XCTAssertEqual(layout.lines.map(\.text).joined(), text)
                for line in layout.lines {
                    XCTAssertTrue(
                        line.carets.allSatisfy {
                            line.sourceRange.lowerBound...line.sourceRange.upperBound ~= $0.position.characterOffset
                        })
                }
            })
        }
    }

    func testAnOversizedGraphemeMakesProgressWithoutBeingSplit() async throws {
        try await MainActor.run {
            var calls = 0
            try withEditingMetrics { text, style, _ in
                calls += 1
                return syntheticEditingLine(text, style: style)
            } perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "ab😀", style: editingStyle(), contentWidth: 2, displayScale: 1))

                XCTAssertEqual(layout.lines.map(\.text), ["a", "b", "😀"])
                XCTAssertEqual(layout.contentSize.width, 5)
                XCTAssertLessThanOrEqual(calls, 6)
            }
        }
    }

    func testWhitespacePreferenceMeasuresTheShorterFragmentBeforeAcceptingIt() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                var line = syntheticEditingLine(text, style: style) { _ in 1 }
                if text == "abcd " || (text.hasPrefix("abcd") && text.count >= 7) {
                    line.width = 20
                }
                return line
            } perform: {
                let text = "abcd efgh"
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: text, style: editingStyle(), contentWidth: 10, displayScale: 1))

                XCTAssertEqual(layout.lines.map(\.text), ["abcd e", "fgh"])
                XCTAssertEqual(layout.lines.map(\.text).joined(), text)
                XCTAssertTrue(layout.lines.allSatisfy { $0.text.count == 1 || $0.rect.width <= 10 })
            }
        }
    }

    func testLegacySyntheticLayoutOverrideRemainsAuthoritativeForEditorGeometry() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            defer { NativeTextRenderer.testingOverrides = previous }
            NativeTextRenderer.testingOverrides.editingLine = nil
            NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in
                XCTFail("Editor geometry must not bypass the supplied layout to measure on the host.")
                return nil
            }
            var calls = 0
            NativeTextRenderer.testingOverrides.layout = { text, style, _, maxWidth in
                calls += 1
                XCTAssertEqual(style.lineBreakMode, .clip)
                XCTAssertNil(maxWidth)
                let glyphs = Array(text).enumerated().map { index, character in
                    NativeTextGlyphLayout(
                        character: character, origin: Point(x: Double(index) * 9, y: 0), advance: 9,
                        sourceIndex: index)
                }
                let size = Size(width: Double(text.count) * 9, height: 17)
                return NativeTextLayoutResult(
                    lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
                    contentSize: size, measuredSize: size)
            }

            let layout = try XCTUnwrap(
                RetainedTextMetrics.editingLayout(of: "abc", style: editingStyle(), contentWidth: 18, displayScale: 2))

            XCTAssertGreaterThan(calls, 0)
            XCTAssertTrue(layout.hasCompleteCaretGeometry)
            XCTAssertEqual(layout.lines.map(\.text), ["ab", "c"])
            XCTAssertEqual(layout.caret(at: .init(characterOffset: 2, affinity: .upstream))?.rect.minX, 18)
            XCTAssertEqual(layout.lines[1].rect.minY, 17)
        }
    }

    func testExplicitNativeLayoutFailureUsesPixelGeometryAndPixelLineSpacing() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            defer { NativeTextRenderer.testingOverrides = previous }
            NativeTextRenderer.testingOverrides.editingLine = nil
            NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
            var fallbackCalls = 0
            NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in
                fallbackCalls += 1
                return nil
            }
            var style = editingStyle()
            style.scale = 2
            style.letterSpacing = 1
            style.lineSpacing = 2

            let layout = try XCTUnwrap(
                RetainedTextMetrics.editingLayout(of: "ab\nc", style: style, contentWidth: 100, displayScale: 1))

            XCTAssertTrue(layout.hasCompleteCaretGeometry)
            XCTAssertGreaterThan(fallbackCalls, 0)
            XCTAssertEqual(
                layout.caret(at: .init(characterOffset: 2, affinity: .upstream))?.rect.minX,
                PixelFont.rawLineWidth("ab", letterSpacing: 1) * 2)
            XCTAssertEqual(layout.lines[1].rect.minY, Double(PixelFont.glyphHeight) * 2 + 4)
        }
    }

    func testUnshapedNativeFallbackKeepsItsMeasuredFragmentsWithoutPixelCarets() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            defer { NativeTextRenderer.testingOverrides = previous }
            NativeTextRenderer.testingOverrides.editingLine = nil
            NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
            var measuredTexts: [String] = []
            NativeTextRenderer.testingOverrides.measure = { text, style, scale, width in
                XCTAssertEqual(style.lineBreakMode, .clip)
                XCTAssertEqual(scale, 1.5)
                XCTAssertNil(width)
                measuredTexts.append(text)
                return Size(width: Double(text.count) * 11, height: 19)
            }

            let layout = try XCTUnwrap(
                RetainedTextMetrics.editingLayout(of: "abc", style: editingStyle(), contentWidth: 22, displayScale: 1.5)
            )

            XCTAssertEqual(layout.lines.map(\.text), ["ab", "c"])
            XCTAssertEqual(layout.lines.map { $0.rect.width }, [22, 11])
            XCTAssertEqual(layout.lines[1].rect.minY, 19)
            XCTAssertTrue(measuredTexts.contains("ab"))
            XCTAssertFalse(layout.hasCompleteCaretGeometry)
            XCTAssertTrue(layout.lines.allSatisfy { $0.carets.isEmpty })
            XCTAssertNil(layout.caret(at: .init(characterOffset: 1)))
            XCTAssertNil(layout.hitTest(Point(x: 11, y: 3)))
            XCTAssertTrue(layout.selectionRects(for: 0..<3).isEmpty)
        }
    }

    func testLegacySyntheticAdapterDeclinesReorderedOverlappingOrInvalidGlyphCells() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            defer { NativeTextRenderer.testingOverrides = previous }
            NativeTextRenderer.testingOverrides.editingLine = nil
            for variant in 0..<4 {
                NativeTextRenderer.testingOverrides.layout = { text, _, _, _ in
                    let glyphs = Array(text).enumerated().map { index, character in
                        let x: Double
                        switch variant {
                        case 0: x = Double(text.count - index - 1) * 10
                        case 1: x = Double(index) * 5
                        case 2: x = Double(index) * 10
                        default: x = .nan
                        }
                        return NativeTextGlyphLayout(
                            character: character, origin: Point(x: x, y: 0),
                            advance: variant == 2 ? -10 : 10, sourceIndex: index)
                    }
                    let size = Size(width: Double(text.count) * 10, height: 17)
                    return NativeTextLayoutResult(
                        lines: [
                            NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)
                        ],
                        contentSize: size, measuredSize: size)
                }
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "ab", style: editingStyle(), contentWidth: 100, displayScale: 1))

                XCTAssertEqual(layout.lines.map(\.text), ["ab"])
                XCTAssertEqual(layout.lines[0].rect.width, 20)
                XCTAssertFalse(layout.hasCompleteCaretGeometry, "variant \(variant)")
                XCTAssertTrue(layout.lines[0].carets.isEmpty)
                XCTAssertNil(layout.hitTest(Point(x: 12, y: 4)))
            }
        }
    }

    func testUnavailableCaretGeometryStillPreservesDrawableWrappedFragments() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                var line = syntheticEditingLine(text, style: style)
                if text.contains("a") {
                    line.carets = []
                    line.selectionRegions = []
                }
                return line
            } perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "abcd", style: editingStyle(), contentWidth: 10, displayScale: 1))

                XCTAssertFalse(layout.hasCompleteCaretGeometry)
                XCTAssertEqual(layout.lines.map(\.text), ["ab", "cd"])
                XCTAssertEqual(layout.lines.map { $0.rect.width }, [10, 10])
                XCTAssertNil(layout.caret(at: .init(characterOffset: 0)))
                XCTAssertNil(layout.caret(onLine: 1, nearestX: 4))
                XCTAssertNil(layout.hitTest(Point(x: 1, y: 1)))
                XCTAssertTrue(layout.selectionRects(for: 0..<4).isEmpty)
            }
        }
    }

    func testExpandingPixelCaseTransformKeepsWidthWithoutInventingSourceCarets() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            defer { NativeTextRenderer.testingOverrides = previous }
            NativeTextRenderer.testingOverrides.editingLine = nil
            NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
            var style = editingStyle()
            style.scale = 1
            let width = PixelFont.rawLineWidth("SS", letterSpacing: style.letterSpacing)

            let layout = try XCTUnwrap(
                RetainedTextMetrics.editingLayout(of: "ßx", style: style, contentWidth: width, displayScale: 1))

            XCTAssertEqual(layout.characterCount, 2)
            XCTAssertEqual(layout.lines.map(\.text), ["ß", "x"])
            XCTAssertEqual(layout.lines[0].rect.width, width)
            XCTAssertFalse(layout.hasCompleteCaretGeometry)
            XCTAssertNil(layout.caret(at: .init(characterOffset: 1)))
        }
    }

    func testAlignmentInsetsAndNativeLeadingAreAppliedOnlyOnce() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                XCTAssertEqual(style.insets, .zero)
                XCTAssertEqual(style.alignment, .leading)
                return syntheticEditingLine(text, style: style)
            } perform: {
                var style = editingStyle()
                style.alignment = .center
                style.insets = EdgeInsets(top: 40, leading: 30, bottom: 20, trailing: 10)
                style.lineSpacing = 3
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(of: "ab\nc", style: style, contentWidth: 30, displayScale: 2))

                XCTAssertEqual(layout.lines[0].rect, Rect(x: 10, y: 0, width: 10, height: 20))
                XCTAssertEqual(layout.lines[1].rect, Rect(x: 12.5, y: 20, width: 5, height: 20))
                XCTAssertEqual(layout.contentSize.height, 40)
                XCTAssertEqual(layout.caret(at: .init(characterOffset: 3))?.rect.origin, Point(x: 12.5, y: 20))
            }
        }
    }

    func testLogicalCaretGeometryDoesNotScaleTwiceAtFractionalDPI() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                syntheticEditingLine(text, style: style) { _ in 5.25 }
            } perform: {
                let first = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "abc\nde", style: editingStyle(), contentWidth: 12, displayScale: 1))
                for scale in [1.25, 1.5, 2] {
                    XCTAssertEqual(
                        RetainedTextMetrics.editingLayout(
                            of: "abc\nde", style: editingStyle(), contentWidth: 12, displayScale: scale), first)
                }
            }
        }
    }

    func testBidiSelectionKeepsDisjointNativePiecesAndBothCaretSides() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                guard text == "abאבcd" else { return syntheticEditingLine(text, style: style) { _ in 10 } }
                let leading: [Double] = [0, 10, 40, 30, 40, 50]
                let trailing: [Double] = [10, 20, 30, 20, 50, 60]
                return syntheticEditingLine(text, leading: leading, trailing: trailing)
            } perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "abאבcd", style: editingStyle(), contentWidth: 100, displayScale: 1))

                XCTAssertEqual(layout.caret(at: .init(characterOffset: 2, affinity: .upstream))?.rect.minX, 20)
                XCTAssertEqual(layout.caret(at: .init(characterOffset: 2, affinity: .downstream))?.rect.minX, 40)
                XCTAssertEqual(
                    layout.selectionRects(for: 1..<3),
                    [Rect(x: 10, y: 0, width: 10, height: 20), Rect(x: 30, y: 0, width: 10, height: 20)])
                XCTAssertEqual(layout.selectionRects(for: 2..<4), [Rect(x: 20, y: 0, width: 20, height: 20)])
            }
        }
    }

    func testBidiHitTestingUsesTheCharacterUnderThePointAtCoincidentCaretPositions() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                guard text == "aאb" else { return syntheticEditingLine(text, style: style) { _ in 10 } }
                return syntheticEditingLine(text, leading: [0, 20, 20], trailing: [10, 10, 30])
            } perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "aאb", style: editingStyle(), contentWidth: 100, displayScale: 1))

                for x in [10.1, 12.0] {
                    let caret = try XCTUnwrap(layout.caret(onLine: 0, nearestX: x))
                    XCTAssertEqual(caret.position, RetainedTextCaretPosition(characterOffset: 2, affinity: .upstream))
                    XCTAssertEqual(caret.rect.minX, 10)
                    XCTAssertEqual(layout.hitTest(Point(x: x, y: 5)), caret)
                }
                for x in [18.0, 19.9] {
                    let caret = try XCTUnwrap(layout.caret(onLine: 0, nearestX: x))
                    XCTAssertEqual(caret.position, RetainedTextCaretPosition(characterOffset: 1, affinity: .downstream))
                    XCTAssertEqual(caret.rect.minX, 20)
                    XCTAssertEqual(layout.hitTest(Point(x: x, y: 5)), caret)
                }
                XCTAssertEqual(layout.hitTest(Point(x: 8, y: 5))?.position.characterOffset, 1)
                XCTAssertEqual(layout.hitTest(Point(x: 22, y: 5))?.position.characterOffset, 2)
            }
        }
    }

    func testHardNewlineSelectionAddsOnlyItsFiniteTail() async throws {
        try await MainActor.run {
            try withEditingMetrics(perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "ab\r\n", style: editingStyle(), contentWidth: 100, displayScale: 1))

                XCTAssertEqual(layout.selectionRects(for: 2..<3), [Rect(x: 10, y: 0, width: 4.5, height: 20)])
                XCTAssertEqual(layout.selectionRects(for: 0..<3), [Rect(x: 0, y: 0, width: 14.5, height: 20)])
                XCTAssertEqual(layout.lines.last?.text, "")
                XCTAssertEqual(layout.caret(at: .init(characterOffset: 3))?.rect.minY, 20)
            })
        }
    }

    func testNativeClusterSnappingDoesNotInventInteriorCaretStops() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                guard text == "ffi" else { return syntheticEditingLine(text, style: style) }
                return NativeTextEditingLine(
                    text: text, width: 12, height: 20,
                    carets: [
                        NativeTextEditingCaret(characterOffset: 0, affinity: .downstream, x: 0),
                        NativeTextEditingCaret(characterOffset: 3, affinity: .upstream, x: 12),
                    ],
                    selectionRegions: [
                        NativeTextEditingRegion(characterRange: 0..<3, rect: Rect(x: 0, y: 0, width: 12, height: 20))
                    ])
            } perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "ffi", style: editingStyle(), contentWidth: 100, displayScale: 1))

                XCTAssertEqual(
                    layout.caret(at: .init(characterOffset: 1, affinity: .upstream))?.position.characterOffset, 0)
                XCTAssertEqual(
                    layout.caret(at: .init(characterOffset: 1, affinity: .downstream))?.position.characterOffset, 3)
                XCTAssertEqual(Set(layout.lines[0].carets.map { $0.position.characterOffset }), [0, 3])
            }
        }
    }

    func testInvalidInputsFailBeforeMeasuringText() async throws {
        try await MainActor.run {
            try withEditingMetrics { _, _, _ in
                XCTFail("Invalid geometry must not reach a native metric provider.")
                return nil
            } perform: {
                for width in [Double.nan, .infinity, -.infinity, 0, -1] {
                    XCTAssertNil(
                        RetainedTextMetrics.editingLayout(
                            of: "a", style: editingStyle(), contentWidth: width, displayScale: 1))
                }
                for scale in [Double.nan, .infinity, 0, -1] {
                    XCTAssertNil(
                        RetainedTextMetrics.editingLayout(
                            of: "a", style: editingStyle(), contentWidth: 100, displayScale: scale))
                }
                var style = editingStyle()
                style.nativeLetterSpacing = .nan
                XCTAssertNil(
                    RetainedTextMetrics.editingLayout(of: "a", style: style, contentWidth: 100, displayScale: 1))
            }
        }
    }

    func testInvalidCaretRecordsDisableGeometryWithoutDroppingText() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                var result = syntheticEditingLine(text, style: style)
                result.carets.append(NativeTextEditingCaret(characterOffset: 0, affinity: .downstream, x: .nan))
                return result
            } perform: {
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "abc", style: editingStyle(), contentWidth: 100, displayScale: 1))

                XCTAssertEqual(layout.lines.map(\.text), ["abc"])
                XCTAssertFalse(layout.hasCompleteCaretGeometry)
                XCTAssertNil(layout.hitTest(Point(x: 3, y: 3)))
                XCTAssertTrue(layout.selectionRects(for: 0..<3).isEmpty)
            }
        }
    }

    func testTranslatedGeometryOverflowDoesNotEscapeTheSnapshot() async throws {
        try await MainActor.run {
            try withEditingMetrics { text, style, _ in
                var line = syntheticEditingLine(text, style: style)
                line.carets.append(
                    NativeTextEditingCaret(characterOffset: 0, affinity: .downstream, x: .greatestFiniteMagnitude))
                line.selectionRegions.append(
                    NativeTextEditingRegion(
                        characterRange: 0..<1,
                        rect: Rect(x: .greatestFiniteMagnitude, y: 0, width: 0, height: 20)))
                return line
            } perform: {
                var style = editingStyle()
                style.alignment = .center
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: "a", style: style, contentWidth: .greatestFiniteMagnitude, displayScale: 1))

                XCTAssertEqual(layout.lines.map(\.text), ["a"])
                XCTAssertFalse(layout.hasCompleteCaretGeometry)
                XCTAssertTrue(layout.lines[0].rect.minX.isFinite)
                XCTAssertTrue(layout.lines[0].carets.allSatisfy { $0.rect.minX.isFinite && $0.rect.maxY.isFinite })
                XCTAssertNil(layout.caret(at: .init(characterOffset: 0)))
                XCTAssertTrue(layout.selectionRects(for: 0..<1).isEmpty)
            }
        }
    }

    func testLongUnbrokenTextUsesABoundedNumberOfWholeFragmentProbes() async throws {
        try await MainActor.run {
            var calls = 0
            try withEditingMetrics { text, style, _ in
                calls += 1
                return syntheticEditingLine(text, style: style)
            } perform: {
                let text = String(repeating: "x", count: 1000)
                let layout = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(
                        of: text, style: editingStyle(), contentWidth: 25, displayScale: 1))

                XCTAssertEqual(layout.lines.count, 200)
                XCTAssertEqual(layout.lines.map(\.text).joined(), text)
                XCTAssertTrue(layout.lines.allSatisfy { $0.rect.width <= 25 })
                XCTAssertLessThanOrEqual(calls, text.count * 3)
            }
        }
    }

    func testDirectWriteEditorCaretGeometryMatchesTheWholePaintedLatinLine() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            let previousShaping = NativeTextRenderer.isGlyphShapingEnabled
            NativeTextRenderer.resetTestingOverrides()
            NativeTextRenderer.isGlyphShapingEnabled = true
            defer {
                NativeTextRenderer.testingOverrides = previous
                NativeTextRenderer.isGlyphShapingEnabled = previousShaping
            }
            let text = "Wi ab"
            let style = editingStyle()
            guard let painted = DirectWriteTextRenderer.layout(text, style: style, scaleFactor: 1)?.lines.first else {
                throw XCTSkip("DirectWrite is unavailable in this environment.")
            }
            let editing = try XCTUnwrap(DirectWriteTextRenderer.editingLine(text, style: style, scaleFactor: 1))

            XCTAssertEqual(editing.width, painted.width, accuracy: 0.001)
            XCTAssertEqual(editing.height, painted.height, accuracy: 0.001)
            for glyph in painted.glyphs {
                guard let offset = glyph.sourceIndex else { continue }
                let caret = try XCTUnwrap(
                    editing.carets.first { $0.characterOffset == offset && $0.affinity == .downstream })
                XCTAssertEqual(caret.x, glyph.origin.x, accuracy: 0.001)
            }
            XCTAssertTrue(editing.carets.allSatisfy { (0...text.count).contains($0.characterOffset) })
        }
    }

    func testDirectWriteBidiSelectionRetainsSeparateNativeRectangles() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            let previousShaping = NativeTextRenderer.isGlyphShapingEnabled
            NativeTextRenderer.resetTestingOverrides()
            NativeTextRenderer.isGlyphShapingEnabled = true
            defer {
                NativeTextRenderer.testingOverrides = previous
                NativeTextRenderer.isGlyphShapingEnabled = previousShaping
            }
            let text = "abאבcd"
            let style = editingStyle()
            guard DirectWriteTextRenderer.layout(text, style: style, scaleFactor: 1) != nil else {
                throw XCTSkip("DirectWrite is unavailable in this environment.")
            }
            let layout = try XCTUnwrap(
                RetainedTextMetrics.editingLayout(of: text, style: style, contentWidth: 500, displayScale: 1))

            XCTAssertTrue(layout.hasCompleteCaretGeometry)
            XCTAssertEqual(layout.selectionRects(for: 1..<3).count, 2)
            let upstream = try XCTUnwrap(layout.caret(at: .init(characterOffset: 2, affinity: .upstream)))
            let downstream = try XCTUnwrap(layout.caret(at: .init(characterOffset: 2, affinity: .downstream)))
            XCTAssertGreaterThan(downstream.rect.minX, upstream.rect.minX)
        }
    }

    func testDirectWriteSupportedTrackingMatchesPaintedGlyphPositions() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            let previousShaping = NativeTextRenderer.isGlyphShapingEnabled
            NativeTextRenderer.resetTestingOverrides()
            NativeTextRenderer.isGlyphShapingEnabled = true
            defer {
                NativeTextRenderer.testingOverrides = previous
                NativeTextRenderer.isGlyphShapingEnabled = previousShaping
            }
            var style = editingStyle()
            style.nativeLetterSpacing = 2.5
            let text = "abc"
            guard let painted = DirectWriteTextRenderer.layout(text, style: style, scaleFactor: 1)?.lines.first else {
                throw XCTSkip("DirectWrite is unavailable in this environment.")
            }
            let editing = try XCTUnwrap(DirectWriteTextRenderer.editingLine(text, style: style, scaleFactor: 1))

            XCTAssertEqual(editing.width, painted.width, accuracy: 0.001)
            for glyph in painted.glyphs {
                guard let offset = glyph.sourceIndex else { continue }
                let caret = try XCTUnwrap(
                    editing.carets.first { $0.characterOffset == offset && $0.affinity == .downstream })
                XCTAssertEqual(caret.x, glyph.origin.x, accuracy: 0.001)
            }
        }
    }

    func testDirectWriteTrailingSpacesAndTabsParticipateInWrapAndCaretExtent() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            let previousShaping = NativeTextRenderer.isGlyphShapingEnabled
            NativeTextRenderer.resetTestingOverrides()
            NativeTextRenderer.isGlyphShapingEnabled = true
            defer {
                NativeTextRenderer.testingOverrides = previous
                NativeTextRenderer.isGlyphShapingEnabled = previousShaping
            }
            let style = editingStyle()
            guard let bare = DirectWriteTextRenderer.layout("a", style: style, scaleFactor: 1)?.lines.first else {
                throw XCTSkip("DirectWrite is unavailable in this environment.")
            }
            for text in ["a ", "a\t"] {
                let painted = try XCTUnwrap(
                    DirectWriteTextRenderer.layout(text, style: style, scaleFactor: 1)?.lines.first)
                let editing = try XCTUnwrap(DirectWriteTextRenderer.editingLine(text, style: style, scaleFactor: 1))
                let end = try XCTUnwrap(
                    editing.carets.first { $0.characterOffset == text.count && $0.affinity == .upstream })

                XCTAssertGreaterThan(editing.width, bare.width)
                XCTAssertEqual(editing.width, painted.width, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(editing.width + 0.001, end.x)
                let width = (bare.width + editing.width) * 0.5
                let wrapped = try XCTUnwrap(
                    RetainedTextMetrics.editingLayout(of: text, style: style, contentWidth: width, displayScale: 1))
                XCTAssertEqual(wrapped.lines.map(\.text), ["a", String(text.dropFirst())])
                XCTAssertEqual(wrapped.lines.map(\.text).joined(), text)
            }
        }
    }

    func testDirectWriteCaretOffsetsCountGraphemesRatherThanUTF16CodeUnits() async throws {
        try await MainActor.run {
            let previous = NativeTextRenderer.testingOverrides
            let previousShaping = NativeTextRenderer.isGlyphShapingEnabled
            NativeTextRenderer.resetTestingOverrides()
            NativeTextRenderer.isGlyphShapingEnabled = true
            defer {
                NativeTextRenderer.testingOverrides = previous
                NativeTextRenderer.isGlyphShapingEnabled = previousShaping
            }
            let text = "e\u{301}😀x"
            let style = editingStyle()
            guard DirectWriteTextRenderer.layout(text, style: style, scaleFactor: 1) != nil else {
                throw XCTSkip("DirectWrite is unavailable in this environment.")
            }
            let layout = try XCTUnwrap(
                RetainedTextMetrics.editingLayout(of: text, style: style, contentWidth: 500, displayScale: 1))

            XCTAssertEqual(text.count, 3)
            XCTAssertGreaterThan(text.utf16.count, text.count)
            XCTAssertTrue(layout.hasCompleteCaretGeometry)
            XCTAssertEqual(layout.lines[0].sourceRange, 0..<3)
            XCTAssertTrue(layout.lines[0].carets.allSatisfy { (0...3).contains($0.position.characterOffset) })
            for offset in 0...3 {
                XCTAssertEqual(layout.caret(at: .init(characterOffset: offset))?.position.characterOffset, offset)
            }
        }
    }
}

@MainActor
private func withEditingMetrics(
    _ metrics: @escaping (String, PixelTextStyle, Double) -> NativeTextEditingLine? = { text, style, _ in
        syntheticEditingLine(text, style: style)
    },
    perform body: () throws -> Void
) rethrows {
    let previous = NativeTextRenderer.testingOverrides
    defer { NativeTextRenderer.testingOverrides = previous }
    NativeTextRenderer.testingOverrides.editingLine = metrics
    NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in
        XCTFail("The explicit editor metric seam must not call the ordinary native layout provider.")
        return nil
    }
    try body()
}

private func editingStyle() -> PixelTextStyle {
    PixelTextStyle(
        color: .white, scale: 1, alignment: .leading, verticalAlignment: .top,
        letterSpacing: 1, lineSpacing: 2, insets: .zero, fontFamily: "Segoe UI", nativeFontSize: 14,
        lineBreakMode: .clip,
        maximumNumberOfLines: 1)
}

private func syntheticEditingLine(
    _ text: String, style: PixelTextStyle, advance: (Character) -> Double = { _ in 5 }
) -> NativeTextEditingLine {
    var x = 0.0
    var leading: [Double] = []
    var trailing: [Double] = []
    for character in text {
        leading.append(x)
        x += advance(character)
        trailing.append(x)
    }
    var line = syntheticEditingLine(text, leading: leading, trailing: trailing)
    line.lineSpacing = min(style.lineSpacing, 0)
    return line
}

private func syntheticEditingLine(_ text: String, leading: [Double], trailing: [Double]) -> NativeTextEditingLine {
    precondition(leading.count == text.count && trailing.count == text.count)
    var carets: [NativeTextEditingCaret] = []
    var regions: [NativeTextEditingRegion] = []
    for index in leading.indices {
        carets.append(NativeTextEditingCaret(characterOffset: index, affinity: .downstream, x: leading[index]))
        carets.append(NativeTextEditingCaret(characterOffset: index + 1, affinity: .upstream, x: trailing[index]))
        regions.append(
            NativeTextEditingRegion(
                characterRange: index..<(index + 1),
                rect: Rect(
                    x: min(leading[index], trailing[index]), y: 0, width: abs(trailing[index] - leading[index]),
                    height: 20)))
    }
    let start = leading.first ?? 0
    let end = trailing.last ?? 0
    carets.insert(NativeTextEditingCaret(characterOffset: 0, affinity: .upstream, x: start), at: 0)
    carets.append(NativeTextEditingCaret(characterOffset: text.count, affinity: .downstream, x: end))
    return NativeTextEditingLine(
        text: text, width: max(leading.max() ?? 0, trailing.max() ?? 0), height: 20,
        carets: carets, selectionRegions: regions)
}
