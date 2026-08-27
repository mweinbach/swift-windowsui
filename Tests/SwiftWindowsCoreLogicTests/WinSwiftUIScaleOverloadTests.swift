import SwiftWindowsCore
import SwiftWindowsUI
import XCTest

@testable import WinSwiftUI

@MainActor
final class WinSwiftUIScaleOverloadTests: XCTestCase {
    func testUnqualifiedScalarAnchorSelectsTwoDimensionalViewOverload() async {
        let node = makeNode(Text("Scale").scaleEffect(2, anchor: .topLeading))
        XCTAssertEqual(node.transform, Transform2D.scale(x: 2, y: 2))
    }

    func testUnqualifiedAxisAnchorSelectsTwoDimensionalViewOverload() async {
        let node = makeNode(Text("Scale").scaleEffect(x: 2, y: 3, anchor: .bottomTrailing))
        XCTAssertEqual(node.transform, Transform2D.scale(x: 2, y: 3))
    }

    func testTypedDepthAnchorsAndExplicitZRemainCallable() async {
        // These checks preserve source access to the existing planar adapter;
        // they do not qualify depth rendering or anchor placement.
        let scalar = makeNode(Text("Scale").scaleEffect(2, anchor: UnitPoint3D.topLeading))
        let axes = makeNode(Text("Scale").scaleEffect(x: 2, y: 3, z: 4, anchor: .bottomTrailing))
        XCTAssertEqual(scalar.transform, Transform2D.scale(x: 2, y: 2))
        XCTAssertEqual(axes.transform, Transform2D.scale(x: 2, y: 3))
    }

    func testUnqualifiedScalarAnchorSelectsTwoDimensionalVisualEffect() async {
        let effect = EmptyVisualEffect().scaleEffect(2, anchor: .topLeading)
        XCTAssertEqual(
            effect.retainedVisualEffectDescription,
            "identity.scaleEffect(x:2.0,y:2.0,anchor:0.0,0.0)")
    }

    func testUnqualifiedAxisAnchorSelectsTwoDimensionalVisualEffect() async {
        let effect = EmptyVisualEffect().scaleEffect(x: 2, y: 3, anchor: .bottomTrailing)
        XCTAssertEqual(
            effect.retainedVisualEffectDescription,
            "identity.scaleEffect(x:2.0,y:3.0,anchor:1.0,1.0)")
    }

    func testExplicitDepthVisualEffectsRemainCallable() async {
        let scalar = EmptyVisualEffect().scaleEffect(2, anchor: UnitPoint3D.topLeading)
        let axes = EmptyVisualEffect().scaleEffect(x: 2, y: 3, z: 4, anchor: .bottomTrailing)
        XCTAssertEqual(
            scalar.retainedVisualEffectDescription,
            "identity.scaleEffect3D(x:2.0,y:2.0,z:2.0,anchor:0.0,0.0,0.5)")
        XCTAssertEqual(
            axes.retainedVisualEffectDescription,
            "identity.scaleEffect3D(x:2.0,y:3.0,z:4.0,anchor:1.0,1.0,0.5)")
    }

    private func makeNode<V: View>(_ view: V) -> ViewNode {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 100, height: 100) }, invalidateHandler: {})
        return view.makeComponent(context: context).makeNode(runtime: runtime)
    }
}
