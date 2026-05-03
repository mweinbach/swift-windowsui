import XCTest
import SwiftWindowsCore
@testable import SwiftWindowsUI

final class ComponentHostTests: XCTestCase {
    func testSetContentBuildsDeclarativeTreeIntoRuntimeRoot() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)

            host.setContent {
                UI.label("HEADER")
                UI.button(
                    title: "GO",
                    preferredSize: Size(width: 100, height: 40),
                    cornerRadius: 12,
                    palette: SurfacePalette(
                        idle: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                        focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                        pressed: Color(red: 0.4, green: 0.5, blue: 0.6, alpha: 1)
                    )
                )
            }

            XCTAssertEqual(runtime.root.children.count, 2)
            XCTAssertEqual(runtime.root.children[0].text, "HEADER")
            XCTAssertTrue(runtime.root.children[1].isFocusable)
        }
    }

    func testReloadRebuildsTreeFromUpdatedState() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var title = "FIRST"

            host.setContent {
                UI.label(title)
            }
            XCTAssertEqual(runtime.root.children.first?.text, "FIRST")

            title = "SECOND"
            host.reload()

            XCTAssertEqual(runtime.root.children.count, 1)
            XCTAssertEqual(runtime.root.children.first?.text, "SECOND")
        }
    }

    func testReloadUpdatesEffectPropertiesInPlace() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var opacity = 0.25
            var blurRadius = 2.0
            var zIndex = 1.0
            var transform = Transform2D.translation(x: 4, y: 6)

            host.setContent {
                Component { _ in
                    ViewNode(
                        backgroundColor: .white,
                        blurRadius: blurRadius,
                        opacity: opacity,
                        zIndex: zIndex,
                        transform: transform
                    )
                }
            }

            let node = runtime.root.children[0]
            opacity = 0.75
            blurRadius = 8
            zIndex = 3
            transform = .scale(x: 2, y: 2)
            host.reload()

            XCTAssertTrue(runtime.root.children[0] === node)
            XCTAssertEqual(node.opacity, 0.75, accuracy: 0.001)
            XCTAssertEqual(node.blurRadius, 8)
            XCTAssertEqual(node.zIndex, 3)
            XCTAssertEqual(node.transform.scaleX, 2, accuracy: 0.001)
        }
    }
}
