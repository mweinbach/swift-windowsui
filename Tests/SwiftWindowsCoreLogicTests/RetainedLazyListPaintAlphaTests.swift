import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedLazyListPaintAlphaTests: XCTestCase {
    private let rect = Rect(x: 0, y: 0, width: 8, height: 8)
    private let invalidAlphas: [Float] = [2, -0.1, .nan, .infinity, -Float.infinity]

    private func color(_ alpha: Float) -> Color {
        Color(red: 0.2, green: 0.4, blue: 0.6, alpha: alpha)
    }

    private func ramp(_ alpha: Float) -> LinearGradient {
        LinearGradient(stops: [
            GradientStop(color: .white, position: 0),
            GradientStop(color: color(alpha), position: 0.5),
            GradientStop(color: .clear, position: 1),
        ])
    }

    private func bitmap() -> BitmapSurface {
        BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 0, 255]))
    }

    private func solids(_ color: Color) -> [CanvasGraphicsContext.Operation] {
        let path = RenderPath(path: Path(rect))
        return [
            .fillPath(path, color), .fillPathWithRule(path, color, fillRule: .evenOdd),
            .strokePath(path, color, StrokeStyle(lineWidth: 1)),
            .fillRect(rect, color), .strokeRect(rect, color, 1),
        ]
    }

    private func gradients(_ gradient: LinearGradient) -> [CanvasGraphicsContext.Operation] {
        let path = RenderPath(path: Path(rect))
        return [
            .fillPathGradient(path, gradient, startPoint: nil, endPoint: nil),
            .fillPathGradientWithRule(
                path, gradient, startPoint: .zero, endPoint: Point(x: 8, y: 8), fillRule: .evenOdd),
            .strokePathGradient(path, gradient, StrokeStyle(lineWidth: 1), startPoint: nil, endPoint: nil),
            .fillRectGradient(rect, gradient),
        ]
    }

    func testAuthoredAlphaMustBeCheckedBeforeSaturationLosesItsProvenance() async {
        let authored = color(2)
        let recorded = authored.multipliedAlpha(by: 1)
        XCTAssertEqual(recorded.alpha, 1)
        XCTAssertEqual(authored.multipliedAlpha(by: 0.5).alpha, 1)
        XCTAssertEqual(recorded.multipliedAlpha(by: 0.5).alpha, 0.5)
        XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: ViewNode(backgroundColor: authored)))
        XCTAssertFalse(
            RetainedLazyListPaintAlpha.isUnit(in: [CanvasGraphicsContext.Operation.fillRect(rect, authored)]))
    }

    func testNativeSolidPaintFieldsRejectOverrangeNegativeAndNonfiniteAlpha() async {
        let required: [ReferenceWritableKeyPath<ViewNode, Color>] = [
            \.borderColor, \.outlineColor, \.shadowColor,
            \.scrollIndicatorColor, \.scrollIndicatorIdleColor, \.scrollIndicatorHoverColor,
            \.scrollIndicatorActiveColor,
        ]
        let optional: [ReferenceWritableKeyPath<ViewNode, Color?>] = [\.backgroundColor, \.listRowPlatterColor]
        for alpha in invalidAlphas {
            for field in required {
                let node = ViewNode()
                node[keyPath: field] = color(alpha)
                XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: node))
            }
            for field in optional {
                let node = ViewNode()
                node[keyPath: field] = color(alpha)
                XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: node))
            }
        }
    }

    func testListTintValuesAreCheckedWithoutResolvingListChrome() async {
        for alpha in invalidAlphas {
            XCTAssertFalse(
                RetainedLazyListPaintAlpha.isUnit(
                    in: ViewNode(listRowSeparatorTint: RetainedListSeparatorTint(color: color(alpha)))))
            XCTAssertFalse(
                RetainedLazyListPaintAlpha.isUnit(
                    in: ViewNode(listSectionSeparatorTint: RetainedListSeparatorTint(color: color(alpha)))))
            XCTAssertFalse(
                RetainedLazyListPaintAlpha.isUnit(
                    in: ViewNode(listItemTint: RetainedListItemTint(color: color(alpha), kind: .preferred))))
        }
    }

    func testEveryNativeGradientStopIsCheckedForAllGradientKinds() async {
        for alpha in invalidAlphas {
            let linear = ramp(alpha)
            let values: [GradientType] = [
                .linear(linear),
                .radial(RadialGradient(center: .zero, radius: 8, stops: linear.stops)),
                .conic(ConicGradient(center: .zero, stops: linear.stops)),
            ]
            for value in values {
                XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: ViewNode(backgroundGradient: value)))
                XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: ViewNode(borderGradient: value)))
            }
        }
    }

    func testGradientInspectionDoesNotHideInvalidStopsThroughRenderingNormalization() async {
        var gradient = ramp(1)
        gradient.stops.insert(GradientStop(color: color(2), position: .nan), at: 1)
        XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: ViewNode(backgroundGradient: .linear(gradient))))
        XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: gradients(gradient)))
    }

    func testTextForegroundAndDecorationAlphaAreCheckedForNativeAndCanvasText() async {
        for alpha in invalidAlphas {
            var underline = PixelTextStyle(color: .white, underline: true)
            underline.underlineColor = color(alpha)
            var strike = PixelTextStyle(color: .white, strikethrough: true)
            strike.strikethroughColor = color(alpha)
            for style in [PixelTextStyle(color: color(alpha)), underline, strike] {
                XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: ViewNode(text: "Text", textStyle: style)))
                XCTAssertFalse(
                    RetainedLazyListPaintAlpha.isUnit(in: [
                        CanvasGraphicsContext.Operation.drawText("Text", rect, style)
                    ]))
            }
        }
    }

    func testNestedTextSpansAreInspectedIterativelyIncludingTheirDecorations() async {
        var style = PixelTextStyle(color: .white, strikethrough: true)
        style.strikethroughColor = color(.nan)
        for _ in 0..<128 {
            style = PixelTextStyle(color: .white, spans: [TextSpan(text: "Nested", style: style)])
        }
        XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: ViewNode(textStyle: style)))
        XCTAssertFalse(
            RetainedLazyListPaintAlpha.isUnit(in: [CanvasGraphicsContext.Operation.drawText("Nested", rect, style)]))
    }

    func testColorMultiplyAlphaIsCheckedAcrossTheWholeNativeEffectChain() async {
        for alpha in invalidAlphas {
            XCTAssertFalse(
                RetainedLazyListPaintAlpha.isUnit(
                    in: ViewNode(colorEffects: [.brightness(0.2), .colorInvert, .colorMultiply(color(alpha))])))
        }
        XCTAssertTrue(
            RetainedLazyListPaintAlpha.isUnit(
                in: ViewNode(colorEffects: [.luminanceToAlpha, .colorMultiply(color(0.5)), .contrast(2)])))
    }

    func testAllCanvasSolidAndGradientOperationFamiliesRejectRawInvalidAlpha() async {
        for alpha in invalidAlphas {
            for operation in solids(color(alpha)) + gradients(ramp(alpha)) {
                XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: [operation]))
            }
        }
    }

    func testCanvasImageOpacityIsCheckedWithoutInspectingOrRenderingPixels() async {
        let bitmap = bitmap()
        for alpha in invalidAlphas {
            XCTAssertFalse(
                RetainedLazyListPaintAlpha.isUnit(in: [CanvasGraphicsContext.Operation.drawImage(bitmap, rect, alpha)]))
        }
        for alpha: Float in [0, 0.25, 1] {
            XCTAssertTrue(
                RetainedLazyListPaintAlpha.isUnit(in: [CanvasGraphicsContext.Operation.drawImage(bitmap, rect, alpha)]))
        }
    }

    func testCanvasSymbolChecksOnlyOccurrenceOpacityAndDoesNotInvokeItsCanvas() async throws {
        var drawCalls = 0
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    backgroundColor: color(2), canvasDraw: { _, _ in drawCalls += 1 },
                    preferredSize: Size(width: 8, height: 8))
            })
        XCTAssertEqual(drawCalls, 0)
        for alpha in invalidAlphas {
            XCTAssertFalse(
                RetainedLazyListPaintAlpha.isUnit(
                    in: [CanvasGraphicsContext.Operation.drawSymbol(symbol, rect, .identity, alpha)]))
        }
        for alpha: Float in [0, 0.25, 1] {
            XCTAssertTrue(
                RetainedLazyListPaintAlpha.isUnit(
                    in: [CanvasGraphicsContext.Operation.drawSymbol(symbol, rect, .identity, alpha)]))
        }
        XCTAssertEqual(drawCalls, 0)
    }

    func testUnitRangeNativeAndCanvasValuesRemainEligible() async {
        var style = PixelTextStyle(color: color(0.5), underline: true, strikethrough: true)
        style.underlineColor = color(0)
        style.strikethroughColor = color(1)
        style.spans = [TextSpan(text: "Span", style: PixelTextStyle(color: color(0.25)))]
        let node = ViewNode(
            backgroundColor: color(0), backgroundGradient: .linear(ramp(0.5)), textStyle: style,
            borderColor: color(0.25), borderGradient: .linear(ramp(1)), outlineColor: color(1), shadowColor: color(0.5),
            colorEffects: [.colorMultiply(color(1))], listRowPlatterColor: color(0.5))
        XCTAssertTrue(RetainedLazyListPaintAlpha.isUnit(in: node))
        let operations =
            solids(color(0.25)) + gradients(ramp(0.5)) + [
                .drawText("Text", rect, style), .drawImage(bitmap(), rect, 0.5), .pushClip(rect), .popClip,
            ]
        XCTAssertTrue(RetainedLazyListPaintAlpha.isUnit(in: operations))
        XCTAssertTrue(RetainedLazyListPaintAlpha.isUnit(in: [CanvasGraphicsContext.Operation]()))
    }

    func testScanDoesNotWalkDescendantsInvokeCallbacksOrOwnTheOpacityWitness() async {
        var drawCalls = 0
        let root = ViewNode(canvasDraw: { _, _ in drawCalls += 1 }, opacity: 2)
        let child = ViewNode(backgroundColor: color(2))
        root.setChildren([child])
        XCTAssertTrue(RetainedLazyListPaintAlpha.isUnit(in: root))
        XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: child))
        XCTAssertEqual(drawCalls, 0)
    }

    func testInspectionBudgetIsSharedAcrossOperationsAndGradientStops() async {
        let limit = RetainedLazyListPaintSource.maximumInspectedEntries
        XCTAssertFalse(
            RetainedLazyListPaintAlpha.isUnit(
                in: Array(repeating: CanvasGraphicsContext.Operation.popClip, count: limit + 1)))
        let stops = Array(repeating: GradientStop(color: .white, position: 0), count: limit / 2)
        let gradient = LinearGradient(stops: stops)
        XCTAssertTrue(
            RetainedLazyListPaintAlpha.isUnit(in: [CanvasGraphicsContext.Operation.fillRectGradient(rect, gradient)]))
        XCTAssertFalse(
            RetainedLazyListPaintAlpha.isUnit(
                in: [
                    CanvasGraphicsContext.Operation.fillRectGradient(rect, gradient), .fillRectGradient(rect, gradient),
                ]))
        XCTAssertFalse(
            RetainedLazyListPaintAlpha.isUnit(
                in: ViewNode(backgroundGradient: .linear(gradient), borderGradient: .linear(gradient))))
    }

    func testInspectionBudgetRejectsUnboundedSpansBeforeGrowingTheWorkList() async {
        let spans = Array(
            repeating: TextSpan(text: "", style: PixelTextStyle(color: .white)),
            count: RetainedLazyListPaintSource.maximumInspectedEntries)
        let style = PixelTextStyle(color: .white, spans: spans)
        XCTAssertFalse(RetainedLazyListPaintAlpha.isUnit(in: ViewNode(textStyle: style)))
        XCTAssertFalse(
            RetainedLazyListPaintAlpha.isUnit(in: [CanvasGraphicsContext.Operation.drawText("", rect, style)]))
    }
}
