import XCTest
import SwiftWindowsCore
import SwiftWindowsLayout
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

    func testReloadReusesNodeWithFreshStateAndHandlers() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var useSecondState = false
            var pointerDownEvents: [String] = []

            host.setContent {
                Component { _ in
                    let node = ViewNode()
                    let label = useSecondState ? "SECOND" : "FIRST"
                    let eventLabel = useSecondState ? "second" : "first"
                    let opacity = useSecondState ? 0.85 : 0.25
                    let zIndex = useSecondState ? 9.0 : 2.0
                    let layoutConstraints = useSecondState
                        ? LayoutConstraints(minWidth: 24, maxWidth: 72, minHeight: 12, maxHeight: 36)
                        : LayoutConstraints(minWidth: 8, maxWidth: 32, minHeight: 4, maxHeight: 16)
                    let fixedSizeAxes = useSecondState
                        ? FixedSizeAxes(horizontal: false, vertical: true)
                        : FixedSizeAxes(horizontal: true, vertical: false)
                    let transform = useSecondState
                        ? Transform2D.translation(x: 24, y: 36)
                        : Transform2D(translationX: 4, translationY: 5, scaleX: 1.25, scaleY: 0.75, rotation: 0.1)
                    let scrollOffset = useSecondState ? 48.0 : 12.0
                    let submitLabel: RetainedSubmitLabel = useSecondState ? .search : .return
                    let caretOffset = useSecondState ? 4 : 1
                    let symbolVariableValue = useSecondState ? 0.75 : 0.25
                    let isSubmitScopeBoundary = useSecondState

                    node.text = label
                    node.opacity = opacity
                    node.zIndex = zIndex
                    node.layoutConstraints = layoutConstraints
                    node.fixedSizeAxes = fixedSizeAxes
                    node.transform = transform
                    node.scrollOffset = scrollOffset
                    node.textInputSubmitLabel = submitLabel
                    node.textInputCaretOffset = caretOffset
                    node.symbolVariableValue = symbolVariableValue
                    node.isSubmitScopeBoundary = isSubmitScopeBoundary
                    node.isFocusable = useSecondState
                    node.animationStates = [
                        .opacity: AnimationState(
                            startValue: useSecondState ? 1.0 : 0.0,
                            endValue: useSecondState ? 0.55 : 0.15,
                            startTime: 10,
                            duration: 2
                        )
                    ]
                    node.onPointerDown = {
                        pointerDownEvents.append(eventLabel)
                    }
                    return node
                }
            }

            let firstNode = runtime.root.children.first
            XCTAssertNotNil(firstNode)
            XCTAssertEqual(firstNode?.text, "FIRST")
            XCTAssertEqual(firstNode?.opacity, 0.25)
            XCTAssertEqual(firstNode?.zIndex, 2)
            XCTAssertEqual(firstNode?.layoutConstraints, LayoutConstraints(minWidth: 8, maxWidth: 32, minHeight: 4, maxHeight: 16))
            XCTAssertEqual(firstNode?.fixedSizeAxes, FixedSizeAxes(horizontal: true, vertical: false))
            XCTAssertEqual(firstNode?.transform, Transform2D(translationX: 4, translationY: 5, scaleX: 1.25, scaleY: 0.75, rotation: 0.1))
            XCTAssertEqual(firstNode?.scrollOffset, 12)
            XCTAssertEqual(firstNode?.textInputSubmitLabel, .return)
            XCTAssertEqual(firstNode?.textInputCaretOffset, 1)
            XCTAssertEqual(firstNode?.symbolVariableValue, 0.25)
            XCTAssertEqual(firstNode?.isSubmitScopeBoundary, false)
            XCTAssertEqual(firstNode?.isFocusable, false)
            XCTAssertEqual(firstNode?.animationStates[.opacity]?.endValue, 0.15)

            useSecondState = true
            host.reload()

            let reusedNode = runtime.root.children.first
            XCTAssertTrue(firstNode === reusedNode)
            XCTAssertEqual(reusedNode?.text, "SECOND")
            XCTAssertEqual(reusedNode?.opacity, 0.85)
            XCTAssertEqual(reusedNode?.zIndex, 9)
            XCTAssertEqual(reusedNode?.layoutConstraints, LayoutConstraints(minWidth: 24, maxWidth: 72, minHeight: 12, maxHeight: 36))
            XCTAssertEqual(reusedNode?.fixedSizeAxes, FixedSizeAxes(horizontal: false, vertical: true))
            XCTAssertEqual(reusedNode?.transform, Transform2D.translation(x: 24, y: 36))
            XCTAssertEqual(reusedNode?.scrollOffset, 48)
            XCTAssertEqual(reusedNode?.textInputSubmitLabel, .search)
            XCTAssertEqual(reusedNode?.textInputCaretOffset, 4)
            XCTAssertEqual(reusedNode?.symbolVariableValue, 0.75)
            XCTAssertEqual(reusedNode?.isSubmitScopeBoundary, true)
            XCTAssertEqual(reusedNode?.isFocusable, true)
            XCTAssertEqual(reusedNode?.animationStates[.opacity]?.endValue, 0.55)

            reusedNode?.onPointerDown?()
            XCTAssertEqual(pointerDownEvents, ["second"])
        }
    }
}
