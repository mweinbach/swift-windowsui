import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private func makeNode<V: View>(_ view: V) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 800, height: 600) },
        invalidateHandler: {}
    )
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

final class WinSwiftUIChartMapTipTests: XCTestCase {
    func testChartRendersPlaceholderPanel() async {
        await MainActor.run {
            let node = makeNode(
                Chart {
                    BarMark(x: PlottableValue("X", 1), y: PlottableValue("Y", 2))
                })
            XCTAssertEqual(node.preferredSize, Size(width: 300, height: 200))
            XCTAssertFalse(node.isHitTestVisible)
        }
    }

    func testBarMarkRendersPlaceholderPanel() async {
        await MainActor.run {
            let node = makeNode(BarMark(x: PlottableValue("X", 1), y: PlottableValue("Y", 2)))
            XCTAssertEqual(node.preferredSize, Size(width: 40, height: 40))
            XCTAssertFalse(node.isHitTestVisible)
        }
    }

    func testMapRendersPlaceholderPanel() async {
        await MainActor.run {
            let node = makeNode(Map())
            XCTAssertEqual(node.preferredSize, Size(width: 300, height: 200))
            XCTAssertFalse(node.isHitTestVisible)
        }
    }

    func testMapStyleModifierDoesNotBreakRendering() async {
        await MainActor.run {
            let node = makeNode(Map().mapStyle(.standard))
            XCTAssertEqual(node.preferredSize, Size(width: 300, height: 200))
        }
    }

    func testTipViewRendersPlaceholderPanel() async {
        await MainActor.run {
            struct TestTip: Tip {
                typealias Title = Text
                typealias Message = Text
                typealias Image = WinSwiftUI.Image
                var title: Text { Text("Test") }
            }
            let node = makeNode(TipView(TestTip()))
            XCTAssertEqual(node.preferredSize, Size(width: 200, height: 80))
            XCTAssertFalse(node.isHitTestVisible)
        }
    }

    func testChartStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            let node = makeNode(
                Chart {
                    BarMark(x: PlottableValue("X", 1), y: PlottableValue("Y", 2))
                }
                .chartStyle(.automatic)
            )
            XCTAssertEqual(node.preferredSize, Size(width: 300, height: 200))
        }
    }

    func testTipViewStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct TestTip: Tip {
                typealias Title = Text
                typealias Message = Text
                typealias Image = WinSwiftUI.Image
                var title: Text { Text("Test") }
            }
            let node = makeNode(
                TipView(TestTip())
                    .tipViewStyle(.inline)
            )
            XCTAssertEqual(node.preferredSize, Size(width: 200, height: 80))
        }
    }
}
