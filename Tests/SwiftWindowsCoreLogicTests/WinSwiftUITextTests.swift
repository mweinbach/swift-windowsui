import XCTest
import Foundation
import SwiftWindowsCore
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUITextTests: XCTestCase {
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
