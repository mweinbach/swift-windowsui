import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
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

    func testReloadUpdatesVectorPathPropertiesInPlace() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var path = trianglePath(width: 10, height: 8)
            var fill = Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.8)
            var stroke = Color(red: 0.7, green: 0.8, blue: 0.9, alpha: 0.6)
            var strokeStyle = StrokeStyle(lineWidth: 1)

            host.setContent {
                Component { _ in
                    ViewNode(
                        renderPath: path,
                        pathFillColor: fill,
                        pathStrokeColor: stroke,
                        pathStrokeStyle: strokeStyle
                    )
                }
            }

            let node = runtime.root.children[0]
            path = trianglePath(width: 20, height: 16)
            fill = Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 1)
            stroke = Color(red: 1.0, green: 0.9, blue: 0.8, alpha: 1)
            strokeStyle = StrokeStyle(lineWidth: 3)
            host.reload()

            XCTAssertTrue(runtime.root.children[0] === node)
            XCTAssertEqual(node.renderPath, path)
            XCTAssertEqual(node.pathFillColor, fill)
            XCTAssertEqual(node.pathStrokeColor, stroke)
            XCTAssertEqual(node.pathStrokeStyle?.lineWidth, 3)
        }
    }

    func testReloadRefreshesHandlersInPlace() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var version = 1
            var activations: [Int] = []

            host.setContent {
                let capturedVersion = version
                Component { _ in
                    let node = ViewNode(backgroundColor: .white)
                    node.onActivate = {
                        activations.append(capturedVersion)
                    }
                    return node
                }
            }

            let node = runtime.root.children[0]
            node.onActivate?()

            version = 2
            host.reload()
            runtime.root.children[0].onActivate?()

            XCTAssertTrue(runtime.root.children[0] === node)
            XCTAssertEqual(activations, [1, 2])
        }
    }

    func testReloadUpdatesFocusabilityInPlace() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var isFocusable = true

            host.setContent {
                Component { _ in
                    ViewNode(backgroundColor: .white, isFocusable: isFocusable)
                }
            }

            let node = runtime.root.children[0]
            isFocusable = false
            host.reload()

            XCTAssertTrue(runtime.root.children[0] === node)
            XCTAssertFalse(node.isFocusable)
        }
    }
}

private func trianglePath(width: Double, height: Double) -> RenderPath {
    var path = RenderPath()
    path.move(to: Point(x: width * 0.5, y: 0))
    path.addLine(to: Point(x: width, y: height))
    path.addLine(to: Point(x: 0, y: height))
    path.close()
    return path
}
