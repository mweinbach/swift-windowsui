import XCTest
import SwiftWindowsCore
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUILabelTests: XCTestCase {
    @MainActor
    func testLabelForegroundStyleOverloadsReturnLabelAndMapToRetainedColor() async {
        let primaryColor = Color(red: 0.7, green: 0.1, blue: 0.2, alpha: 1)
        let secondaryColor = Color(red: 0.1, green: 0.7, blue: 0.2, alpha: 1)
        let gradient = LinearGradient(
            startColor: Color(red: 0.2, green: 0.3, blue: 0.9, alpha: 1),
            endColor: Color(red: 0.9, green: 0.6, blue: 0.1, alpha: 1),
            axis: .horizontal
        )

        let colorLabel: Label = Label("COLOR", systemImage: "gear").foregroundStyle(primaryColor)
        let storedStyleLabel: Label = Label("STYLE", systemImage: "gear")
            .foregroundStyle(ForegroundStyle.color(secondaryColor))
        let gradientLabel: Label = Label("GRADIENT", systemImage: "gear").foregroundStyle(gradient)
        let multiLabel: Label = Label("MULTI", systemImage: "gear")
            .foregroundStyle(primaryColor, secondaryColor, SwiftWindowsCore.Color.blue)
        let multiGradientLabel: Label = Label("MULTIGRADIENT", systemImage: "gear")
            .foregroundStyle(gradient, gradient)

        assertLabel(colorLabel, hasTextColor: primaryColor, iconColor: primaryColor)
        assertLabel(storedStyleLabel, hasTextColor: secondaryColor, iconColor: secondaryColor)
        assertLabel(gradientLabel, hasTextColor: gradient.startColor, iconColor: gradient.startColor)
        assertLabel(multiLabel, hasTextColor: primaryColor, iconColor: primaryColor)
        assertLabel(multiGradientLabel, hasTextColor: gradient.startColor, iconColor: gradient.startColor)
    }
}

@MainActor
private func assertLabel(_ label: Label, hasTextColor textColor: Color, iconColor: Color) {
    let node = makeNode(label)

    XCTAssertEqual(node.children.count, 2)
    XCTAssertEqual(node.children[0].textStyle.color, iconColor)
    XCTAssertEqual(node.children[1].textStyle.color, textColor)
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
