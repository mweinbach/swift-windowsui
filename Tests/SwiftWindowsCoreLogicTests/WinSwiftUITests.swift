import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUITests: XCTestCase {
    func testSwiftUIColorConstantsMapToCoreColors() async {
        await MainActor.run {
            XCTAssertEqual(Color.red, Color(red: 1, green: 0, blue: 0, alpha: 1))
            XCTAssertEqual(Color.orange, Color(red: 1, green: 0.5, blue: 0, alpha: 1))
            XCTAssertEqual(Color.yellow, Color(red: 1, green: 1, blue: 0, alpha: 1))
            XCTAssertEqual(Color.green, Color(red: 0, green: 1, blue: 0, alpha: 1))
            XCTAssertEqual(Color.mint, Color(red: 0, green: 0.78, blue: 0.75, alpha: 1))
            XCTAssertEqual(Color.teal, Color(red: 0, green: 0.5, blue: 0.5, alpha: 1))
            XCTAssertEqual(Color.cyan, Color(red: 0, green: 1, blue: 1, alpha: 1))
            XCTAssertEqual(Color.blue, Color(red: 0, green: 0, blue: 1, alpha: 1))
            XCTAssertEqual(Color.indigo, Color(red: 0.29, green: 0, blue: 0.51, alpha: 1))
            XCTAssertEqual(Color.purple, Color(red: 0.5, green: 0, blue: 0.5, alpha: 1))
            XCTAssertEqual(Color.pink, Color(red: 1, green: 0.41, blue: 0.71, alpha: 1))
            XCTAssertEqual(Color.brown, Color(red: 0.6, green: 0.4, blue: 0.2, alpha: 1))
            XCTAssertEqual(Color.gray, Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            XCTAssertEqual(Color.primary, .white)
            XCTAssertEqual(Color.secondary, Color(red: 0.70, green: 0.74, blue: 0.80, alpha: 1))
            XCTAssertEqual(Color.accentColor, ViewBuildContext.defaultTint)
        }
    }

    func testSwiftUIColorInitializersMapToCoreRGBA() async {
        await MainActor.run {
            assertColor(Color(white: 0.25, opacity: 0.75), red: 0.25, green: 0.25, blue: 0.25, alpha: 0.75)
            assertColor(Color(white: 1.5, opacity: -0.25), red: 1, green: 1, blue: 1, alpha: 0)
            assertColor(Color(hue: 0, saturation: 1, brightness: 1), red: 1, green: 0, blue: 0, alpha: 1)
            assertColor(Color(hue: 1.0 / 3.0, saturation: 1, brightness: 1), red: 0, green: 1, blue: 0, alpha: 1)
            assertColor(Color(hue: 0.5, saturation: 0.5, brightness: 0.8, opacity: 0.6), red: 0.4, green: 0.8, blue: 0.8, alpha: 0.6)
            assertColor(Color(hue: -0.25, saturation: 1, brightness: 0.5), red: 0.25, green: 0, blue: 0.5, alpha: 1)
        }
    }

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
            XCTAssertEqual(node.textStyle.nativeFontSize, 22.4)
            XCTAssertEqual(node.textStyle.weight, .bold)
            XCTAssertEqual(node.textStyle.color, Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
            XCTAssertEqual(node.textStyle.alignment, .leading)
            XCTAssertEqual(node.textStyle.maximumNumberOfLines, 1)
        }
    }

    func testTextSupportsVerbatimAndStringProtocolInitializers() async {
        await MainActor.run {
            let source = "PREFIX-VALUE"
            let substring = source.dropFirst(7)

            let verbatimNode = makeNode(Text(verbatim: "RAW VALUE"))
            let substringNode = makeNode(Text(substring))

            XCTAssertEqual(verbatimNode.text, "RAW VALUE")
            XCTAssertEqual(substringNode.text, "VALUE")
        }
    }

    func testLocalizedStringKeyInputsMapToPlainRetainedText() async {
        await MainActor.run {
            let count = 7
            let textKey: LocalizedStringKey = "COUNT \(count)"
            let labelKey = LocalizedStringKey("SETTINGS")
            let sectionKey = LocalizedStringKey("GENERAL")
            let toggleKey = LocalizedStringKey("ENABLED")
            let buttonKey = LocalizedStringKey("SAVE")

            let textNode = makeNode(Text(textKey))
            let labelNode = makeNode(Label(labelKey, systemImage: "gear"))
            let sectionNode = makeNode(Section(sectionKey) { Text("BODY") })
            let toggleNode = makeNode(
                Toggle(
                    toggleKey,
                    isOn: Binding(get: { false }, set: { _ in })
                )
            )
            let buttonNode = makeNode(Button(buttonKey, role: .cancel, action: {}))

            XCTAssertEqual(textNode.text, "COUNT 7")
            XCTAssertEqual(labelNode.children[1].text, "SETTINGS")
            XCTAssertEqual(sectionNode.children[0].text, "GENERAL")
            XCTAssertEqual(firstText(in: toggleNode), "ENABLED")
            XCTAssertEqual(firstText(in: buttonNode), "SAVE")
        }
    }

    func testTextFieldDisplaysPlaceholderAndWritesBindingFromKeyboard() async {
        await MainActor.run {
            var value = ""
            var invalidationCount = 0
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let placeholderNode = makeNode(
                TextField("NAME", text: binding),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertTrue(placeholderNode.isFocusable)
            XCTAssertEqual(placeholderNode.children[0].text, "NAME")

            placeholderNode.onKeyDown?(KeyboardEvent(keyCode: 0x4A))
            placeholderNode.onKeyDown?(KeyboardEvent(keyCode: 0x4F))
            placeholderNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
            placeholderNode.onKeyDown?(KeyboardEvent(keyCode: 0x39))
            placeholderNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))
            placeholderNode.onKeyDown?(KeyboardEvent(keyCode: 0x4B, modifiers: [.shift]))

            XCTAssertEqual(value, "jo K")
            XCTAssertEqual(invalidationCount, 6)

            let valueNode = makeNode(TextField("NAME", text: binding))

            XCTAssertEqual(valueNode.children[0].text, "jo K")
        }
    }

    func testDisabledTextFieldDoesNotAcceptKeyboardInput() async {
        await MainActor.run {
            var value = "LOCKED"
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(
                TextField("NAME", text: binding)
                    .disabled()
            )

            XCTAssertFalse(node.isFocusable)
            XCTAssertNil(node.onKeyDown)

            node.onKeyDown?(KeyboardEvent(keyCode: 0x58))

            XCTAssertEqual(value, "LOCKED")
        }
    }

    func testSecureFieldMasksDisplayedValueAndWritesBindingFromKeyboard() async {
        await MainActor.run {
            var value = "open"
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let maskedNode = makeNode(SecureField("PASSWORD", text: binding))

            XCTAssertTrue(maskedNode.isFocusable)
            XCTAssertEqual(maskedNode.children[0].text, "****")

            maskedNode.onKeyDown?(KeyboardEvent(keyCode: 0x31))
            maskedNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))
            maskedNode.onKeyDown?(KeyboardEvent(keyCode: 0x5A, modifiers: [.shift]))

            XCTAssertEqual(value, "openZ")

            let updatedNode = makeNode(SecureField("PASSWORD", text: binding))

            XCTAssertEqual(updatedNode.children[0].text, "*****")
        }
    }

    func testTextEditorSupportsBasicMultilineBindingInput() async {
        await MainActor.run {
            var value = "hi"
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(TextEditor(text: binding))

            XCTAssertTrue(node.isFocusable)
            XCTAssertEqual(node.preferredSize, Size(width: 260, height: 120))
            XCTAssertEqual(node.children[0].text, "hi")
            XCTAssertNil(node.children[0].textStyle.maximumNumberOfLines)
            XCTAssertEqual(node.children[0].textStyle.lineBreakMode, .wrap)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x41, modifiers: [.shift]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x42))

            XCTAssertEqual(value, "hi\nAb")

            let updatedNode = makeNode(TextEditor(text: binding))

            XCTAssertEqual(updatedNode.children[0].text, "hi\nAb")
        }
    }

    func testRectangleAndRoundedRectangleMapToRetainedShapeNodes() async {
        await MainActor.run {
            let fillColor = Color(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)
            let strokeColor = Color(red: 0.1, green: 0.4, blue: 1.0, alpha: 1)
            let inheritedColor = Color(red: 0.9, green: 0.6, blue: 0.2, alpha: 1)

            let filledRectangle = makeNode(Rectangle().fill(fillColor))
            let strokedRoundedRectangle = makeNode(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor, lineWidth: 2)
            )
            let inheritedRectangle = makeNode(
                VStack {
                    Rectangle()
                        .frame(width: 12, height: 10)
                }
                .foregroundStyle(inheritedColor)
            )

            XCTAssertEqual(filledRectangle.backgroundColor, fillColor)
            XCTAssertEqual(filledRectangle.cornerRadius, 0)
            XCTAssertEqual(strokedRoundedRectangle.backgroundColor, .clear)
            XCTAssertEqual(strokedRoundedRectangle.borderColor, strokeColor)
            XCTAssertEqual(strokedRoundedRectangle.borderWidth, 2)
            XCTAssertEqual(strokedRoundedRectangle.cornerRadius, 8)
            XCTAssertEqual(inheritedRectangle.children[0].children[0].backgroundColor, inheritedColor)
        }
    }

    func testCapsuleMapsToDynamicRoundedRetainedShapeNode() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let fillColor = Color(red: 0.3, green: 0.9, blue: 0.7, alpha: 1)
            let strokeColor = Color(red: 0.9, green: 0.2, blue: 0.4, alpha: 1)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {}
            )
            let root = VStack {
                Capsule()
                    .fill(fillColor)
                    .frame(width: 40, height: 12)
                Capsule(style: .continuous)
                    .stroke(strokeColor, lineWidth: 3)
                    .frame(width: 50, height: 20)
            }
            let node = root.makeComponent(context: context).makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            _ = runtime.renderFrame()

            let filledCapsule = node.children[0].children[0]
            let strokedCapsule = node.children[1].children[0]
            XCTAssertEqual(filledCapsule.backgroundColor, fillColor)
            XCTAssertEqual(filledCapsule.cornerRadius, 6)
            XCTAssertEqual(strokedCapsule.backgroundColor, .clear)
            XCTAssertEqual(strokedCapsule.borderColor, strokeColor)
            XCTAssertEqual(strokedCapsule.borderWidth, 3)
            XCTAssertEqual(strokedCapsule.cornerRadius, 10)
        }
    }

    func testTextMapsSwiftUIFontPointsToNativeTextSize() async {
        await MainActor.run {
            let node = makeNode(
                Text("HELLO")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            )

            XCTAssertEqual(node.textStyle.scale, 1.8)
            XCTAssertEqual(node.textStyle.nativeFontSize, 18)
            XCTAssertEqual(node.textStyle.weight, .semibold)
            XCTAssertEqual(node.textStyle.fontFamily, "Segoe UI")
        }
    }

    func testNamedFontStylesMapToRetainedTextSizes() async {
        await MainActor.run {
            let titleNode = makeNode(Text("TITLE").font(.title))
            let title2Node = makeNode(Text("TITLE2").font(.title2))
            let headlineNode = makeNode(Text("HEADLINE").font(.headline))
            let captionNode = makeNode(Text("CAPTION").font(.caption))
            let caption2Node = makeNode(Text("CAPTION2").font(.caption2))

            XCTAssertEqual(titleNode.textStyle.nativeFontSize, 28)
            XCTAssertEqual(titleNode.textStyle.scale, 2.8)
            XCTAssertEqual(title2Node.textStyle.nativeFontSize, 22)
            XCTAssertEqual(headlineNode.textStyle.nativeFontSize, 17)
            XCTAssertEqual(headlineNode.textStyle.weight, .semibold)
            XCTAssertEqual(captionNode.textStyle.nativeFontSize, 12)
            XCTAssertEqual(caption2Node.textStyle.nativeFontSize, 11)
        }
    }

    func testSystemFontTextStyleOverloadMapsToRetainedTextStyle() async {
        await MainActor.run {
            let titleNode = makeNode(
                Text("TITLE")
                    .font(.system(.title, design: .monospaced, weight: .bold))
            )
            let headlineNode = makeNode(
                Text("HEADLINE")
                    .font(.system(.headline))
            )

            XCTAssertEqual(titleNode.textStyle.nativeFontSize, 28)
            XCTAssertEqual(titleNode.textStyle.weight, .bold)
            XCTAssertEqual(titleNode.textStyle.fontFamily, "Cascadia Mono")
            XCTAssertEqual(headlineNode.textStyle.nativeFontSize, 17)
            XCTAssertEqual(headlineNode.textStyle.weight, .semibold)
        }
    }

    func testFontWeightAndBoldMapToTextWeight() async {
        await MainActor.run {
            let boldNode = makeNode(Text("LOUD").bold())
            let inheritedNode = makeNode(
                VStack {
                    Text("ONE")
                    Text("TWO")
                }
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .fontWeight(.semibold)
            )
            let heavyNode = makeNode(Text("HEAVY").fontWeight(.heavy))

            XCTAssertEqual(boldNode.textStyle.weight, .bold)
            XCTAssertEqual(heavyNode.textStyle.weight, .bold)
            for child in inheritedNode.children {
                XCTAssertEqual(child.textStyle.weight, .semibold)
                XCTAssertEqual(child.textStyle.nativeFontSize, 14)
                XCTAssertEqual(child.textStyle.fontFamily, "Cascadia Mono")
            }
        }
    }

    func testContainerTextStyleModifiersPropagateToText() async {
        await MainActor.run {
            let node = makeNode(
                VStack {
                    Text("ONE")
                    Text("TWO")
                }
                .foregroundColor(Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
            )

            XCTAssertEqual(node.children.count, 2)
            for child in node.children {
                XCTAssertEqual(child.textStyle.color, Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
                XCTAssertEqual(child.textStyle.scale, 1.6)
                XCTAssertEqual(child.textStyle.nativeFontSize, 16)
                XCTAssertEqual(child.textStyle.weight, .bold)
                XCTAssertEqual(child.textStyle.fontFamily, "Cascadia Mono")
                XCTAssertEqual(child.textStyle.alignment, .trailing)
                XCTAssertEqual(child.textStyle.maximumNumberOfLines, 1)
            }
        }
    }

    func testForegroundStyleColorPropagatesToText() async {
        await MainActor.run {
            let styledColor = Color(red: 0.1, green: 0.7, blue: 0.4, alpha: 1)
            let node = makeNode(
                VStack {
                    Text("ONE")
                    Text("TWO")
                }
                .foregroundStyle(styledColor)
            )

            XCTAssertEqual(node.children.count, 2)
            for child in node.children {
                XCTAssertEqual(child.textStyle.color, styledColor)
            }
        }
    }

    func testInheritedForegroundColorPropagatesToImageAndLabel() async {
        await MainActor.run {
            let inheritedColor = Color(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)
            let imageNode = makeNode(
                VStack {
                    Image(systemName: "gear")
                }
                .foregroundColor(inheritedColor)
            )
            let labelNode = makeNode(
                Label("SETTINGS", systemImage: "gear")
                    .foregroundStyle(inheritedColor)
            )

            XCTAssertEqual(imageNode.children[0].textStyle.color, inheritedColor)
            XCTAssertEqual(labelNode.children.count, 2)
            XCTAssertEqual(labelNode.children[0].textStyle.color, inheritedColor)
            XCTAssertEqual(labelNode.children[1].textStyle.color, inheritedColor)
        }
    }

    func testImageScalingCompatibilityModifiersPassThroughIconRendering() async {
        await MainActor.run {
            let color = Color(red: 0.4, green: 0.7, blue: 1.0, alpha: 1)
            let node = makeNode(
                Image(systemName: "gear")
                    .resizable(resizingMode: .stretch)
                    .scaledToFit()
                    .aspectRatio(1, contentMode: .fill)
                    .foregroundColor(color)
            )

            XCTAssertEqual(node.textStyle.color, color)
        }
    }

    func testFrameConstraintOverloadMapsToRetainedLayoutConstraints() async {
        await MainActor.run {
            let constrainedNode = makeNode(
                Text("FRAME")
                    .frame(
                        minWidth: 80,
                        idealWidth: 100,
                        maxWidth: 120,
                        minHeight: 20,
                        idealHeight: 24,
                        maxHeight: 30,
                        alignment: .bottomTrailing
                    )
            )
            let flexibleNode = makeNode(
                Text("FLEX")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )

            XCTAssertEqual(constrainedNode.preferredSize, Size(width: 100, height: 24))
            XCTAssertEqual(
                constrainedNode.layoutConstraints,
                LayoutConstraints(minWidth: 80, maxWidth: 120, minHeight: 20, maxHeight: 30)
            )
            XCTAssertEqual(flexibleNode.layoutConstraints?.maxWidth, .infinity)
            XCTAssertEqual(flexibleNode.layoutConstraints?.maxHeight, .infinity)
        }
    }

    func testFrameConstraintOverloadClampsIntrinsicSize() async {
        await MainActor.run {
            let minNode = makeNode(
                Rectangle()
                    .frame(minWidth: 80, minHeight: 20)
            )
            let maxNode = makeNode(
                Rectangle()
                    .frame(width: 100, height: 50)
                    .frame(maxWidth: 30, maxHeight: 20)
            )

            XCTAssertEqual(minNode.intrinsicContentSize(), Size(width: 80, height: 20))
            XCTAssertEqual(maxNode.intrinsicContentSize(), Size(width: 30, height: 20))
        }
    }

    func testPaddingAcceptsSwiftUIOptionalLengthOverloads() async {
        await MainActor.run {
            let allPaddingNode = makeNode(Text("ALL").padding(nil))
            let horizontalPaddingNode = makeNode(Text("HORIZONTAL").padding(.horizontal, nil))

            guard case .stack(let allPaddingLayout) = allPaddingNode.layoutMode else {
                return XCTFail("Expected padding to wrap content in a stack layout")
            }
            guard case .stack(let horizontalPaddingLayout) = horizontalPaddingNode.layoutMode else {
                return XCTFail("Expected edge padding to wrap content in a stack layout")
            }

            XCTAssertEqual(allPaddingLayout, .vertical(padding: .all(16), alignment: .stretch))
            XCTAssertEqual(
                horizontalPaddingLayout,
                .vertical(
                    padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16),
                    alignment: .stretch
                )
            )
        }
    }

    func testFixedSizeMapsToRetainedMeasurementAxes() async {
        await MainActor.run {
            let defaultFixedNode = makeNode(Text("BOTH").fixedSize())
            let horizontalFixedNode = makeNode(Text("WIDE TEXT").fixedSize(horizontal: true, vertical: false))

            XCTAssertEqual(defaultFixedNode.fixedSizeAxes, FixedSizeAxes(horizontal: true, vertical: true))
            XCTAssertEqual(horizontalFixedNode.fixedSizeAxes, FixedSizeAxes(horizontal: true, vertical: false))
        }
    }

    func testFixedSizeHorizontalUsesUnconstrainedMeasurementWidth() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 24, height: 120) },
                invalidateHandler: {}
            )
            let node = Text("WIDE TEXT VALUE")
                .fixedSize(horizontal: true, vertical: false)
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 24, height: 120))
            _ = runtime.renderFrame()

            XCTAssertGreaterThan(node.resolvedFrame.size.width, 24)
        }
    }

    func testSafeAreaCompatibilityModifiersPassThroughView() async {
        await MainActor.run {
            let ignoredNode = makeNode(
                Text("SAFE")
                    .ignoresSafeArea(.container, edges: .top)
            )
            let legacyNode = makeNode(
                Text("LEGACY")
                    .edgesIgnoringSafeArea(.all)
            )

            XCTAssertEqual(ignoredNode.text, "SAFE")
            XCTAssertEqual(legacyNode.text, "LEGACY")
        }
    }

    func testOverlayAlignsContentWithoutExpandingBaseLayout() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {}
            )
            let node = Text("BASE")
                .frame(width: 100, height: 40)
                .overlay(alignment: .bottomTrailing) {
                    Text("BADGE")
                        .frame(width: 24, height: 12)
                }
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            _ = runtime.renderFrame()

            XCTAssertEqual(node.preferredSize, Size(width: 100, height: 40))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].frame, Rect(x: 0, y: 0, width: 100, height: 40))
            XCTAssertEqual(node.children[1].frame, Rect(x: 76, y: 28, width: 24, height: 12))
        }
    }

    func testOverlayViewOverloadUsesExistingAlignmentLayout() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {}
            )
            let node = Text("BASE")
                .frame(width: 90, height: 30)
                .overlay(
                    Text("BADGE").frame(width: 18, height: 10),
                    alignment: .topTrailing
                )
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            _ = runtime.renderFrame()

            XCTAssertEqual(node.preferredSize, Size(width: 90, height: 30))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].frame, Rect(x: 0, y: 0, width: 90, height: 30))
            XCTAssertEqual(node.children[1].frame, Rect(x: 72, y: 0, width: 18, height: 10))
        }
    }

    func testBackgroundContentAlignsBehindBaseWithoutExpandingLayout() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {}
            )
            let node = Text("BASE")
                .frame(width: 80, height: 32)
                .background(alignment: .topLeading) {
                    Text("BG")
                        .frame(width: 20, height: 10)
                }
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            _ = runtime.renderFrame()

            XCTAssertEqual(node.preferredSize, Size(width: 80, height: 32))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].frame, Rect(x: 0, y: 0, width: 20, height: 10))
            XCTAssertEqual(node.children[1].frame, Rect(x: 0, y: 0, width: 80, height: 32))
        }
    }

    func testBackgroundViewOverloadUsesExistingAlignmentLayout() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {}
            )
            let node = Text("BASE")
                .frame(width: 80, height: 32)
                .background(
                    Text("BG").frame(width: 16, height: 8),
                    alignment: .bottomTrailing
                )
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            _ = runtime.renderFrame()

            XCTAssertEqual(node.preferredSize, Size(width: 80, height: 32))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].frame, Rect(x: 64, y: 24, width: 16, height: 8))
            XCTAssertEqual(node.children[1].frame, Rect(x: 0, y: 0, width: 80, height: 32))
        }
    }

    func testExplicitTextStyleOverridesInheritedStyle() async {
        await MainActor.run {
            let node = makeNode(
                VStack {
                    Text("ONE")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                }
                .foregroundColor(Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
            )

            let child = node.children[0]
            XCTAssertEqual(child.textStyle.color, .white)
            XCTAssertEqual(child.textStyle.scale, 1.8)
            XCTAssertEqual(child.textStyle.nativeFontSize, 18)
            XCTAssertEqual(child.textStyle.weight, .semibold)
            XCTAssertEqual(child.textStyle.fontFamily, "Segoe UI")
            XCTAssertEqual(child.textStyle.alignment, .leading)
            XCTAssertNil(child.textStyle.maximumNumberOfLines)
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

    func testStacksAcceptNilSpacing() async {
        await MainActor.run {
            let vStackNode = makeNode(
                VStack(alignment: .trailing, spacing: nil) {
                    Text("ONE")
                    Text("TWO")
                }
            )
            let hStackNode = makeNode(
                HStack(alignment: .bottom, spacing: nil) {
                    Text("ONE")
                    Text("TWO")
                }
            )

            guard case .stack(let vStackLayout) = vStackNode.layoutMode else {
                return XCTFail("Expected vertical stack layout")
            }
            guard case .stack(let hStackLayout) = hStackNode.layoutMode else {
                return XCTFail("Expected horizontal stack layout")
            }

            XCTAssertEqual(vStackLayout, .vertical(spacing: 0, alignment: .trailing))
            XCTAssertEqual(hStackLayout, .horizontal(spacing: 0, alignment: .trailing))
        }
    }

    func testDividerAdaptsToStackAxis() async {
        await MainActor.run {
            let verticalStack = makeNode(
                VStack {
                    Text("TOP")
                    Divider()
                    Text("BOTTOM")
                }
            )
            let horizontalDivider = verticalStack.children[1]
            XCTAssertEqual(horizontalDivider.preferredSize, Size(width: 16, height: 1))
            XCTAssertEqual(horizontalDivider.backgroundColor, Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22))
            XCTAssertFalse(horizontalDivider.isHitTestVisible)

            let horizontalStack = makeNode(
                HStack {
                    Text("LEADING")
                    Divider()
                    Text("TRAILING")
                }
            )
            let verticalDivider = horizontalStack.children[1]
            XCTAssertEqual(verticalDivider.preferredSize, Size(width: 1, height: 16))
            XCTAssertEqual(verticalDivider.backgroundColor, Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22))
            XCTAssertFalse(verticalDivider.isHitTestVisible)
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

    func testButtonRoleOverloadsMapToAutomaticSurfaceStyles() async {
        await MainActor.run {
            var didRunAction = false
            let destructiveNode = makeNode(
                Button("DELETE", role: .destructive) {
                    didRunAction = true
                }
            )
            let cancelNode = makeNode(
                Button(role: .cancel, action: {}) {
                    Text("CANCEL")
                }
            )

            XCTAssertEqual(destructiveNode.backgroundColor, ButtonSurfaceStyle.destructive.palette.idle)
            XCTAssertEqual(cancelNode.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            destructiveNode.onActivate?()
            XCTAssertTrue(didRunAction)
        }
    }

    func testButtonSystemImageInitializersBuildLabelContentAndRoleSurface() async {
        await MainActor.run {
            var didRunAction = false
            let node = makeNode(
                Button("EXPORT", systemImage: "doc.text", role: .destructive) {
                    didRunAction = true
                }
            )

            XCTAssertEqual(node.backgroundColor, ButtonSurfaceStyle.destructive.palette.idle)
            XCTAssertTrue(allTexts(in: node).contains(SymbolIcon.document.rawValue))
            XCTAssertTrue(allTexts(in: node).contains("EXPORT"))

            node.onActivate?()
            XCTAssertTrue(didRunAction)
        }
    }

    func testButtonStyleModifierPropagatesThroughViewContextAndCanBeOverridden() async {
        await MainActor.run {
            let customColor = Color(red: 0.2, green: 0.7, blue: 0.4, alpha: 1)
            let customStyle = ButtonSurfaceStyle(
                palette: SurfacePalette(
                    idle: customColor,
                    focused: customColor,
                    pressed: customColor
                )
            )
            let node = makeNode(
                VStack {
                    Button("QUIET") {}
                    Button("LOUD") {}
                        .buttonStyle(.borderedProminent)
                    Button("CUSTOM") {}
                        .buttonSurface(customStyle)
                }
                .buttonStyle(.borderless)
            )

            let inheritedButton = node.children[0]
            let overriddenButton = node.children[1]
            let customButton = node.children[2]

            XCTAssertEqual(inheritedButton.backgroundColor, .clear)
            XCTAssertEqual(inheritedButton.borderColor, .clear)
            XCTAssertEqual(overriddenButton.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            XCTAssertEqual(customButton.backgroundColor, customColor)
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

    func testListMapsToVerticalRetainedScrollPanel() async {
        await MainActor.run {
            let node = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
            )

            guard case .stack(let stackLayout) = node.layoutMode else {
                return XCTFail("Expected List to use retained stack layout inside a scroll panel")
            }

            XCTAssertEqual(node.scrollAxis, .vertical)
            XCTAssertTrue(node.showsScrollIndicator)
            XCTAssertEqual(stackLayout, .vertical(spacing: 0, padding: .zero, alignment: .stretch))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "ONE")
            XCTAssertEqual(node.children[1].text, "TWO")
        }
    }

    func testFormMapsToVerticalRetainedStackPanel() async {
        await MainActor.run {
            let node = makeNode(
                Form {
                    Text("NAME")
                    Toggle("ENABLED", isOn: .constant(true))
                }
            )

            guard case .stack(let stackLayout) = node.layoutMode else {
                return XCTFail("Expected Form to use retained stack layout")
            }

            XCTAssertEqual(stackLayout, .vertical(spacing: 12, padding: .all(12), alignment: .stretch))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "NAME")
            XCTAssertEqual(firstText(in: node.children[1]), "ENABLED")
        }
    }

    func testGroupBoxMapsToRetainedPanelWithTitleAndContent() async {
        await MainActor.run {
            let node = makeNode(
                GroupBox("SETTINGS") {
                    Text("BODY")
                }
            )

            guard case .stack(let stackLayout) = node.layoutMode else {
                return XCTFail("Expected GroupBox to use retained stack layout")
            }

            XCTAssertEqual(stackLayout, .vertical(spacing: 8, padding: .all(12), alignment: .stretch))
            XCTAssertEqual(node.borderWidth, 1)
            XCTAssertEqual(node.cornerRadius, 12)
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "SETTINGS")
            XCTAssertEqual(node.children[1].text, "BODY")
        }
    }

    func testGroupBoxSupportsBuilderLabelSyntax() async {
        await MainActor.run {
            let node = makeNode(
                GroupBox {
                    Text("CONTENT")
                } label: {
                    Label("ADVANCED", systemImage: "gear")
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertTrue(allTexts(in: node.children[0]).contains("ADVANCED"))
            XCTAssertEqual(node.children[1].text, "CONTENT")
        }
    }

    func testDisclosureGroupTogglesBindingAndRevealsContentWhenRebuilt() async {
        await MainActor.run {
            var isExpanded = false
            var didInvalidate = false
            let binding = Binding(
                get: { isExpanded },
                set: { isExpanded = $0 }
            )

            let collapsedNode = makeNode(
                DisclosureGroup("ADVANCED", isExpanded: binding) {
                    Text("DETAIL")
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(collapsedNode.children.count, 1)
            XCTAssertTrue(allTexts(in: collapsedNode.children[0]).contains("ADVANCED"))

            collapsedNode.children[0].onActivate?()

            XCTAssertTrue(isExpanded)
            XCTAssertTrue(didInvalidate)

            let expandedNode = makeNode(
                DisclosureGroup("ADVANCED", isExpanded: binding) {
                    Text("DETAIL")
                }
            )

            XCTAssertEqual(expandedNode.children.count, 2)
            XCTAssertTrue(allTexts(in: expandedNode.children[0]).contains("ADVANCED"))
            XCTAssertEqual(firstText(in: expandedNode.children[1]), "DETAIL")
        }
    }

    func testDisclosureGroupCanManageExpansionWithoutExternalBinding() async {
        await MainActor.run {
            var didInvalidate = false
            let disclosure = DisclosureGroup("DETAILS") {
                Text("NESTED")
            }

            let collapsedNode = makeNode(
                disclosure,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(collapsedNode.children.count, 1)
            XCTAssertTrue(allTexts(in: collapsedNode.children[0]).contains("DETAILS"))

            collapsedNode.children[0].onActivate?()

            XCTAssertTrue(didInvalidate)

            let expandedNode = makeNode(disclosure)

            XCTAssertEqual(expandedNode.children.count, 2)
            XCTAssertTrue(allTexts(in: expandedNode.children[0]).contains("DETAILS"))
            XCTAssertEqual(firstText(in: expandedNode.children[1]), "NESTED")
        }
    }

    func testMenuRevealsInlineContentAndPreservesActions() async {
        await MainActor.run {
            var didInvalidate = false
            var activationCount = 0
            let menu = Menu("ACTIONS") {
                Button("EXPORT") {
                    activationCount += 1
                }
                Button("ARCHIVE") {}
            }

            let collapsedNode = makeNode(
                menu,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(collapsedNode.children.count, 1)
            XCTAssertTrue(allTexts(in: collapsedNode.children[0]).contains("ACTIONS"))

            collapsedNode.children[0].onActivate?()

            XCTAssertTrue(didInvalidate)

            let expandedNode = makeNode(menu)

            XCTAssertEqual(expandedNode.children.count, 2)
            XCTAssertTrue(allTexts(in: expandedNode.children[1]).contains("EXPORT"))
            XCTAssertTrue(allTexts(in: expandedNode.children[1]).contains("ARCHIVE"))

            expandedNode.children[1].children[0].onActivate?()

            XCTAssertEqual(activationCount, 1)
        }
    }

    func testForEachFlattensInsideStackAndAssignsStableIDs() async {
        await MainActor.run {
            let node = makeNode(
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(["ONE", "TWO"], id: \.self) { title in
                        Text(title)
                    }
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "ONE")
            XCTAssertEqual(node.children[1].text, "TWO")
            XCTAssertEqual(node.children[0].nodeTag, "ONE#0")
            XCTAssertEqual(node.children[1].nodeTag, "TWO#0")
        }
    }

    func testForEachSupportsClosedIntegerRanges() async {
        await MainActor.run {
            let node = makeNode(
                VStack {
                    ForEach(1...3) { value in
                        Text("ROW \(value)")
                    }
                }
            )

            XCTAssertEqual(node.children.count, 3)
            XCTAssertEqual(node.children[0].text, "ROW 1")
            XCTAssertEqual(node.children[1].text, "ROW 2")
            XCTAssertEqual(node.children[2].text, "ROW 3")
            XCTAssertEqual(node.children[0].nodeTag, "1#0")
            XCTAssertEqual(node.children[2].nodeTag, "3#0")
        }
    }

    func testToggleWritesBindingAndInvalidates() async {
        await MainActor.run {
            var isEnabled = false
            var didInvalidate = false

            let node = makeNode(
                Toggle(
                    "ENABLED",
                    isOn: Binding(
                        get: { isEnabled },
                        set: { isEnabled = $0 }
                    )
                ),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            guard let toggleNode = firstFocusable(in: node) else {
                return XCTFail("Expected Toggle to create a focusable retained control")
            }

            toggleNode.onActivate?()

            XCTAssertTrue(isEnabled)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testBindingPropertyWrapperFeedsToggle() async {
        await MainActor.run {
            struct BoundToggle: View {
                @Binding var isEnabled: Bool

                var body: some View {
                    Toggle("ENABLED", isOn: $isEnabled)
                }
            }

            var isEnabled = false
            let node = makeNode(
                BoundToggle(
                    isEnabled: Binding(
                        get: { isEnabled },
                        set: { isEnabled = $0 }
                    )
                )
            )

            firstFocusable(in: node)?.onActivate?()

            XCTAssertTrue(isEnabled)
        }
    }

    func testPickerTaggedContentWritesSelectionAndInvalidates() async {
        await MainActor.run {
            var selection = "compact"
            var didInvalidate = false

            let node = makeNode(
                Picker(
                    "MODE",
                    selection: Binding(
                        get: { selection },
                        set: { selection = $0 }
                    )
                ) {
                    Text("COMPACT").tag("compact")
                    Text("EXPANDED")
                        .tag("expanded")
                        .font(.headline)
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(firstText(in: node.children[0]), "MODE")
            XCTAssertTrue(allTexts(in: node.children[1].children[0]).contains("COMPACT"))
            XCTAssertTrue(allTexts(in: node.children[1].children[1]).contains("EXPANDED"))
            XCTAssertTrue(node.children[1].children[0].isFocusable)
            XCTAssertTrue(node.children[1].children[1].isFocusable)

            node.children[1].children[1].onActivate?()

            XCTAssertEqual(selection, "expanded")
            XCTAssertTrue(didInvalidate)
        }
    }

    func testPickerUsesIntegerIndexForUntaggedContent() async {
        await MainActor.run {
            var selection = 0

            let node = makeNode(
                Picker(
                    "TAB",
                    selection: Binding(
                        get: { selection },
                        set: { selection = $0 }
                    )
                ) {
                    Text("ONE")
                    Text("TWO")
                }
            )

            node.children[1].children[1].onActivate?()

            XCTAssertEqual(selection, 1)
        }
    }

    func testPickerDisablesUntaggedNonIntegerOptions() async {
        await MainActor.run {
            var selection = "one"

            let node = makeNode(
                Picker(
                    "VALUE",
                    selection: Binding(
                        get: { selection },
                        set: { selection = $0 }
                    )
                ) {
                    Text("ONE")
                    Text("TWO")
                }
            )

            XCTAssertFalse(node.children[1].children[0].isFocusable)
            XCTAssertFalse(node.children[1].children[1].isFocusable)
            node.children[1].children[1].onActivate?()

            XCTAssertEqual(selection, "one")
        }
    }

    func testPickerStyleMenuUsesDropdownAndWritesTaggedSelection() async {
        await MainActor.run {
            var selection = "compact"
            var didInvalidate = false

            let node = makeNode(
                VStack {
                    Picker(
                        "MODE",
                        selection: Binding(
                            get: { selection },
                            set: { selection = $0 }
                        )
                    ) {
                        Text("COMPACT").tag("compact")
                        Text("EXPANDED").tag("expanded")
                    }
                }
                .pickerStyle(.menu),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            let pickerNode = node.children[0]
            let dropdownNode = pickerNode.children[1]
            XCTAssertEqual(firstText(in: dropdownNode.children[0]), "COMPACT")
            XCTAssertTrue(dropdownNode.children[1].isHidden)

            dropdownNode.onActivate?()
            XCTAssertFalse(dropdownNode.children[1].isHidden)
            dropdownNode.children[1].children[1].onActivate?()

            XCTAssertEqual(selection, "expanded")
            XCTAssertTrue(didInvalidate)
        }
    }

    func testStepperDoubleWritesBindingInvalidatesAndReportsEditingChanges() async {
        await MainActor.run {
            var value = 4.0
            var didInvalidate = false
            var editingChanges: [Bool] = []

            let node = makeNode(
                Stepper(
                    "VALUE",
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    ),
                    in: 0...10,
                    step: 2,
                    onEditingChanged: { isEditing in
                        editingChanges.append(isEditing)
                    }
                ),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(firstText(in: node.children[0]), "VALUE")

            node.children[2].onActivate?()
            XCTAssertEqual(value, 6.0, accuracy: 0.001)
            XCTAssertTrue(didInvalidate)
            XCTAssertEqual(editingChanges, [true, false])

            node.children[1].onActivate?()
            XCTAssertEqual(value, 4.0, accuracy: 0.001)
            XCTAssertEqual(editingChanges, [true, false, true, false])
        }
    }

    func testStepperIntClampsAtBoundsAndDisablesUnavailableActions() async {
        await MainActor.run {
            var value = 1

            let node = makeNode(
                Stepper(
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    ),
                    in: 0...1,
                    step: 1
                ) {
                    Label("COUNT", systemImage: "info.circle")
                }
            )

            XCTAssertTrue(allTexts(in: node.children[0]).contains("COUNT"))
            XCTAssertTrue(node.children[1].isFocusable)
            XCTAssertFalse(node.children[2].isFocusable)

            node.children[2].onActivate?()
            XCTAssertEqual(value, 1)
            node.children[1].onActivate?()
            XCTAssertEqual(value, 0)
        }
    }

    func testSliderWritesBindingFromDragAndInvalidates() async {
        await MainActor.run {
            var value = 0.25
            var didInvalidate = false

            let node = makeNode(
                Slider(
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    ),
                    in: 0...10
                ),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            node.onDragStart?(Point(x: 0, y: 0))
            node.onDragChange?(Point(x: 91, y: 0), Point(x: 91, y: 0))

            XCTAssertEqual(value, 5.25, accuracy: 0.001)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testSliderStepInitializerSnapsValuesAndReportsEditingChanges() async {
        await MainActor.run {
            var value = 0.0
            var editingChanges: [Bool] = []

            let node = makeNode(
                Slider(
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    ),
                    in: 0...10,
                    step: 2,
                    onEditingChanged: { isEditing in
                        editingChanges.append(isEditing)
                    }
                )
            )

            node.onDragStart?(Point(x: 0, y: 0))
            node.onDragChange?(Point(x: 91, y: 0), Point(x: 91, y: 0))
            node.onDragEnd?(Point(x: 91, y: 0), Point(x: 91, y: 0))

            XCTAssertEqual(value, 6.0, accuracy: 0.001)
            XCTAssertEqual(editingChanges, [true, false])
        }
    }

    func testSliderStepInitializerClampsAtRangeBounds() async {
        await MainActor.run {
            var upperValue = 9.0
            var lowerValue = 1.0

            let upperNode = makeNode(
                Slider(
                    value: Binding(
                        get: { upperValue },
                        set: { upperValue = $0 }
                    ),
                    in: 0...10,
                    step: 3
                )
            )
            let lowerNode = makeNode(
                Slider(
                    value: Binding(
                        get: { lowerValue },
                        set: { lowerValue = $0 }
                    ),
                    in: 0...10,
                    step: 3
                )
            )

            upperNode.onDragStart?(Point(x: 0, y: 0))
            upperNode.onDragChange?(Point(x: 182, y: 0), Point(x: 182, y: 0))
            lowerNode.onDragStart?(Point(x: 0, y: 0))
            lowerNode.onDragChange?(Point(x: -182, y: 0), Point(x: -182, y: 0))

            XCTAssertEqual(upperValue, 10.0, accuracy: 0.001)
            XCTAssertEqual(lowerValue, 0.0, accuracy: 0.001)
        }
    }

    func testSliderLabelInitializerComposesLabelsAndKeepsBindingBehavior() async {
        await MainActor.run {
            var value = 0.0
            var editingChanges: [Bool] = []

            let node = makeNode(
                Slider(
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    ),
                    in: 0...10,
                    step: 2,
                    onEditingChanged: { isEditing in
                        editingChanges.append(isEditing)
                    },
                    minimumValueLabel: Text("LOW"),
                    maximumValueLabel: Text("HIGH")
                ) {
                    Label("GAIN", systemImage: "slider.horizontal.3")
                }
            )

            XCTAssertTrue(allTexts(in: node.children[0]).contains("GAIN"))
            XCTAssertEqual(firstText(in: node.children[1].children[0]), "LOW")
            XCTAssertEqual(firstText(in: node.children[1].children[2]), "HIGH")

            let sliderNode = node.children[1].children[1]
            sliderNode.onDragStart?(Point(x: 0, y: 0))
            sliderNode.onDragChange?(Point(x: 91, y: 0), Point(x: 91, y: 0))
            sliderNode.onDragEnd?(Point(x: 91, y: 0), Point(x: 91, y: 0))

            XCTAssertEqual(value, 6.0, accuracy: 0.001)
            XCTAssertEqual(editingChanges, [true, false])
        }
    }

    func testProgressViewMapsToProgressBarNode() async {
        await MainActor.run {
            let node = makeNode(ProgressView(value: 0.25, total: 1.0))

            XCTAssertEqual(node.preferredSize, Size(width: 200, height: 8))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].frame.size.width, 200)
            XCTAssertEqual(node.children[1].frame.size.width, 50)
        }
    }

    func testProgressViewLabelInitializersWrapProgressBarWithLabel() async {
        await MainActor.run {
            let stringNode = makeNode(ProgressView("LOADING", value: 0.25, total: 1.0))
            let builderNode = makeNode(
                ProgressView(value: 0.5, total: 1.0) {
                    Label("SYNC", systemImage: "arrow.triangle.2.circlepath")
                }
            )

            XCTAssertEqual(stringNode.children.count, 2)
            XCTAssertEqual(stringNode.children[0].text, "LOADING")
            XCTAssertEqual(stringNode.children[1].children.count, 2)
            XCTAssertEqual(stringNode.children[1].children[1].frame.size.width, 50)

            XCTAssertEqual(builderNode.children.count, 2)
            XCTAssertTrue(allTexts(in: builderNode.children[0]).contains("SYNC"))
            XCTAssertEqual(builderNode.children[1].children[1].frame.size.width, 100)
        }
    }

    func testProgressViewCurrentValueLabelInitializerComposesHeaderAndProgressBar() async {
        await MainActor.run {
            let node = makeNode(
                ProgressView(value: 0.75, total: 1.0) {
                    Text("DOWNLOAD")
                } currentValueLabel: {
                    Text("75%")
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(firstText(in: node.children[0].children[0]), "DOWNLOAD")
            XCTAssertEqual(firstText(in: node.children[0].children[1]), "75%")
            XCTAssertEqual(node.children[1].children[1].frame.size.width, 150)
        }
    }

    func testTintModifierPropagatesToControls() async {
        await MainActor.run {
            var isOn = true
            var value = 0.35
            let tint = Color(red: 0.9, green: 0.2, blue: 0.5, alpha: 1)

            let node = makeNode(
                VStack {
                    Toggle(
                        "ENABLED",
                        isOn: Binding(
                            get: { isOn },
                            set: { isOn = $0 }
                        )
                    )
                    Slider(
                        value: Binding(
                            get: { value },
                            set: { value = $0 }
                        )
                    )
                    ProgressView(value: 0.5, total: 1.0)
                }
                .tint(tint)
            )

            let toggleTrack = node.children[0].children[1].children[0]
            let sliderFilled = node.children[1].children[1]
            let progressFilled = node.children[2].children[1]

            XCTAssertEqual(toggleTrack.backgroundColor, tint)
            XCTAssertEqual(sliderFilled.backgroundColor, tint)
            XCTAssertEqual(progressFilled.backgroundColor, tint)
        }
    }

    func testNestedTintOverridesParentAccentColor() async {
        await MainActor.run {
            var value = 0.25
            let parentAccent = Color(red: 0.1, green: 0.8, blue: 0.3, alpha: 1)
            let nestedTint = Color(red: 0.8, green: 0.4, blue: 0.1, alpha: 1)

            let node = makeNode(
                VStack {
                    ProgressView(value: 0.25, total: 1.0)
                    Slider(
                        value: Binding(
                            get: { value },
                            set: { value = $0 }
                        )
                    )
                    .tint(nestedTint)
                }
                .accentColor(parentAccent)
            )

            let progressFilled = node.children[0].children[1]
            let sliderFilled = node.children[1].children[1]

            XCTAssertEqual(progressFilled.backgroundColor, parentAccent)
            XCTAssertEqual(sliderFilled.backgroundColor, nestedTint)
        }
    }

    func testOpacityModifierClampsAndMapsToNodeOpacity() async {
        await MainActor.run {
            let fadedNode = makeNode(Text("FADED").opacity(0.42))
            let overbrightNode = makeNode(Text("BRIGHT").opacity(2.0))
            let invisibleNode = makeNode(Text("GONE").opacity(-1.0))

            XCTAssertEqual(fadedNode.opacity, 0.42)
            XCTAssertEqual(overbrightNode.opacity, 1.0)
            XCTAssertEqual(invisibleNode.opacity, 0.0)
        }
    }

    func testHiddenModifierMapsToRetainedNodeVisibility() async {
        await MainActor.run {
            let hiddenNode = makeNode(Text("SECRET").hidden())
            let visibleNode = makeNode(Text("VISIBLE").hidden(false))

            XCTAssertTrue(hiddenNode.isHidden)
            XCTAssertFalse(visibleNode.isHidden)
        }
    }

    func testClippedModifierMapsToRetainedBoundsClip() async {
        await MainActor.run {
            let node = makeNode(Text("CLIP").clipped(antialiased: true))

            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.children.count, 1)
            XCTAssertEqual(node.children[0].text, "CLIP")
        }
    }

    func testClipShapeMapsKnownShapesToRetainedBoundsClip() async {
        await MainActor.run {
            let rectangleNode = makeNode(Text("RECT").clipShape(Rectangle()))
            let roundedNode = makeNode(
                Text("ROUND").clipShape(
                    RoundedRectangle(cornerRadius: 6),
                    style: FillStyle(eoFill: true, antialiased: false)
                )
            )

            XCTAssertTrue(rectangleNode.clipsToBounds)
            XCTAssertEqual(rectangleNode.cornerRadius, 0)
            XCTAssertEqual(rectangleNode.children[0].text, "RECT")
            XCTAssertTrue(roundedNode.clipsToBounds)
            XCTAssertEqual(roundedNode.cornerRadius, 6)
            XCTAssertEqual(roundedNode.children[0].text, "ROUND")
        }
    }

    func testClipShapeFallsBackToRectangularClipForCustomShape() async {
        struct CustomClipShape: Shape {}

        await MainActor.run {
            let node = makeNode(Text("CUSTOM").clipShape(CustomClipShape()))

            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.cornerRadius, 0)
            XCTAssertEqual(node.children[0].text, "CUSTOM")
        }
    }

    func testClipShapeCapsuleUsesDynamicRetainedCornerRadius() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {}
            )
            let node = Text("PILL")
                .frame(width: 60, height: 20)
                .clipShape(Capsule())
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            _ = runtime.renderFrame()

            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.cornerRadius, 10)
            XCTAssertEqual(node.children[0].preferredSize, Size(width: 60, height: 20))
        }
    }

    func testCornerRadiusAcceptsAntialiasedArgumentAndClipsBounds() async {
        await MainActor.run {
            let node = makeNode(Text("ROUND").cornerRadius(5, antialiased: false))

            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.cornerRadius, 5)
            XCTAssertEqual(node.children.count, 1)
            XCTAssertEqual(node.children[0].text, "ROUND")
        }
    }

    func testZIndexModifierMapsToRetainedNodeZIndex() async {
        await MainActor.run {
            let node = makeNode(Text("FRONT").zIndex(7.5))

            XCTAssertEqual(node.zIndex, 7.5)
        }
    }

    func testOffsetAndScaleEffectMapToRetainedTransform() async {
        await MainActor.run {
            let offsetNode = makeNode(Text("MOVED").offset(x: 12, y: 18))
            let sizedOffsetNode = makeNode(Text("MOVED").offset(CGSize(width: 3, height: 4)))
            let scaledNode = makeNode(Text("BIG").scaleEffect(1.5))

            XCTAssertEqual(offsetNode.transform, Transform2D.translation(x: 12, y: 18))
            XCTAssertEqual(sizedOffsetNode.transform, Transform2D.translation(x: 3, y: 4))
            XCTAssertEqual(scaledNode.transform, Transform2D.scale(x: 1.5, y: 1.5))
        }
    }

    func testAngleAndRotationEffectMapToRetainedTransform() async {
        await MainActor.run {
            let angle = Angle.degrees(90)
            let node = makeNode(Text("TURN").rotationEffect(angle))

            XCTAssertEqual(angle.degrees, 90, accuracy: 0.001)
            XCTAssertEqual(angle.radians, .pi / 2, accuracy: 0.001)
            XCTAssertEqual(node.transform, Transform2D(rotation: .pi / 2))
        }
    }

    func testBlurModifierMapsToRetainedNodeBlurRadius() async {
        await MainActor.run {
            let blurredNode = makeNode(Text("SOFT").blur(radius: 12))
            let clampedNode = makeNode(Text("SHARP").blur(radius: -3))

            XCTAssertEqual(blurredNode.blurRadius, 12)
            XCTAssertEqual(clampedNode.blurRadius, 0)
        }
    }

    func testSwiftUIAnimationValueOverloadMapsToRetainedAnimationState() async {
        await MainActor.run {
            let animatedNode = makeNode(
                Text("MOVE")
                    .animation(.linear(duration: 0.4), value: true)
            )
            let disabledNode = makeNode(
                Text("STILL")
                    .animation(nil, value: false)
            )

            XCTAssertEqual(animatedNode.animationStates[.opacity]?.duration, 0.4)
            if case .linear? = animatedNode.animationStates[.opacity]?.easing {
            } else {
                XCTFail("Expected linear easing")
            }
            XCTAssertTrue(disabledNode.animationStates.isEmpty)
        }
    }

    func testDisabledButtonDoesNotActivate() async {
        await MainActor.run {
            var didRunAction = false

            let node = makeNode(
                Button("GO") {
                    didRunAction = true
                }
                .disabled()
            )

            XCTAssertFalse(node.isFocusable)
            XCTAssertFalse(node.isHitTestVisible)
            node.onActivate?()
            XCTAssertFalse(didRunAction)
        }
    }

    func testDisabledEnvironmentReachesNestedControls() async {
        await MainActor.run {
            var didRunAction = false

            let node = makeNode(
                VStack {
                    Button("GO") {
                        didRunAction = true
                    }
                }
                .disabled(true)
            )

            XCTAssertNil(firstFocusable(in: node))
            XCTAssertFalse(didRunAction)
        }
    }

    func testEnvironmentReadsInheritedEnabledStateAndDefaultColorScheme() async {
        await MainActor.run {
            struct EnvironmentReaderView: View {
                @Environment(\.isEnabled) var isEnabled
                @Environment(\.colorScheme) var colorScheme

                var body: some View {
                    Text("\(isEnabled ? "ENABLED" : "DISABLED") \(colorScheme == .dark ? "DARK" : "LIGHT")")
                }
            }

            let enabledNode = makeNode(EnvironmentReaderView())
            let disabledNode = makeNode(EnvironmentReaderView().disabled())
            let lightNode = makeNode(EnvironmentReaderView().environment(\.colorScheme, .light))
            let preferredLightNode = makeNode(EnvironmentReaderView().preferredColorScheme(.light))
            let inheritedNode = makeNode(
                EnvironmentReaderView()
                    .environment(\.colorScheme, .light)
                    .preferredColorScheme(nil)
            )

            XCTAssertEqual(enabledNode.text, "ENABLED DARK")
            XCTAssertEqual(disabledNode.text, "DISABLED DARK")
            XCTAssertEqual(lightNode.text, "ENABLED LIGHT")
            XCTAssertEqual(preferredLightNode.text, "ENABLED LIGHT")
            XCTAssertEqual(inheritedNode.text, "ENABLED LIGHT")
        }
    }

    func testDisabledToggleAndSliderDoNotMutateBindings() async {
        await MainActor.run {
            var isEnabled = false
            var value = 0.25

            let toggleNode = makeNode(
                Toggle(
                    "ENABLED",
                    isOn: Binding(
                        get: { isEnabled },
                        set: { isEnabled = $0 }
                    )
                )
                .disabled()
            )
            XCTAssertNil(firstFocusable(in: toggleNode))
            XCTAssertFalse(isEnabled)

            let sliderNode = makeNode(
                Slider(
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    )
                )
                .disabled()
            )

            XCTAssertFalse(sliderNode.isFocusable)
            XCTAssertNil(sliderNode.onDragStart)
            XCTAssertNil(sliderNode.onDragChange)
            XCTAssertEqual(value, 0.25)
        }
    }

    func testOnAppearModifierRunsOnceWhenRendered() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var appearCount = 0

            let node = Text("HELLO")
                .onAppear {
                    appearCount += 1
                }
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()
            _ = runtime.renderFrame()

            XCTAssertEqual(appearCount, 1)
        }
    }

    func testOnDisappearModifierRunsWhenRenderedSubtreeIsRemoved() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var isVisible = true
            var disappearCount = 0

            host.setComponents {
                guard isVisible else {
                    return []
                }

                return [
                    VStack {
                        Text("CHILD")
                            .onDisappear {
                                disappearCount += 1
                            }
                    }
                    .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()

            isVisible = false
            host.reload()

            XCTAssertEqual(disappearCount, 1)
        }
    }

    func testOnChangeModifierObservesEquatableValueChangesAcrossBuilds() async {
        await MainActor.run {
            var changes: [(Int, Int)] = []

            @MainActor
            func observedView(_ value: Int) -> some View {
                Text("VALUE")
                    .onChange(of: value) { oldValue, newValue in
                        changes.append((oldValue, newValue))
                    }
            }

            _ = makeNode(observedView(1))
            _ = makeNode(observedView(1))
            _ = makeNode(observedView(3))
            _ = makeNode(observedView(5))

            XCTAssertEqual(changes.map(\.0), [1, 3])
            XCTAssertEqual(changes.map(\.1), [3, 5])
        }
    }

    func testOnChangeModifierSupportsInitialAndPerformOverload() async {
        await MainActor.run {
            var values: [String] = []

            @MainActor
            func observedView(_ value: String) -> some View {
                Text("VALUE")
                    .onChange(of: value, initial: true) { newValue in
                        values.append(newValue)
                    }
            }

            _ = makeNode(observedView("alpha"))
            _ = makeNode(observedView("alpha"))
            _ = makeNode(observedView("beta"))

            XCTAssertEqual(values, ["alpha", "beta"])
        }
    }

    func testOnTapGestureEnablesHitTestingAndRunsActionOnPointerTap() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var tapCount = 0

            let node = Text("TAP")
                .frame(width: 80, height: 24)
                .onTapGesture {
                    tapCount += 1
                }
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()

            XCTAssertTrue(node.isHitTestVisible)

            runtime.pointerDown(at: Point(x: 10, y: 10))
            runtime.pointerUp(at: Point(x: 10, y: 10))

            XCTAssertEqual(tapCount, 1)
        }
    }

    func testOnTapGesturePreservesExistingPointerUpHandler() async {
        await MainActor.run {
            var buttonActionCount = 0
            var tapCount = 0

            let node = makeNode(
                Button("GO") {
                    buttonActionCount += 1
                }
                .onTapGesture {
                    tapCount += 1
                }
            )

            node.onPointerDown?()
            node.onPointerUpInside?()
            node.onActivate?()

            XCTAssertEqual(tapCount, 1)
            XCTAssertEqual(buttonActionCount, 1)
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

    func testGeometryReaderRebuildsAfterCanvasSizeChange() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var rootSize = Size(width: 320, height: 180)
            let context = ViewBuildContext(canvasSizeProvider: { rootSize }, invalidateHandler: {})

            host.setComponents {
                [
                    ZStack(alignment: .center) {
                        GeometryReader { proxy in
                            Text("\(Int(proxy.size.width)) X \(Int(proxy.size.height))")
                                .frame(width: 80, height: 24)
                        }
                    }.makeComponent(context: context)
                ]
            }

            XCTAssertEqual(firstText(in: runtime.root), "320 X 180")

            rootSize = Size(width: 640, height: 360)
            host.reload()

            XCTAssertEqual(firstText(in: runtime.root), "640 X 360")
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

    func testStateObjectMutationTriggersInvalidation() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
            }

            struct CounterView: View {
                @StateObject var model: CounterModel

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

private func assertColor(
    _ color: Color,
    red: Float,
    green: Float,
    blue: Float,
    alpha: Float,
    accuracy: Float = 0.0001,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(color.red, red, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(color.green, green, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(color.blue, blue, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(color.alpha, alpha, accuracy: accuracy, file: file, line: line)
}

@MainActor
private func firstText(in node: ViewNode) -> String? {
    if let text = node.text {
        return text
    }

    for child in node.children {
        if let text = firstText(in: child) {
            return text
        }
    }

    return nil
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
private func firstFocusable(in node: ViewNode) -> ViewNode? {
    if node.isFocusable {
        return node
    }

    for child in node.children {
        if let focusable = firstFocusable(in: child) {
            return focusable
        }
    }

    return nil
}
