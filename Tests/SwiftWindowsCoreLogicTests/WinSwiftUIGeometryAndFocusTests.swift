import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUIGeometryAndFocusTests: XCTestCase {
    func testTimelineViewRendersContentWithCurrentDate() async {
        await MainActor.run {
            let node = makeNode(
                TimelineView(.everyMinute) { context in
                    Text("DATE: \(context.date.timeIntervalSince1970)")
                }
            )
            XCTAssertTrue(allTexts(in: node).contains(where: { $0.hasPrefix("DATE: ") }))
        }
    }

    func testAnimationTimelineViewRendersContentWithAnimationSchedule() async {
        await MainActor.run {
            let node = makeNode(
                AnimationTimelineView(.animation) { context in
                    Text("ANIMATED: \(context.cadence == .live ? "LIVE" : "OTHER")")
                }
            )
            XCTAssertTrue(allTexts(in: node).contains("ANIMATED: LIVE"))
        }
    }

    func testGeometryGroupMapsToRetainedNodeFlag() async {
        await MainActor.run {
            let node = makeNode(
                Text("GROUPED")
                    .geometryGroup()
            )
            XCTAssertTrue(node.isGeometryGroup)
        }
    }

    func testInspectorColumnWidthMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("INSPECTOR")
                    .inspectorColumnWidth(240)
            )
            XCTAssertEqual(node.inspectorColumnWidth, 240)
        }
    }

    func testInspectorColumnWidthFractionMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("INSPECTOR")
                    .inspectorColumnWidthFraction(0.3)
            )
            XCTAssertEqual(node.inspectorColumnWidthFraction, 0.3)
        }
    }

    func testInspectorColumnWidthMinMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("INSPECTOR")
                    .inspectorColumnWidthMin(120)
            )
            XCTAssertEqual(node.inspectorColumnWidthMin, 120)
        }
    }

    func testFocusSectionMapsToRetainedNodeFlag() async {
        await MainActor.run {
            let node = makeNode(
                Text("SECTION")
                    .focusSection()
            )
            XCTAssertTrue(node.isFocusSection)
        }
    }

    func testFocusScopeMapsToRetainedNodeFlagAndNamespace() async {
        await MainActor.run {
            let ns = Namespace().wrappedValue
            let node = makeNode(
                Text("SCOPE")
                    .focusScope(ns)
            )
            XCTAssertTrue(node.isFocusSection)
            XCTAssertEqual(node.focusNamespace, ns)
        }
    }

    func testFocusDestinationMapsToRetainedNodeFlag() async {
        await MainActor.run {
            let node = makeNode(
                Text("DESTINATION")
                    .focusDestination()
            )
            XCTAssertTrue(node.isFocusDestination)
        }
    }

    func testPrefersDefaultFocusMapsToRetainedNodeProperties() async {
        await MainActor.run {
            let ns = Namespace().wrappedValue
            let node = makeNode(
                Text("PREFERS")
                    .prefersDefaultFocus(true, in: ns)
            )
            XCTAssertTrue(node.prefersDefaultFocus)
            XCTAssertEqual(node.focusNamespace, ns)
        }
    }

    func testDefaultFocusMapsToRetainedNodeProperties() async {
        await MainActor.run {
            let ns = Namespace().wrappedValue
            let focusState = FocusState<Bool>(wrappedValue: true)
            let node = makeNode(
                Text("DEFAULT")
                    .defaultFocus(focusState.projectedValue, in: ns)
            )
            XCTAssertTrue(node.isFocusable)
            XCTAssertTrue(node.isHitTestVisible)
            XCTAssertEqual(node.focusNamespace, ns)
        }
    }

    func testFileDialogCustomizationIDMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("DIALOG")
                    .fileDialogCustomizationID("com.example.export")
            )
            XCTAssertEqual(node.fileDialogCustomizationID, "com.example.export")
        }
    }

    func testFileDialogConfirmationLabelMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("DIALOG")
                    .fileDialogConfirmationLabel(Text("Confirm Save"))
            )
            XCTAssertEqual(node.fileDialogConfirmationLabel, "Confirm Save")
        }
    }

    func testFileDialogDefaultDirectoryMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let url = URL(fileURLWithPath: "C:\\Users\\Documents")
            let node = makeNode(
                Text("DIALOG")
                    .fileDialogDefaultDirectory(url)
            )
            XCTAssertEqual(node.fileDialogDefaultDirectory, url)
        }
    }

    func testFileDialogMessageMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("DIALOG")
                    .fileDialogMessage(Text("Select a file to import"))
            )
            XCTAssertEqual(node.fileDialogMessage, "Select a file to import")
        }
    }

    func testOnOpenURLProvidesHandledActionInEnvironment() async {
        await MainActor.run {
            var receivedURL: URL?
            struct OpenURLReaderView: View {
                @Environment(\.openURL) var openURL
                var body: some View {
                    Button("OPEN") {
                        openURL(URL(string: "https://example.com")!)
                    }
                }
            }

            let node = makeNode(
                OpenURLReaderView()
                    .onOpenURL { url in
                        receivedURL = url
                    }
            )
            node.onActivate?()
            XCTAssertEqual(receivedURL, URL(string: "https://example.com")!)
        }
    }

    func testTouchBarModifierDoesNotBreakViewRendering() async {
        await MainActor.run {
            let node = makeNode(
                Text("TOUCH")
                    .touchBar {
                        Button("TB") {}
                    }
            )
            XCTAssertEqual(node.text, "TOUCH")
        }
    }

    func testFixedFrameAlignsIntrinsicTextWithoutStretchingIt() async {
        await MainActor.run {
            let node = renderedNode(
                Text("FRAME")
                    .frame(width: 200, height: 80, alignment: .bottomTrailing)
            )
            let textNode = node.children[0]
            let intrinsicSize = textNode.intrinsicContentSize()

            XCTAssertEqual(node.resolvedFrame.size, Size(width: 200, height: 80))
            XCTAssertNil(textNode.preferredSize)
            XCTAssertGreaterThan(intrinsicSize.width, 0)
            XCTAssertLessThan(intrinsicSize.width, 200)
            XCTAssertLessThan(intrinsicSize.height, 80)
            XCTAssertEqual(textNode.resolvedFrame.size, intrinsicSize)
            XCTAssertEqual(textNode.resolvedFrame.maxX, 200, accuracy: 0.001)
            XCTAssertEqual(textNode.resolvedFrame.maxY, 80, accuracy: 0.001)
        }
    }

    func testNestedFixedFramesPreserveInnerDimensionsAndAlignment() async {
        await MainActor.run {
            let node = renderedNode(
                Text("INNER")
                    .frame(width: 80, height: 30, alignment: .topLeading)
                    .frame(width: 200, height: 80, alignment: .bottomTrailing)
            )
            let innerFrame = node.children[0]
            let textNode = innerFrame.children[0]

            XCTAssertEqual(node.resolvedFrame.size, Size(width: 200, height: 80))
            XCTAssertEqual(innerFrame.preferredSize, Size(width: 80, height: 30))
            XCTAssertEqual(innerFrame.resolvedFrame, Rect(x: 120, y: 50, width: 80, height: 30))
            XCTAssertNil(textNode.preferredSize)
            XCTAssertEqual(textNode.resolvedFrame.origin, .zero)
            XCTAssertEqual(textNode.resolvedFrame.size, textNode.intrinsicContentSize())
        }
    }

    func testFixedFramesProposeTheirSizeToFlexibleShapes() async {
        await MainActor.run {
            struct FrameTestShape: Shape {
                func path(in rect: Rect) -> Path {
                    var path = Path()
                    path.addRect(rect)
                    return path
                }
            }
            let rectangle = renderedNode(Rectangle().frame(width: 120, height: 40))
            let capsule = renderedNode(Capsule().frame(width: 120, height: 40))
            let arc = renderedNode(
                Arc(startAngle: .zero, endAngle: .degrees(180), clockwise: false)
                    .frame(width: 120, height: 40)
            )
            let trimmedShape = renderedNode(Rectangle().trim(from: 0, to: 0.5).frame(width: 120, height: 40))
            let customShape = renderedNode(FrameTestShape().frame(width: 120, height: 40))
            var canvasSize: SwiftWindowsCore.Size?
            let canvas = renderedNode(
                Canvas { _, size in
                    canvasSize = size
                }
                .frame(width: 120, height: 40)
            )

            for node in [rectangle, capsule, arc, trimmedShape, customShape, canvas] {
                let content = node.children[0]
                XCTAssertEqual(node.resolvedFrame.size, Size(width: 120, height: 40))
                XCTAssertNil(content.preferredSize)
                XCTAssertEqual(content.resolvedFrame, Rect(x: 0, y: 0, width: 120, height: 40))
            }
            XCTAssertEqual(capsule.children[0].cornerRadius, 20)
            XCTAssertEqual(canvasSize, SwiftWindowsCore.Size(width: 120, height: 40))
        }
    }

    func testFixedFrameFillsAndClipsFlexibleZStackBackground() async {
        await MainActor.run {
            let backgroundColor = Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: ZStack(alignment: .leading) {
                    backgroundColor
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [.red, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 56)
                        .offset(x: 12, y: -8)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green)
                        .frame(width: 64, height: 56)
                        .offset(x: 92, y: 9)
                }
                .frame(height: 84)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(12),
                size: IntSize(width: 240, height: 120),
                clearColor: .clear
            )
            let clipNode = snapshot.runtime.root.children[0]
            let zStackNode = clipNode.children[0].children[0].children[0]
            let backgroundNode = zStackNode.children[0]
            XCTAssertEqual(clipNode.resolvedFrame.size, Size(width: 240, height: 84))
            XCTAssertEqual(zStackNode.resolvedFrame, Rect(x: 0, y: 0, width: 240, height: 84))
            XCTAssertEqual(backgroundNode.resolvedFrame, Rect(x: 0, y: 0, width: 240, height: 84))
            XCTAssertEqual(zStackNode.children[1].resolvedFrame.size, Size(width: 80, height: 56))
            XCTAssertEqual(backgroundNode.frame, .zero, "Placement must leave authored geometry unchanged")
            XCTAssertFalse(snapshot.runtime.hasPendingLayout)

            let surface = GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
            func alpha(x: Int, y: Int) -> UInt8 {
                surface.pixels[y * Int(surface.bytesPerRow) + x * 4 + 3]
            }
            XCTAssertEqual(alpha(x: 0, y: 0), 0, "the rounded corner must clip the filling background")
            XCTAssertEqual(alpha(x: 200, y: 3), 255, "the background must fill above its 56-point overlays")
            XCTAssertEqual(alpha(x: 200, y: 80), 255, "the background must fill below its overlays")
            XCTAssertEqual(alpha(x: 200, y: 90), 0, "the stage must not paint outside its 84-point frame")

            let intrinsicStack = renderedNode(
                ZStack {
                    Text("INTRINSIC")
                }
                .frame(width: 240, height: 84)
            )
            XCTAssertLessThan(intrinsicStack.children[0].resolvedFrame.size.height, 84)
        }
    }

    func testFlexibleZStackColumnsKeepIntrinsicSizesAndSettleAfterResizing() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 780, height: 160) }, invalidateHandler: {})
            let row = HStack(spacing: 20) {
                ZStack(alignment: .leading) {
                    Color.red
                    Color.green.frame(width: 144, height: 46)
                }
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                Color.blue.frame(width: 80, height: 84)
                    .frame(maxWidth: .infinity)
            }
            .makeComponent(context: context).makeNode(runtime: runtime)
            runtime.root.addChild(row)
            let intrinsic = row.intrinsicContentSize()
            var stack = row.children[0]
            while stack.children.count == 1 { stack = stack.children[0] }
            let background = stack.children[0]

            for width: Int32 in [640, 780, 640] {
                runtime.setRootSize(IntSize(width: width, height: 160))
                _ = runtime.renderScene()

                XCTAssertFalse(runtime.hasPendingLayout, "ZStack placement must settle in the layout pass")
                XCTAssertEqual(row.intrinsicContentSize(), intrinsic)
                XCTAssertEqual(background.frame, .zero)
                XCTAssertEqual(background.resolvedFrame.size, stack.resolvedFrame.size)
                XCTAssertGreaterThan(background.resolvedFrame.width, 144)
                XCTAssertLessThanOrEqual(row.children[0].resolvedFrame.maxX, row.children[1].resolvedFrame.minX)

                let settledFrame = background.resolvedFrame
                _ = runtime.renderFrame()
                XCTAssertFalse(runtime.hasPendingLayout)
                XCTAssertEqual(background.resolvedFrame, settledFrame)
            }
        }
    }

    func testZStackLayoutUsesRetainedChildrenAcrossRebuilds() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 300, height: 200) }, invalidateHandler: {})
            var width = 100.0
            var height = 80.0
            var label = "X"
            var alignment = Alignment.bottomTrailing
            host.setComponents {
                [
                    ZStack(alignment: alignment) {
                        Color.red
                        Text(label)
                    }
                    .frame(width: width, height: height)
                    .makeComponent(context: context)
                ]
            }
            runtime.setRootSize(IntSize(width: 300, height: 200))
            _ = runtime.renderFrame()
            let stack = runtime.root.children[0].children[0]
            let text = stack.children[1]
            let initialTextWidth = text.resolvedFrame.size.width
            XCTAssertGreaterThan(text.resolvedFrame.minX, 0)
            XCTAssertGreaterThan(text.resolvedFrame.minY, 0)
            XCTAssertEqual(text.resolvedFrame.maxX, width, accuracy: 0.001)
            XCTAssertEqual(text.resolvedFrame.maxY, height, accuracy: 0.001)

            for resize in [false, true] {
                if resize {
                    width = 200
                    height = 120
                    label = "A WIDER LABEL"
                }
                host.reload()
                _ = runtime.renderFrame()

                XCTAssertTrue(runtime.root.children[0].children[0] === stack)
                XCTAssertTrue(stack.children[1] === text)
                XCTAssertEqual(stack.children[0].resolvedFrame.size, Size(width: width, height: height))
                XCTAssertEqual(text.text, label)
                XCTAssertEqual(text.resolvedFrame.maxX, width, accuracy: 0.001)
                XCTAssertEqual(text.resolvedFrame.maxY, height, accuracy: 0.001)
                XCTAssertFalse(runtime.hasPendingLayout)
                if resize {
                    XCTAssertGreaterThan(text.resolvedFrame.size.width, initialTextWidth)
                }
            }

            alignment = .topLeading
            host.reload()
            XCTAssertTrue(runtime.hasPendingLayout, "Changing only alignment must invalidate placement")
            _ = runtime.renderFrame()
            XCTAssertTrue(stack.children[1] === text)
            XCTAssertEqual(text.resolvedFrame.origin, .zero)
            XCTAssertEqual(text.frame, .zero)
            XCTAssertFalse(runtime.hasPendingLayout)

            let alignedFrame = text.resolvedFrame
            _ = runtime.renderFrame()
            XCTAssertEqual(text.resolvedFrame, alignedFrame)
            XCTAssertFalse(runtime.hasPendingLayout)
        }
    }

    func testContainerRelativeFrameAlignsIntrinsicText() async {
        await MainActor.run {
            let node = renderedNode(
                Text("FULL")
                    .containerRelativeFrame([.horizontal, .vertical], alignment: .bottomTrailing),
                size: Size(width: 320, height: 180)
            )
            let textNode = node.children[0]
            let intrinsicSize = textNode.intrinsicContentSize()

            XCTAssertEqual(node.resolvedFrame.size, Size(width: 320, height: 180))
            XCTAssertLessThan(intrinsicSize.width, 320)
            XCTAssertLessThan(intrinsicSize.height, 180)
            XCTAssertEqual(textNode.resolvedFrame.size, intrinsicSize)
            XCTAssertEqual(textNode.resolvedFrame.maxX, 320, accuracy: 0.001)
            XCTAssertEqual(textNode.resolvedFrame.maxY, 180, accuracy: 0.001)
        }
    }
}

@MainActor
private func makeNode<V: View>(_ view: V) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 800, height: 600) },
        invalidateHandler: {}
    )
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func allTexts(in node: ViewNode) -> [String] {
    var texts: [String] = []
    if let text = node.text {
        texts.append(text)
    }
    for child in node.children {
        texts.append(contentsOf: allTexts(in: child))
    }
    return texts
}

@MainActor
private func renderedNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600),
    onInvalidate: @escaping () -> Void = {}
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    _ = runtime.renderFrame()
    return node
}
