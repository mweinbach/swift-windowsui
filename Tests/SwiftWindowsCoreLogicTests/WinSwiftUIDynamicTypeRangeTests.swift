import Foundation
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUIDynamicTypeRangeTests: XCTestCase {
    func testClosedRangeClampsEnvironmentScaledMetricAndRetainedTextTogether() async {
        await MainActor.run {
            let node = makeDynamicTypeRangeNode(
                DynamicTypeRangeProbe()
                    .dynamicTypeSize(.small ... .xxLarge)
                    .dynamicTypeSize(.accessibility3)
            )

            XCTAssertEqual(node.text, "5:12.4")
            XCTAssertEqual(node.textStyle.nativeFontSize ?? 0, 12.4, accuracy: 0.001)
        }
    }

    func testPartialUpperBoundClampsEnvironmentAndScaledMetric() async {
        await MainActor.run {
            let node = makeDynamicTypeRangeNode(
                DynamicTypeRangeProbe()
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .dynamicTypeSize(.accessibility2)
            )

            XCTAssertEqual(node.text, "3:10.0")
            XCTAssertEqual(node.textStyle.nativeFontSize ?? 0, 10, accuracy: 0.001)
        }
    }

    func testPartialLowerBoundClampsEnvironmentAndScaledMetric() async {
        await MainActor.run {
            let node = makeDynamicTypeRangeNode(
                DynamicTypeRangeProbe()
                    .dynamicTypeSize(DynamicTypeSize.xLarge...)
                    .dynamicTypeSize(.small)
            )

            XCTAssertEqual(node.text, "4:11.2")
            XCTAssertEqual(node.textStyle.nativeFontSize ?? 0, 11.2, accuracy: 0.001)
        }
    }

    func testNestedLowerBoundCannotDiscardAncestorUpperBound() async {
        await MainActor.run {
            let node = makeDynamicTypeRangeNode(
                DynamicTypeRangeProbe()
                    .dynamicTypeSize(.accessibility5)
                    .dynamicTypeSize(DynamicTypeSize.medium...)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
            )

            XCTAssertEqual(node.text, "4:11.2")
            XCTAssertEqual(node.textStyle.nativeFontSize ?? 0, 11.2, accuracy: 0.001)
        }
    }

    func testNestedUpperBoundCannotDiscardAncestorLowerBound() async {
        await MainActor.run {
            let node = makeDynamicTypeRangeNode(
                DynamicTypeRangeProbe()
                    .dynamicTypeSize(.xSmall)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .dynamicTypeSize(DynamicTypeSize.xLarge...)
            )

            XCTAssertEqual(node.text, "4:11.2")
            XCTAssertEqual(node.textStyle.nativeFontSize ?? 0, 11.2, accuracy: 0.001)
        }
    }

    func testDisjointNestedRangeRemainsWithinAncestorBounds() async {
        await MainActor.run {
            let node = makeDynamicTypeRangeNode(
                DynamicTypeRangeProbe()
                    .dynamicTypeSize(.accessibility1 ... .accessibility3)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .dynamicTypeSize(.accessibility5)
            )

            XCTAssertEqual(node.text, "4:11.2")
            XCTAssertEqual(node.textStyle.nativeFontSize ?? 0, 11.2, accuracy: 0.001)
        }
    }
}

@MainActor
private struct DynamicTypeRangeProbe: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var spacing = 10.0

    var body: some View {
        Text("\(dynamicTypeSize.rawValue):\(String(format: "%.1f", spacing))")
            .font(.system(size: 10))
    }
}

@MainActor
private func makeDynamicTypeRangeNode<V: View>(_ view: V) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 640, height: 480) },
        invalidateHandler: {}
    )
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}
