import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
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
            var contextMenuEvents: [String] = []

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
                    let borderStrokeStyle = useSecondState
                        ? StrokeStyle(lineWidth: 5, dashPattern: [3, 1], dashOffset: 2, lineCap: .round, lineJoin: .bevel, miterLimit: 4)
                        : StrokeStyle(lineWidth: 2, dashPattern: [1, 2], dashOffset: 0.5, lineCap: .square, lineJoin: .round, miterLimit: 8)
                    let borderGradient = useSecondState
                        ? LinearGradient(
                            startColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                            endColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                            axis: .horizontal
                        )
                        : LinearGradient(startColor: .white, endColor: .black, axis: .vertical)
                    let clipFillStyle = RetainedClipFillStyle(
                        eoFill: useSecondState,
                        antialiased: !useSecondState
                    )
                    let scrollOffset = useSecondState ? 48.0 : 12.0
                    let submitLabel: RetainedSubmitLabel = useSecondState ? .search : .return
                    let caretOffset = useSecondState ? 4 : 1
                    let symbolVariableValue = useSecondState ? 0.75 : 0.25
                    let imageResizingMode: RetainedImageResizingMode = useSecondState ? .tile : .stretch
                    let imageCapInsets = useSecondState
                        ? EdgeInsets(top: 5, leading: 6, bottom: 7, trailing: 8)
                        : EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
                    let imageRenderingMode: RetainedImageRenderingMode = useSecondState ? .original : .template
                    let imageInterpolation: RetainedImageInterpolation = useSecondState ? .high : .low
                    let imageAntialiased = useSecondState
                    let isSubmitScopeBoundary = useSecondState
                    let matchedGeometryEffect = useSecondState
                        ? RetainedMatchedGeometryEffect(
                            namespaceID: "secondNamespace",
                            elementID: "secondElement",
                            properties: 3,
                            anchor: Point(x: 1, y: 1),
                            isSource: false
                        )
                        : RetainedMatchedGeometryEffect(
                            namespaceID: "firstNamespace",
                            elementID: "firstElement",
                            properties: 1,
                            anchor: Point(x: 0, y: 0),
                            isSource: true
                        )
                    let presentationChrome = useSecondState
                        ? RetainedPresentationChrome(
                            hasBackgroundOverride: true,
                            backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                            hasCornerRadiusOverride: true,
                            cornerRadius: 18,
                            hasDragIndicatorOverride: true,
                            showsDragIndicator: false,
                            hasDetentsOverride: true,
                            detents: [.fraction(0.5), .large],
                            selectedDetent: .fraction(0.5)
                        )
                        : RetainedPresentationChrome(
                            hasBackgroundOverride: true,
                            backgroundGradient: LinearGradient(
                                startColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                                endColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                                axis: .vertical
                            ),
                            hasCornerRadiusOverride: true,
                            cornerRadius: 8,
                            hasDragIndicatorOverride: true,
                            showsDragIndicator: true,
                            hasDetentsOverride: true,
                            detents: [.height(240), .medium],
                            selectedDetent: .height(240)
                        )

                    node.text = label
                    node.opacity = opacity
                    node.zIndex = zIndex
                    node.layoutConstraints = layoutConstraints
                    node.fixedSizeAxes = fixedSizeAxes
                    node.transform = transform
                    node.borderGradient = borderGradient
                    node.borderStrokeStyle = borderStrokeStyle
                    node.clipFillStyle = clipFillStyle
                    node.scrollOffset = scrollOffset
                    node.textInputSubmitLabel = submitLabel
                    node.textInputCaretOffset = caretOffset
                    node.symbolVariableValue = symbolVariableValue
                    node.imageResizingMode = imageResizingMode
                    node.imageCapInsets = imageCapInsets
                    node.imageRenderingMode = imageRenderingMode
                    node.imageInterpolation = imageInterpolation
                    node.imageAntialiased = imageAntialiased
                    node.isSubmitScopeBoundary = isSubmitScopeBoundary
                    node.matchedGeometryEffect = matchedGeometryEffect
                    node.presentationChrome = presentationChrome
                    node.isToolbarContainer = useSecondState
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
                    node.onContextMenu = { _ in
                        contextMenuEvents.append(eventLabel)
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
            XCTAssertEqual(firstNode?.borderGradient, LinearGradient(startColor: .white, endColor: .black, axis: .vertical))
            XCTAssertEqual(firstNode?.borderStrokeStyle, StrokeStyle(lineWidth: 2, dashPattern: [1, 2], dashOffset: 0.5, lineCap: .square, lineJoin: .round, miterLimit: 8))
            XCTAssertEqual(firstNode?.clipFillStyle, RetainedClipFillStyle(eoFill: false, antialiased: true))
            XCTAssertEqual(firstNode?.scrollOffset, 12)
            XCTAssertEqual(firstNode?.textInputSubmitLabel, .return)
            XCTAssertEqual(firstNode?.textInputCaretOffset, 1)
            XCTAssertEqual(firstNode?.symbolVariableValue, 0.25)
            XCTAssertEqual(firstNode?.imageResizingMode, .stretch)
            XCTAssertEqual(firstNode?.imageCapInsets, EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
            XCTAssertEqual(firstNode?.imageRenderingMode, .template)
            XCTAssertEqual(firstNode?.imageInterpolation, .low)
            XCTAssertEqual(firstNode?.imageAntialiased, false)
            XCTAssertEqual(firstNode?.isSubmitScopeBoundary, false)
            XCTAssertEqual(
                firstNode?.matchedGeometryEffect,
                RetainedMatchedGeometryEffect(
                    namespaceID: "firstNamespace",
                    elementID: "firstElement",
                    properties: 1,
                    anchor: Point(x: 0, y: 0),
                    isSource: true
                )
            )
            XCTAssertEqual(
                firstNode?.presentationChrome,
                RetainedPresentationChrome(
                    hasBackgroundOverride: true,
                    backgroundGradient: LinearGradient(
                        startColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                        endColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                        axis: .vertical
                    ),
                    hasCornerRadiusOverride: true,
                    cornerRadius: 8,
                    hasDragIndicatorOverride: true,
                    showsDragIndicator: true,
                    hasDetentsOverride: true,
                    detents: [.height(240), .medium],
                    selectedDetent: .height(240)
                )
            )
            XCTAssertEqual(firstNode?.isToolbarContainer, false)
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
            XCTAssertEqual(
                reusedNode?.borderGradient,
                LinearGradient(
                    startColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                    endColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                    axis: .horizontal
                )
            )
            XCTAssertEqual(reusedNode?.borderStrokeStyle, StrokeStyle(lineWidth: 5, dashPattern: [3, 1], dashOffset: 2, lineCap: .round, lineJoin: .bevel, miterLimit: 4))
            XCTAssertEqual(reusedNode?.clipFillStyle, RetainedClipFillStyle(eoFill: true, antialiased: false))
            XCTAssertEqual(reusedNode?.scrollOffset, 48)
            XCTAssertEqual(reusedNode?.textInputSubmitLabel, .search)
            XCTAssertEqual(reusedNode?.textInputCaretOffset, 4)
            XCTAssertEqual(reusedNode?.symbolVariableValue, 0.75)
            XCTAssertEqual(reusedNode?.imageResizingMode, .tile)
            XCTAssertEqual(reusedNode?.imageCapInsets, EdgeInsets(top: 5, leading: 6, bottom: 7, trailing: 8))
            XCTAssertEqual(reusedNode?.imageRenderingMode, .original)
            XCTAssertEqual(reusedNode?.imageInterpolation, .high)
            XCTAssertEqual(reusedNode?.imageAntialiased, true)
            XCTAssertEqual(reusedNode?.isSubmitScopeBoundary, true)
            XCTAssertEqual(
                reusedNode?.matchedGeometryEffect,
                RetainedMatchedGeometryEffect(
                    namespaceID: "secondNamespace",
                    elementID: "secondElement",
                    properties: 3,
                    anchor: Point(x: 1, y: 1),
                    isSource: false
                )
            )
            XCTAssertEqual(
                reusedNode?.presentationChrome,
                RetainedPresentationChrome(
                    hasBackgroundOverride: true,
                    backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                    hasCornerRadiusOverride: true,
                    cornerRadius: 18,
                    hasDragIndicatorOverride: true,
                    showsDragIndicator: false,
                    hasDetentsOverride: true,
                    detents: [.fraction(0.5), .large],
                    selectedDetent: .fraction(0.5)
                )
            )
            XCTAssertEqual(reusedNode?.isToolbarContainer, true)
            XCTAssertEqual(reusedNode?.isFocusable, true)
            XCTAssertEqual(reusedNode?.animationStates[.opacity]?.endValue, 0.55)

            reusedNode?.onPointerDown?()
            XCTAssertEqual(pointerDownEvents, ["second"])
            reusedNode?.onContextMenu?(Point(x: 4, y: 8))
            XCTAssertEqual(contextMenuEvents, ["second"])
        }
    }
}
