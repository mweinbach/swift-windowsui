import XCTest
import Foundation
import SwiftWindowsCore
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUITextTests: XCTestCase {
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
