import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUITests: XCTestCase {
    func testTextMapsToLabelNode() async {
        await MainActor.run {
            let node = makeNode(
                Text("HELLO")
                    .font(.system(size: 2.4, weight: .bold))
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )

            XCTAssertEqual(node.text, "HELLO")
            XCTAssertEqual(node.textStyle.scale, 2.4)
            XCTAssertEqual(node.textStyle.weight, .bold)
            XCTAssertEqual(node.textStyle.color, Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
            XCTAssertEqual(node.textStyle.alignment, .leading)
            XCTAssertEqual(node.textStyle.maximumNumberOfLines, 1)
        }
    }

    func testTextSupportsVerbatimAndStringProtocolInitializers() async {
        await MainActor.run {
            let title = "PREFIX-VALUE".suffix(5)
            let verbatimNode = makeNode(Text(verbatim: "literal.value"))
            let substringNode = makeNode(Text(title))

            XCTAssertEqual(verbatimNode.text, "literal.value")
            XCTAssertEqual(substringNode.text, "VALUE")
        }
    }

    func testNamedFontPresetsMapToRetainedTextStyle() async {
        await MainActor.run {
            let headlineNode = makeNode(Text("HEADLINE").font(.headline))
            let captionNode = makeNode(Text("CAPTION").font(.caption2))

            XCTAssertEqual(headlineNode.textStyle.scale, 1.7, accuracy: 0.001)
            XCTAssertEqual(headlineNode.textStyle.weight, .semibold)
            XCTAssertEqual(captionNode.textStyle.scale, 1.1, accuracy: 0.001)
            XCTAssertEqual(captionNode.textStyle.weight, .regular)
        }
    }

    func testVStackMapsToVerticalStackPanel() async {
        await MainActor.run {
            let node = makeNode(
                VStack(alignment: .leading, spacing: 12) {
                    Text("ONE")
                    Text("TWO")
                }
            )

            guard case .stack(let stackLayout) = node.layoutMode else {
                return XCTFail("Expected stack layout")
            }

            XCTAssertEqual(stackLayout, .vertical(spacing: 12, alignment: .leading))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "ONE")
            XCTAssertEqual(node.children[1].text, "TWO")
        }
    }

    func testDividerUsesStackAxisForRuleDirection() async {
        await MainActor.run {
            let verticalStack = laidOutNode(
                VStack(alignment: .leading, spacing: 2) {
                    Text("ONE").frame(width: 80, height: 20)
                    Divider()
                    Text("TWO").frame(width: 80, height: 20)
                },
                size: Size(width: 160, height: 80)
            )
            let horizontalRule = verticalStack.children[1]

            let horizontalStack = laidOutNode(
                HStack(alignment: .top, spacing: 2) {
                    Text("ONE").frame(width: 40, height: 20)
                    Divider()
                    Text("TWO").frame(width: 40, height: 20)
                },
                size: Size(width: 120, height: 60)
            )
            let verticalRule = horizontalStack.children[1]

            XCTAssertEqual(horizontalRule.resolvedFrame, Rect(x: 0, y: 22, width: 160, height: 1))
            XCTAssertEqual(horizontalRule.backgroundColor?.alpha ?? 0, 0.16, accuracy: 0.001)
            XCTAssertEqual(verticalRule.resolvedFrame, Rect(x: 42, y: 0, width: 1, height: 60))
            XCTAssertEqual(verticalRule.backgroundColor?.alpha ?? 0, 0.16, accuracy: 0.001)
        }
    }

    func testFlexibleFrameMaxWidthFillsVerticalStackCrossAxis() async {
        await MainActor.run {
            let node = laidOutNode(
                VStack(alignment: .leading) {
                    Color.orange
                        .frame(width: 20, height: 10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                },
                size: Size(width: 100, height: 30)
            )
            let frameNode = node.children[0]
            let colorFrame = frameNode.children[0]

            XCTAssertEqual(frameNode.resolvedFrame, Rect(x: 0, y: 0, width: 100, height: 10))
            XCTAssertEqual(colorFrame.resolvedFrame, Rect(x: 80, y: 0, width: 20, height: 10))
        }
    }

    func testFlexibleFrameMaxWidthSharesHorizontalStackSpace() async {
        await MainActor.run {
            let node = laidOutNode(
                HStack(spacing: 0) {
                    Color.orange
                        .frame(width: 20, height: 10)
                        .frame(maxWidth: .infinity)
                    Color.cyan
                        .frame(width: 20, height: 10)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 100, height: 20),
                size: Size(width: 100, height: 20)
            )
            let stackNode = node.children[0]

            XCTAssertEqual(stackNode.children[0].resolvedFrame, Rect(x: 0, y: 5, width: 50, height: 10))
            XCTAssertEqual(stackNode.children[1].resolvedFrame, Rect(x: 50, y: 5, width: 50, height: 10))
        }
    }

    func testFrameMinAndMaxClampRetainedSize() async {
        await MainActor.run {
            let node = laidOutNode(
                Color.orange
                    .frame(width: 120, height: 30)
                    .frame(minWidth: 40, maxWidth: 80, minHeight: 12, maxHeight: 20),
                size: Size(width: 160, height: 60)
            )

            XCTAssertEqual(node.resolvedFrame.size, Size(width: 80, height: 20))
            XCTAssertEqual(node.children[0].resolvedFrame.size, Size(width: 80, height: 20))
        }
    }

    func testGenericForegroundColorStylesTextDescendants() async {
        await MainActor.run {
            let color = Color(red: 0.3, green: 0.8, blue: 0.7, alpha: 1)
            let node = makeNode(
                HStack {
                    Text("STATUS")
                    Image(systemName: "star.fill")
                }
                .foregroundColor(color)
            )

            XCTAssertEqual(node.children[0].textStyle.color, color)
            XCTAssertEqual(node.children[1].textStyle.color, color)
        }
    }

    func testForegroundStyleUsesNamedColor() async {
        await MainActor.run {
            let node = makeNode(
                Text("ACCENT")
                    .foregroundStyle(.accentColor)
            )

            XCTAssertEqual(node.textStyle.color, .accentColor)
            XCTAssertEqual(Color.secondary.opacity(0.5).alpha, 0.5, accuracy: 0.001)
        }
    }

    func testGenericFontStylesTextDescendantsAndPreservesIconFamily() async {
        await MainActor.run {
            let node = makeNode(
                HStack {
                    Text("TITLE")
                    Image(systemName: "star.fill")
                }
                .font(.system(size: 18, weight: .bold, design: .monospaced))
            )

            XCTAssertEqual(node.children[0].textStyle.scale, 1.8)
            XCTAssertEqual(node.children[0].textStyle.weight, .bold)
            XCTAssertEqual(node.children[0].textStyle.fontFamily, "Cascadia Mono")
            XCTAssertEqual(node.children[1].textStyle.scale, 1.8)
            XCTAssertEqual(node.children[1].textStyle.weight, .bold)
            XCTAssertEqual(node.children[1].textStyle.fontFamily, "Segoe Fluent Icons")
        }
    }

    func testGenericTextAlignmentAndLineLimitStyleDescendants() async {
        await MainActor.run {
            let node = makeNode(
                VStack {
                    Text("ALPHA")
                    Text("BETA")
                }
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
            )

            for child in node.children {
                XCTAssertEqual(child.textStyle.alignment, .trailing)
                XCTAssertEqual(child.textStyle.maximumNumberOfLines, 2)
                XCTAssertEqual(child.textStyle.lineBreakMode, .wrap)
            }
        }
    }

    func testInspectionSnapshotSummarizesWinSwiftUIViewTree() async {
        await MainActor.run {
            let snapshot = WinSwiftUIInspection.snapshot(
                of: VStack(alignment: .leading, spacing: 8) {
                    Text("INSPECT")
                    Button("RUN") {}
                    Toggle("POWER", isOn: Binding(get: { true }, set: { _ in }))
                    ProgressView(value: 0.5)
                }
                .foregroundColor(Color(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0))
                .font(.system(size: 16, weight: .semibold)),
                size: Size(width: 320, height: 180)
            )

            XCTAssertGreaterThan(snapshot.nodeCount, 8)
            XCTAssertGreaterThanOrEqual(snapshot.textNodeCount, 3)
            XCTAssertGreaterThanOrEqual(snapshot.focusableNodeCount, 2)
            XCTAssertEqual(snapshot.rootLayoutKind, "stack.vertical")
            XCTAssertTrue(snapshot.textSamples.contains("INSPECT"))
            XCTAssertTrue(snapshot.textSamples.contains("RUN"))
            XCTAssertGreaterThan(snapshot.renderCommands.total, 0)
        }
    }

    func testForEachExpandsRowsAndAssignsStableTags() async {
        await MainActor.run {
            struct Row: Identifiable {
                let id: Int
                let title: String
            }

            let rows = [
                Row(id: 10, title: "ALPHA"),
                Row(id: 20, title: "BETA"),
            ]
            let node = makeNode(
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows) { row in
                        Text(row.title)
                    }
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "ALPHA")
            XCTAssertEqual(node.children[0].nodeTag, "10:0")
            XCTAssertEqual(node.children[1].text, "BETA")
            XCTAssertEqual(node.children[1].nodeTag, "20:0")
        }
    }

    func testForEachSupportsIntegerRanges() async {
        await MainActor.run {
            let node = makeNode(
                VStack {
                    ForEach(0..<3) { index in
                        Text("ROW \(index)")
                    }
                }
            )

            XCTAssertEqual(node.children.count, 3)
            XCTAssertEqual(node.children.map(\.text), ["ROW 0", "ROW 1", "ROW 2"].map(Optional.some))
            XCTAssertEqual(node.children[2].nodeTag, "2:0")

            let closedRangeNode = makeNode(
                VStack {
                    ForEach(1...3) { index in
                        Text("STEP \(index)")
                    }
                }
            )

            XCTAssertEqual(closedRangeNode.children.count, 3)
            XCTAssertEqual(closedRangeNode.children.map(\.text), ["STEP 1", "STEP 2", "STEP 3"].map(Optional.some))
            XCTAssertEqual(closedRangeNode.children[0].nodeTag, "1:0")
            XCTAssertEqual(closedRangeNode.children[2].nodeTag, "3:0")
        }
    }

    func testButtonRunsActionAndInvalidates() async {
        await MainActor.run {
            var didRunAction = false
            var didInvalidate = false

            let node = makeNode(
                Button("GO") {
                    didRunAction = true
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(node.isFocusable)
            node.onActivate?()
            XCTAssertTrue(didRunAction)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testToggleUsesBindingAndInvalidates() async {
        await MainActor.run {
            var isOn = false
            var didInvalidate = false

            let node = makeNode(
                Toggle("POWER", isOn: Binding(get: { isOn }, set: { isOn = $0 })),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(node.children.count, 2)
            let switchNode = node.children[1]
            XCTAssertTrue(switchNode.isFocusable)

            switchNode.onActivate?()

            XCTAssertTrue(isOn)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testButtonDisabledRemovesInteractionAndUsesDisabledChrome() async {
        await MainActor.run {
            var didRunAction = false

            let node = makeNode(
                Button("NOPE") {
                    didRunAction = true
                }
                .disabled(true)
            )

            XCTAssertFalse(node.isFocusable)
            XCTAssertFalse(node.isHitTestVisible)
            XCTAssertEqual(node.backgroundColor, ButtonSurfaceStyle.defaultPalette.disabledBackground)
            XCTAssertEqual(node.borderColor, ButtonSurfaceStyle.defaultPalette.disabledBorder)
            XCTAssertNil(node.onActivate)
            XCTAssertFalse(didRunAction)
        }
    }

    func testSliderUpdatesBindingFromDrag() async {
        await MainActor.run {
            var value = 0.25
            var invalidationCount = 0

            let node = makeNode(
                Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...1),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertTrue(node.isFocusable)
            node.onDragStart?(Point(x: 0, y: 0))
            node.onDragChange?(Point(x: 91, y: 0), Point(x: 91, y: 0))

            XCTAssertEqual(value, 0.75, accuracy: 0.01)
            XCTAssertEqual(invalidationCount, 1)
        }
    }

    func testProgressViewMapsToProgressBar() async {
        await MainActor.run {
            let node = makeNode(ProgressView(value: 0.4, total: 1.0))

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].frame.size.width, 200)
            XCTAssertEqual(node.children[1].frame.size.width, 80)
            XCTAssertFalse(node.isHitTestVisible)
        }
    }

    func testGenericTintStylesControlDescendants() async {
        await MainActor.run {
            let node = makeNode(
                VStack {
                    Toggle("POWER", isOn: Binding(get: { true }, set: { _ in }))
                    Slider(value: Binding(get: { 0.5 }, set: { _ in }), in: 0...1)
                    ProgressView(value: 0.5)
                    ProgressView(value: 0.5)
                        .tint(.purple)
                }
                .tint(.orange)
            )

            let toggleTrack = node.children[0].children[1].children[0]
            let sliderFill = node.children[1].children[1]
            let progressFill = node.children[2].children[1]
            let explicitProgressFill = node.children[3].children[1]

            XCTAssertEqual(toggleTrack.backgroundColor, .orange)
            XCTAssertEqual(sliderFill.backgroundColor, .orange)
            XCTAssertEqual(progressFill.backgroundColor, .orange)
            XCTAssertEqual(explicitProgressFill.backgroundColor, .purple)
        }
    }

    func testVisualEffectModifiersReachRuntimeNode() async {
        await MainActor.run {
            let effectNode = makeNode(
                Text("FX")
                    .opacity(0.4)
                    .blur(radius: 6)
                    .zIndex(5)
            )
            let offsetNode = makeNode(Text("MOVE").offset(x: 7, y: 9))
            let scaleNode = makeNode(Text("ZOOM").scaleEffect(x: 2, y: 0.5))
            let rotationNode = makeNode(Text("TURN").rotationEffect(.degrees(90)))

            XCTAssertEqual(effectNode.opacity, 0.4, accuracy: 0.001)
            XCTAssertEqual(effectNode.blurRadius, 6)
            XCTAssertEqual(effectNode.zIndex, 5)
            XCTAssertEqual(offsetNode.transform.translationX, 7, accuracy: 0.001)
            XCTAssertEqual(offsetNode.transform.translationY, 9, accuracy: 0.001)
            XCTAssertEqual(scaleNode.transform.scaleX, 2, accuracy: 0.001)
            XCTAssertEqual(scaleNode.transform.scaleY, 0.5, accuracy: 0.001)
            XCTAssertEqual(rotationNode.transform.rotation, Double.pi / 2, accuracy: 0.001)
        }
    }

    func testHiddenModifierPreservesLayoutAndSuppressesRendering() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(canvasSizeProvider: { Size(width: 160, height: 80) }, invalidateHandler: {})
            let node = VStack(alignment: .leading, spacing: 4) {
                Text("HIDDEN")
                    .frame(width: 80, height: 20)
                    .hidden()
                Text("VISIBLE")
                    .frame(width: 80, height: 20)
            }
            .makeComponent(context: context)
            .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 160, height: 80))
            let frame = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].resolvedFrame, Rect(x: 0, y: 0, width: 80, height: 20))
            XCTAssertEqual(node.children[1].resolvedFrame, Rect(x: 0, y: 24, width: 80, height: 20))
            XCTAssertEqual(drawBitmapCommands(in: frame).count, 1)
        }
    }

    func testHiddenModifierSuppressesDescendantInteraction() async {
        await MainActor.run {
            var taps = 0
            let node = makeNode(
                VStack {
                    Button("Tap") {
                        taps += 1
                    }
                }
                .hidden()
            )

            XCTAssertFalse(hasInteractiveNode(in: node))
            node.children[0].onActivate?()
            XCTAssertEqual(taps, 0)
        }
    }

    func testClipModifiersMapToRetainedClipping() async {
        await MainActor.run {
            let clippedNode = makeNode(
                Text("CLIP")
                    .frame(width: 60, height: 24)
                    .clipped(antialiased: true)
            )
            let cornerNode = makeNode(Text("CARD").cornerRadius(8, antialiased: false))
            let roundedNode = makeNode(Text("ROUND").clipShape(RoundedRectangle(cornerRadius: 14)))
            let rectNode = makeNode(Text("RECT").clipShape(Rectangle(), style: FillStyle(antialiased: false)))

            XCTAssertTrue(clippedNode.clipsToBounds)
            XCTAssertEqual(clippedNode.cornerRadius, 0)
            XCTAssertEqual(clippedNode.children.count, 1)
            XCTAssertTrue(cornerNode.clipsToBounds)
            XCTAssertEqual(cornerNode.cornerRadius, 8)
            XCTAssertTrue(roundedNode.clipsToBounds)
            XCTAssertEqual(roundedNode.cornerRadius, 14)
            XCTAssertTrue(rectNode.clipsToBounds)
            XCTAssertEqual(rectNode.cornerRadius, 0)
        }
    }

    func testRenderableShapesMapToRetainedPanels() async {
        await MainActor.run {
            let rectangleNode = makeNode(Rectangle().fill(.accentColor))
            let roundedNode = makeNode(RoundedRectangle(cornerRadius: 12).fill(.orange))
            let strokedNode = makeNode(RoundedRectangle(cornerRadius: 10).stroke(.cyan, lineWidth: 2))

            XCTAssertEqual(rectangleNode.backgroundColor, .accentColor)
            XCTAssertEqual(rectangleNode.cornerRadius, 0)
            XCTAssertFalse(rectangleNode.isHitTestVisible)
            XCTAssertEqual(roundedNode.backgroundColor, .orange)
            XCTAssertEqual(roundedNode.cornerRadius, 12)
            XCTAssertTrue(roundedNode.clipsToBounds)
            XCTAssertEqual(strokedNode.borderColor, .cyan)
            XCTAssertEqual(strokedNode.borderWidth, 2)
            XCTAssertEqual(strokedNode.cornerRadius, 10)
            XCTAssertFalse(strokedNode.isHitTestVisible)
        }
    }

    func testRenderableShapesSupportGradientFillsAndDefaultBodies() async {
        await MainActor.run {
            let gradient = LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)
            let gradientNode = makeNode(Rectangle().fill(gradient))
            let defaultRoundedNode = makeNode(RoundedRectangle(cornerRadius: 16))
            let defaultCircleNode = makeNode(Circle())

            XCTAssertEqual(gradientNode.backgroundGradient, gradient)
            XCTAssertEqual(gradientNode.cornerRadius, 0)
            XCTAssertFalse(gradientNode.isHitTestVisible)
            XCTAssertEqual(defaultRoundedNode.backgroundColor, .white)
            XCTAssertEqual(defaultRoundedNode.cornerRadius, 16)
            XCTAssertTrue(defaultRoundedNode.clipsToBounds)
            XCTAssertEqual(defaultCircleNode.backgroundColor, .white)
            XCTAssertEqual(defaultCircleNode.cornerRadius, 1_000_000)
            XCTAssertTrue(defaultCircleNode.clipsToBounds)
        }
    }

    func testCapsuleCircleAndEllipseMapToRoundedRetainedPanels() async {
        await MainActor.run {
            let capsuleNode = makeNode(Capsule().fill(.pink))
            let circleNode = makeNode(Circle().stroke(.orange, lineWidth: 3))
            let ellipseClipNode = makeNode(Text("AVATAR").clipShape(Ellipse()))

            XCTAssertEqual(capsuleNode.backgroundColor, .pink)
            XCTAssertEqual(capsuleNode.cornerRadius, 1_000_000)
            XCTAssertTrue(capsuleNode.clipsToBounds)
            XCTAssertEqual(circleNode.borderColor, .orange)
            XCTAssertEqual(circleNode.borderWidth, 3)
            XCTAssertEqual(circleNode.cornerRadius, 1_000_000)
            XCTAssertTrue(circleNode.clipsToBounds)
            XCTAssertEqual(ellipseClipNode.cornerRadius, 1_000_000)
            XCTAssertTrue(ellipseClipNode.clipsToBounds)
        }
    }

    func testOverlayAndBackgroundUseAlignedLayerWrappers() async {
        await MainActor.run {
            let overlayNode = laidOutNode(
                Text("BASE")
                    .frame(width: 100, height: 50)
                    .overlay(alignment: .bottomTrailing) {
                        Color(red: 1, green: 1, blue: 1, opacity: 0.35)
                            .frame(width: 20, height: 10)
                    }
            )
            let backgroundNode = laidOutNode(
                Text("BASE")
                    .frame(width: 100, height: 50)
                    .background(alignment: .topLeading) {
                        Color(red: 0.1, green: 0.2, blue: 0.3, opacity: 1)
                            .frame(width: 12, height: 8)
                    }
            )

            XCTAssertEqual(overlayNode.children.count, 2)
            XCTAssertEqual(overlayNode.children[0].frame, Rect(x: 0, y: 0, width: 100, height: 50))
            XCTAssertEqual(overlayNode.children[1].frame, Rect(x: 80, y: 40, width: 20, height: 10))
            XCTAssertEqual(backgroundNode.children.count, 2)
            XCTAssertEqual(backgroundNode.children[0].frame, Rect(x: 0, y: 0, width: 12, height: 8))
            XCTAssertEqual(backgroundNode.children[1].frame, Rect(x: 0, y: 0, width: 100, height: 50))
        }
    }

    func testOverlayAndBackgroundViewOverloadsFillZeroSizedLayers() async {
        await MainActor.run {
            let overlayNode = laidOutNode(
                Text("BASE")
                    .frame(width: 100, height: 50)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan, lineWidth: 2))
            )
            let backgroundNode = laidOutNode(
                Text("BASE")
                    .frame(width: 100, height: 50)
                    .background(Rectangle().fill(.orange))
            )

            XCTAssertEqual(overlayNode.children.count, 2)
            XCTAssertEqual(overlayNode.children[1].frame, Rect(x: 0, y: 0, width: 100, height: 50))
            XCTAssertEqual(overlayNode.children[1].borderColor, .cyan)
            XCTAssertEqual(overlayNode.children[1].borderWidth, 2)
            XCTAssertEqual(backgroundNode.children.count, 2)
            XCTAssertEqual(backgroundNode.children[0].frame, Rect(x: 0, y: 0, width: 100, height: 50))
            XCTAssertEqual(backgroundNode.children[0].backgroundColor, .orange)
        }
    }

    func testMaterialBackgroundAndOverlayMapToBlurredRetainedLayers() async {
        await MainActor.run {
            let backgroundNode = laidOutNode(
                Text("BASE")
                    .frame(width: 100, height: 50)
                    .background(.ultraThinMaterial)
            )
            let overlayNode = laidOutNode(
                Text("BASE")
                    .frame(width: 100, height: 50)
                    .overlay(.bar, alignment: .bottom)
            )

            let materialLayer = backgroundNode.children[0]
            let barLayer = overlayNode.children[1]

            XCTAssertEqual(materialLayer.frame, Rect(x: 0, y: 0, width: 100, height: 50))
            XCTAssertEqual(materialLayer.backgroundColor, Material.ultraThinMaterial.backgroundColor)
            XCTAssertEqual(materialLayer.blurRadius, Material.ultraThinMaterial.blurRadius)
            XCTAssertEqual(materialLayer.cornerRadius, Material.ultraThinMaterial.cornerRadius)
            XCTAssertFalse(materialLayer.isHitTestVisible)
            XCTAssertEqual(barLayer.frame, Rect(x: 0, y: 0, width: 100, height: 50))
            XCTAssertEqual(barLayer.backgroundColor, Material.bar.backgroundColor)
            XCTAssertEqual(barLayer.blurRadius, Material.bar.blurRadius)
            XCTAssertEqual(barLayer.borderColor, Material.bar.borderColor)
        }
    }

    func testLifecycleModifiersRouteToRetainedCallbacks() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(canvasSizeProvider: { Size(width: 120, height: 60) }, invalidateHandler: {})
            var didAppear = false
            var didDisappear = false

            let node = Text("LIFE")
                .onAppear {
                    didAppear = true
                }
                .onDisappear {
                    didDisappear = true
                }
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 120, height: 60))
            _ = runtime.renderFrame()
            runtime.root.removeAllChildren()

            XCTAssertTrue(didAppear)
            XCTAssertTrue(didDisappear)
        }
    }

    func testTapGestureMapsToPointerActivation() async {
        await MainActor.run {
            var taps = 0
            var doubleTaps = 0
            let tapNode = makeNode(
                Text("TAP")
                    .onTapGesture {
                        taps += 1
                    }
            )
            let doubleTapNode = makeNode(
                Text("DOUBLE")
                    .onTapGesture(count: 2) {
                        doubleTaps += 1
                    }
            )

            XCTAssertTrue(tapNode.isHitTestVisible)
            tapNode.onPointerUpInside?()
            doubleTapNode.onPointerUpInside?()

            XCTAssertEqual(taps, 1)
            XCTAssertEqual(doubleTaps, 0)
        }
    }

    func testGenericDisabledClearsRetainedInteraction() async {
        await MainActor.run {
            var taps = 0
            let node = makeNode(
                Text("LOCKED")
                    .onTapGesture {
                        taps += 1
                    }
                    .disabled(true)
            )

            XCTAssertFalse(node.isFocusable)
            XCTAssertFalse(node.isHitTestVisible)
            XCTAssertNil(node.onPointerUpInside)
            XCTAssertEqual(taps, 0)
        }
    }

    func testDragGestureMapsToRetainedDragCallbacks() async {
        await MainActor.run {
            var changedTranslations: [Size] = []
            var endedTranslation: Size?
            let gesture = DragGesture(minimumDistance: 5)
                .onChanged { value in
                    changedTranslations.append(value.translation)
                }
                .onEnded { value in
                    endedTranslation = value.translation
                }
            let node = makeNode(Text("DRAG").gesture(gesture))

            XCTAssertTrue(node.isHitTestVisible)
            node.onDragStart?(Point(x: 10, y: 20))
            node.onDragChange?(Point(x: 13, y: 20), Point(x: 3, y: 0))
            XCTAssertTrue(changedTranslations.isEmpty)

            node.onDragChange?(Point(x: 18, y: 24), Point(x: 5, y: 4))
            node.onDragEnd?(Point(x: 20, y: 25), Point(x: 2, y: 1))

            XCTAssertEqual(changedTranslations.count, 1)
            XCTAssertEqual(changedTranslations[0].width, 8, accuracy: 0.001)
            XCTAssertEqual(changedTranslations[0].height, 4, accuracy: 0.001)
            guard let endedTranslation else {
                return XCTFail("Expected drag end translation")
            }
            XCTAssertEqual(endedTranslation.width, 10, accuracy: 0.001)
            XCTAssertEqual(endedTranslation.height, 5, accuracy: 0.001)
        }
    }

    func testTagModifierSetsSelectionTag() async {
        await MainActor.run {
            let node = makeNode(Text("TAGGED").tag(7))

            XCTAssertEqual(node.nodeTag, "7")
            XCTAssertEqual(node.selectionTag?.base as? Int, 7)
            XCTAssertEqual(node.text, "TAGGED")
        }
    }

    func testTagModifierAcceptsHashableSelectionValues() async {
        await MainActor.run {
            let node = makeNode(Text("TAGGED").tag("render"))

            XCTAssertEqual(node.nodeTag, "render")
            XCTAssertEqual(node.selectionTag?.base as? String, "render")
            XCTAssertEqual(node.text, "TAGGED")
        }
    }

    func testIdModifierAcceptsHashableValues() async {
        await MainActor.run {
            let numericNode = makeNode(Text("NUMERIC").id(42))
            let stringNode = makeNode(Text("STRING").id("stable-row"))

            XCTAssertEqual(numericNode.nodeTag, "42")
            XCTAssertEqual(stringNode.nodeTag, "stable-row")
        }
    }

    func testPickerUsesTaggedTextOptionsAndBinding() async {
        await MainActor.run {
            var selection = 1
            var didInvalidate = false

            let node = makeNode(
                Picker("MODE", selection: Binding(get: { selection }, set: { selection = $0 })) {
                    Text("Layout").tag(0)
                    Text("Input").tag(1)
                    Text("Render").tag(2)
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "MODE")

            let dropdown = node.children[1]
            XCTAssertTrue(dropdown.isFocusable)
            XCTAssertEqual(dropdown.children[0].children.first?.text, "Input")

            let optionsList = dropdown.children[1]
            XCTAssertTrue(optionsList.isHidden)
            dropdown.onActivate?()
            XCTAssertFalse(optionsList.isHidden)

            optionsList.children[2].onActivate?()
            XCTAssertEqual(selection, 2)
            XCTAssertTrue(didInvalidate)
            XCTAssertTrue(optionsList.isHidden)
        }
    }

    func testPickerSupportsHashableTaggedOptionsAndBinding() async {
        await MainActor.run {
            var selection = "render"
            var didInvalidate = false

            let node = makeNode(
                Picker("MODE", selection: Binding(get: { selection }, set: { selection = $0 })) {
                    Text("Layout").tag("layout")
                    Text("Input").tag("input")
                    Text("Render").tag("render")
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(node.children.count, 2)

            let dropdown = node.children[1]
            XCTAssertTrue(dropdown.isFocusable)
            XCTAssertEqual(dropdown.children[0].children.first?.text, "Render")

            let optionsList = dropdown.children[1]
            XCTAssertTrue(optionsList.isHidden)
            dropdown.onActivate?()
            XCTAssertFalse(optionsList.isHidden)

            optionsList.children[0].onActivate?()
            XCTAssertEqual(selection, "layout")
            XCTAssertTrue(didInvalidate)
            XCTAssertTrue(optionsList.isHidden)
        }
    }

    func testTextFieldUsesBindingAndKeyboardEditing() async {
        await MainActor.run {
            var text = ""
            var invalidationCount = 0

            let node = makeNode(
                TextField("Search", text: Binding(get: { text }, set: { text = $0 })),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertTrue(node.isFocusable)
            XCTAssertEqual(node.children[0].text, "Search")
            XCTAssertTrue(node.children[1].isHidden)

            node.onFocusEnter?()
            XCTAssertFalse(node.children[1].isHidden)

            node.onTextInput?("Hi")
            XCTAssertEqual(text, "Hi")
            XCTAssertEqual(node.children[0].text, "Hi")

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))
            XCTAssertEqual(text, "H")

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.delete.rawValue))
            XCTAssertEqual(text, "H")
            XCTAssertEqual(node.children[0].text, "H")
            XCTAssertEqual(invalidationCount, 2)
        }
    }

    func testTextFieldEditsAtCaretAndMovesCaret() async {
        await MainActor.run {
            var text = ""
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(canvasSizeProvider: { Size(width: 320, height: 80) }, invalidateHandler: {})
            let node = TextField("Search", text: Binding(get: { text }, set: { text = $0 }))
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 80))

            node.onTextInput?("ABC")
            _ = runtime.renderFrame()
            let endCaretX = node.children[1].frame.origin.x

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
            _ = runtime.renderFrame()
            let movedCaretX = node.children[1].frame.origin.x

            node.onTextInput?("x")
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.delete.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.home.rawValue))
            node.onTextInput?("^")
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.end.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))

            XCTAssertLessThan(movedCaretX, endCaretX)
            XCTAssertEqual(text, "^Ax")
        }
    }

    func testSecureFieldMasksDisplayWhileEditingBinding() async {
        await MainActor.run {
            var password = ""
            var invalidationCount = 0

            let node = makeNode(
                SecureField("Password", text: Binding(get: { password }, set: { password = $0 })),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertTrue(node.isFocusable)
            XCTAssertEqual(node.children[0].text, "Password")

            node.onTextInput?("Pa")
            XCTAssertEqual(password, "Pa")
            XCTAssertEqual(node.children[0].text, "**")

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))
            XCTAssertEqual(password, "P")
            XCTAssertEqual(node.children[0].text, "*")
            XCTAssertEqual(invalidationCount, 2)
        }
    }

    func testTextFieldOnSubmitRunsFromEnterKey() async {
        await MainActor.run {
            var text = ""
            var submissions = 0
            let node = makeNode(
                TextField("Search", text: Binding(get: { text }, set: { text = $0 }))
                    .onSubmit {
                        submissions += 1
                    }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(submissions, 1)
        }
    }

    func testParentOnSubmitRoutesToTextFieldDescendant() async {
        await MainActor.run {
            var text = ""
            var submissions = 0
            let node = makeNode(
                VStack {
                    TextField("Search", text: Binding(get: { text }, set: { text = $0 }))
                }
                .onSubmit {
                    submissions += 1
                }
            )

            let textFieldNode = node.children[0]
            textFieldNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(submissions, 1)
        }
    }

    func testStateBindingPersistsAcrossRebuilds() async {
        await MainActor.run {
            struct SearchView: View {
                @State var query = ""

                var body: some View {
                    TextField("Search", text: $query)
                }
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            var invalidationCount = 0
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 80) },
                invalidateHandler: {
                    invalidationCount += 1
                }
            )
            let view = AnyView(SearchView())

            let firstNode = view.makeComponent(context: context).makeNode(runtime: runtime)
            firstNode.onTextInput?("Go")

            let rebuiltNode = view.makeComponent(context: context).makeNode(runtime: runtime)

            XCTAssertEqual(invalidationCount, 1)
            XCTAssertEqual(rebuiltNode.children[0].text, "Go")
        }
    }

    func testStateObjectProjectedBindingPersistsAcrossRebuilds() async {
        await MainActor.run {
            final class SettingsModel: ObservableObject {
                @Published var enabled = false
            }

            struct SettingsView: View {
                @StateObject var model = SettingsModel()

                var body: some View {
                    Toggle("ENABLED", isOn: $model.enabled)
                        .tint(.orange)
                }
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            var invalidationCount = 0
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 80) },
                invalidateHandler: {
                    invalidationCount += 1
                }
            )
            let view = AnyView(SettingsView())

            let firstNode = view.makeComponent(context: context).makeNode(runtime: runtime)
            firstNode.children[1].onActivate?()

            let rebuiltNode = view.makeComponent(context: context).makeNode(runtime: runtime)
            let rebuiltSwitchTrack = rebuiltNode.children[1].children[0]

            XCTAssertEqual(invalidationCount, 1)
            XCTAssertEqual(rebuiltSwitchTrack.backgroundColor, .orange)
        }
    }

    func testScrollViewConfiguresScrollChrome() async {
        await MainActor.run {
            let node = makeNode(
                ScrollView(.vertical, style: ScrollViewStyle(spacing: 6, scrollStep: 24)) {
                    Text("ONE")
                    Text("TWO")
                    Text("THREE")
                }
            )

            XCTAssertEqual(node.scrollAxis, .vertical)
            XCTAssertEqual(node.scrollStep, 24)
            XCTAssertTrue(node.showsScrollIndicator)
            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.children.count, 3)
        }
    }

    func testListMapsToVerticalScrollPanelAndFlattensForEachRows() async {
        await MainActor.run {
            let rows = ["ONE", "TWO", "THREE"]
            let node = makeNode(
                List {
                    ForEach(rows, id: \.self) { row in
                        Text(row)
                    }
                }
            )

            XCTAssertEqual(node.scrollAxis, .vertical)
            XCTAssertTrue(node.showsScrollIndicator)
            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.children.count, 3)
            XCTAssertEqual(node.children.map(\.text), rows.map(Optional.some))
        }
    }

    func testGeometryReaderAndZStackUseBuildContextSizing() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let rootSize = Size(width: 320, height: 180)
            let context = ViewBuildContext(canvasSizeProvider: { rootSize }, invalidateHandler: {})
            let root = ZStack(alignment: .center) {
                GeometryReader { proxy in
                    Text("\(Int(proxy.size.width)) X \(Int(proxy.size.height))")
                        .frame(width: 80, height: 24)
                }
            }
            let node = root.makeComponent(context: context).makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            let frame = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 1)
            XCTAssertEqual(node.children[0].children.count, 1)
            XCTAssertEqual(node.children[0].children[0].text, "320 X 180")

            let bitmapRect = frame.commands.compactMap { command -> Rect? in
                guard case .drawBitmap(let drawBitmap) = command else {
                    return nil
                }

                return drawBitmap.rect
            }.first

            guard let bitmapRect else {
                return XCTFail("Expected a bitmap text draw command")
            }

            XCTAssertGreaterThan(bitmapRect.size.width, 0)
            XCTAssertGreaterThan(bitmapRect.size.height, 0)
        }
    }

    func testObservedObjectProjectedBindingFeedsToggle() async {
        await MainActor.run {
            final class SettingsModel: ObservableObject {
                @Published var enabled = false
            }

            struct SettingsView: View {
                @ObservedObject var model: SettingsModel

                var body: some View {
                    Toggle("ENABLED", isOn: $model.enabled)
                }
            }

            let model = SettingsModel()
            var didInvalidate = false
            let node = makeNode(
                SettingsView(model: model),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            node.children[1].onActivate?()

            XCTAssertTrue(model.enabled)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testStateObjectMutationTriggersInvalidation() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
            }

            struct CounterView: View {
                @StateObject var model = CounterModel()

                var body: some View {
                    Text("\(model.value)")
                }
            }

            var model: CounterModel?
            var invalidationCount = 0
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {},
                observedObjectHandler: { object in
                    model = object as? CounterModel
                    _ = ObservableObjectCenter.shared.addObserver(for: object) {
                        invalidationCount += 1
                    }
                }
            )

            _ = CounterView().makeComponent(context: context)
            model?.value = 1

            XCTAssertEqual(invalidationCount, 1)
        }
    }

    func testObservedObjectMutationTriggersInvalidation() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
            }

            struct CounterView: View {
                @ObservedObject var model: CounterModel

                var body: some View {
                    Text("\(model.value)")
                }
            }

            let model = CounterModel()
            var invalidationCount = 0
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {},
                observedObjectHandler: { object in
                    _ = ObservableObjectCenter.shared.addObserver(for: object) {
                        invalidationCount += 1
                    }
                }
            )

            _ = CounterView(model: model).makeComponent(context: context)
            model.value = 1

            XCTAssertEqual(invalidationCount, 1)
        }
    }

}

@MainActor
private func makeNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600),
    onInvalidate: @escaping () -> Void = {}
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func laidOutNode<V: View>(
    _ view: V,
    size: Size = Size(width: 160, height: 90)
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    _ = runtime.renderFrame()
    return node
}

private func drawBitmapCommands(in frame: RenderFrame) -> [DrawBitmapCommand] {
    frame.commands.compactMap { command in
        guard case .drawBitmap(let drawBitmap) = command else {
            return nil
        }

        return drawBitmap
    }
}

@MainActor
private func hasInteractiveNode(in node: ViewNode) -> Bool {
    if node.isHitTestVisible || node.isFocusable || node.onActivate != nil || node.onPointerUpInside != nil {
        return true
    }

    return node.children.contains { hasInteractiveNode(in: $0) }
}
