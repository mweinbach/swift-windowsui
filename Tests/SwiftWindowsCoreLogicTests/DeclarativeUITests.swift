import XCTest
import SwiftWindowsCore
import SwiftWindowsLayout
@testable import SwiftWindowsUI

final class DeclarativeUITests: XCTestCase {
    func testDeclarativeStackBuildsExpectedTree() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let component = UI.stackPanel(
                preferredSize: Size(width: 200, height: 120),
                backgroundColor: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                cornerRadius: 12,
                stackLayout: .vertical(spacing: 8, alignment: .stretch)
            ) {
                UI.label("HEADER", color: .white, scale: 2)
                UI.button(
                    title: "GO",
                    preferredSize: Size(width: 120, height: 40),
                    cornerRadius: 10,
                    palette: SurfacePalette(
                        idle: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                        focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                        pressed: Color(red: 0.4, green: 0.5, blue: 0.6, alpha: 1)
                    )
                )
            }

            let node = component.makeNode(runtime: runtime)

            guard case .stack(let stackLayout) = node.layoutMode else {
                return XCTFail("Expected stack layout")
            }

            XCTAssertEqual(stackLayout, .vertical(spacing: 8, alignment: .stretch))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "HEADER")
            XCTAssertTrue(node.children[1].isFocusable)
        }
    }

    func testDeclarativeScrollPanelConfiguresScrollState() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let component = UI.scrollPanel(
                axis: .vertical,
                preferredSize: Size(width: 160, height: 90),
                backgroundColor: .black,
                stackLayout: .vertical(spacing: 6, alignment: .stretch),
                scrollStep: 24
            ) {
                UI.label("ONE")
                UI.label("TWO")
                UI.label("THREE")
            }

            let node = component.makeNode(runtime: runtime)

            XCTAssertEqual(node.scrollAxis, .vertical)
            XCTAssertEqual(node.scrollStep, 24)
            XCTAssertTrue(node.showsScrollIndicator)
            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.children.count, 3)
        }
    }

    func testDeclarativeSectionAndListRowBuildExpectedChrome() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let component = UI.section(
                title: "DETAILS",
                preferredSize: Size(width: 220, height: 180)
            ) {
                UI.listRow(
                    title: "PIPELINE",
                    detail: "GPU READY",
                    accentColor: Color(red: 0.4, green: 0.7, blue: 0.9, alpha: 1),
                    preferredSize: Size(width: 184, height: 68)
                )
            }

            let node = component.makeNode(runtime: runtime)

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "DETAILS")
            XCTAssertTrue(node.children[1].isFocusable)
        }
    }

    func testDeclarativeSplitViewBuildsPaneHosts() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let component = UI.splitView(
                axis: .horizontal,
                frame: Rect(x: 0, y: 0, width: 300, height: 120),
                ratio: 0.25
            ) {
                UI.section(title: "LEFT") {
                    UI.label("NAV")
                }
            } secondary: {
                UI.section(title: "RIGHT") {
                    UI.label("CONTENT")
                }
            }

            let node = component.makeNode(runtime: runtime)

            XCTAssertEqual(node.children.count, 3)
            XCTAssertEqual(node.children[0].children.count, 1)
            XCTAssertEqual(node.children[1].children.count, 1)
        }
    }
}
