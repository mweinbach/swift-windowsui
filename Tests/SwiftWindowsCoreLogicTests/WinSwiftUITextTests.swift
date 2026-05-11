import XCTest
import Foundation
import SwiftWindowsCore
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private struct TestStringFormatStyle: FormatStyle {
    func format(_ value: Int) -> String {
        "COUNT \(value)"
    }
}

private struct TestAttributedStringFormatStyle: FormatStyle {
    func format(_ value: Int) -> AttributedString {
        AttributedString("ATTR \(value)")
    }
}

final class WinSwiftUITextTests: XCTestCase {
    func testItalicModifierMapsToRetainedTextStyle() async {
        await MainActor.run {
            let directNode = makeNode(Text("ITALIC").italic())
            let combinedNode = makeNode(Text("A").italic() + Text("B"))
            let disabledNode = makeNode(Text("PLAIN").italic().italic(false))
            let inheritedNode = makeNode(
                VStack {
                    Text("INNER")
                    Text("PLAIN")
                        .italic(false)
                }
                .italic()
            )

            XCTAssertTrue(directNode.textStyle.isItalic)
            XCTAssertTrue(combinedNode.textStyle.isItalic)
            XCTAssertFalse(disabledNode.textStyle.isItalic)
            XCTAssertTrue(inheritedNode.children[0].textStyle.isItalic)
            XCTAssertFalse(inheritedNode.children[1].textStyle.isItalic)
        }
    }

    func testBooleanTextWeightAndMonospacedModifiersMapToRetainedStyle() async {
        await MainActor.run {
            let textBoldNode = makeNode(Text("BOLD").bold(false))
            let textMonospacedNode = makeNode(Text("CODE").monospaced(false))
            let inheritedNode = makeNode(
                VStack {
                    Text("CODE")
                    Text("PLAIN")
                        .monospaced(false)
                    Text("BOLD")
                        .bold(false)
                }
                .monospaced()
                .bold()
            )

            XCTAssertEqual(textBoldNode.textStyle.weight, .regular)
            XCTAssertEqual(textMonospacedNode.textStyle.fontFamily, "Segoe UI")
            XCTAssertEqual(inheritedNode.children[0].textStyle.fontFamily, "Cascadia Mono")
            XCTAssertEqual(inheritedNode.children[1].textStyle.fontFamily, "Segoe UI")
            XCTAssertEqual(inheritedNode.children[2].textStyle.weight, .regular)
        }
    }

    func testMonospacedDigitModifierMapsToRetainedTextStyle() async {
        await MainActor.run {
            let directNode = makeNode(Text("11:11").monospacedDigit())
            let combinedNode = makeNode(Text("A").monospacedDigit() + Text("1"))
            let inheritedNode = makeNode(
                VStack {
                    Text("12:34")
                }
                .monospacedDigit()
            )

            XCTAssertTrue(directNode.textStyle.monospacedDigits)
            XCTAssertTrue(combinedNode.textStyle.monospacedDigits)
            XCTAssertTrue(inheritedNode.children[0].textStyle.monospacedDigits)
        }
    }

    func testBaselineOffsetModifierMapsToRetainedTextTransform() async {
        await MainActor.run {
            let raisedNode = makeNode(Text("RAISED").baselineOffset(6))
            let loweredNode = makeNode(Text("LOWER").baselineOffset(-4))
            let resetNode = makeNode(Text("RESET").baselineOffset(6).baselineOffset(0))
            let combinedNode = makeNode(
                Text("A").baselineOffset(3) + Text("B").baselineOffset(9)
            )

            XCTAssertEqual(raisedNode.transform, Transform2D.translation(x: 0, y: -6))
            XCTAssertEqual(loweredNode.transform, Transform2D.translation(x: 0, y: 4))
            XCTAssertEqual(resetNode.transform, .identity)
            XCTAssertEqual(combinedNode.transform, Transform2D.translation(x: 0, y: -3))
        }
    }

    func testLineStyleDecorationModifiersMapToRetainedTextStyle() async {
        await MainActor.run {
            let directNode = makeNode(
                Text("DECORATED")
                    .underline(pattern: .dash, color: .blue)
                    .strikethrough(Text.LineStyle(pattern: .dashDotDot, color: .red))
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                    Text("PLAIN")
                        .underline(false)
                        .strikethrough(false)
                }
                .underline(pattern: .dot, color: .green)
                .strikethrough(pattern: .dashDot, color: .yellow)
            )

            XCTAssertTrue(directNode.textStyle.underline)
            XCTAssertEqual(directNode.textStyle.underlinePattern, .dash)
            XCTAssertEqual(directNode.textStyle.underlineColor, .blue)
            XCTAssertTrue(directNode.textStyle.strikethrough)
            XCTAssertEqual(directNode.textStyle.strikethroughPattern, .dashDotDot)
            XCTAssertEqual(directNode.textStyle.strikethroughColor, .red)

            let inheritedText = inheritedNode.children[0]
            XCTAssertTrue(inheritedText.textStyle.underline)
            XCTAssertEqual(inheritedText.textStyle.underlinePattern, .dot)
            XCTAssertEqual(inheritedText.textStyle.underlineColor, .green)
            XCTAssertTrue(inheritedText.textStyle.strikethrough)
            XCTAssertEqual(inheritedText.textStyle.strikethroughPattern, .dashDot)
            XCTAssertEqual(inheritedText.textStyle.strikethroughColor, .yellow)

            let plainText = inheritedNode.children[1]
            XCTAssertFalse(plainText.textStyle.underline)
            XCTAssertEqual(plainText.textStyle.underlinePattern, .solid)
            XCTAssertNil(plainText.textStyle.underlineColor)
            XCTAssertFalse(plainText.textStyle.strikethrough)
            XCTAssertEqual(plainText.textStyle.strikethroughPattern, .solid)
            XCTAssertNil(plainText.textStyle.strikethroughColor)
        }
    }

    func testAttributedStringInitializerFlattensToRetainedText() async {
        await MainActor.run {
            var attributed = AttributedString("HELLO")
            attributed.append(AttributedString(" WORLD"))

            let node = makeNode(Text(attributed))

            XCTAssertEqual(node.text, "HELLO WORLD")
        }
    }

    func testFormatStyleInitializerUsesStringOutput() async {
        await MainActor.run {
            let customNode = makeNode(Text(7, format: TestStringFormatStyle()))
            let numberNode = makeNode(
                Text(1234.5, format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)))
            )

            XCTAssertEqual(customNode.text, "COUNT 7")
            XCTAssertEqual(numberNode.text, "1,234.5")
        }
    }

    func testFormatStyleInitializerFlattensAttributedStringOutput() async {
        await MainActor.run {
            let node = makeNode(Text(9, format: TestAttributedStringFormatStyle()))

            XCTAssertEqual(node.text, "ATTR 9")
        }
    }

    func testFormatterInitializerUsesFoundationFormatterOutput() async {
        await MainActor.run {
            let numberFormatter = NumberFormatter()
            numberFormatter.locale = Locale(identifier: "en_US_POSIX")
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 1

            let dateFormatter = DateFormatter()
            dateFormatter.calendar = Calendar(identifier: .gregorian)
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

            let numberNode = makeNode(
                Text(NSNumber(value: 1234.5), formatter: numberFormatter)
            )
            let dateNode = makeNode(
                Text(Date(timeIntervalSince1970: 90_061), formatter: dateFormatter)
            )

            XCTAssertEqual(numberNode.text, "1,234.5")
            XCTAssertEqual(dateNode.text, "1970-01-02 01:01")
        }
    }

    func testFormatterInitializerFallsBackToStringDescription() async {
        await MainActor.run {
            let numberFormatter = NumberFormatter()
            let node = makeNode(Text("RAW", formatter: numberFormatter))

            XCTAssertEqual(node.text, "RAW")
        }
    }

    func testTimerCountdownText() async {
        await MainActor.run {
            let start = Date(timeIntervalSince1970: 0)
            let end = Date(timeIntervalSince1970: 7_505)
            let pauseTime = Date(timeIntervalSince1970: 305)

            let defaultNode = makeNode(
                Text(timerInterval: start...end, pauseTime: pauseTime)
            )
            let hiddenHoursNode = makeNode(
                Text(
                    timerInterval: start...end,
                    pauseTime: pauseTime,
                    countsDown: true,
                    showsHours: false
                )
            )

            XCTAssertEqual(defaultNode.text, "2:00:00")
            XCTAssertEqual(hiddenHoursNode.text, "120:00")
        }
    }

    func testTimerElapsedAndClampedText() async {
        await MainActor.run {
            let start = Date(timeIntervalSince1970: 0)
            let end = Date(timeIntervalSince1970: 600)

            let elapsedNode = makeNode(
                Text(
                    timerInterval: start...end,
                    pauseTime: Date(timeIntervalSince1970: 125),
                    countsDown: false
                )
            )
            let beforeIntervalNode = makeNode(
                Text(
                    timerInterval: start...end,
                    pauseTime: Date(timeIntervalSince1970: -20),
                    countsDown: false
                )
            )
            let afterIntervalNode = makeNode(
                Text(
                    timerInterval: start...end,
                    pauseTime: Date(timeIntervalSince1970: 800),
                    countsDown: true
                )
            )

            XCTAssertEqual(elapsedNode.text, "2:05")
            XCTAssertEqual(beforeIntervalNode.text, "0:00")
            XCTAssertEqual(afterIntervalNode.text, "0:00")
        }
    }
}

@MainActor
private func makeNode<V: View>(_ view: V) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: {
            Size(width: 800, height: 600)
        },
        invalidateHandler: {}
    )
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}
