import XCTest
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private struct PointerHandlerProbe: View {
    typealias Body = Never

    var onEnter: (() -> Void)? = nil
    var onExit: (() -> Void)? = nil
    var onUpInside: (() -> Void)? = nil
    var onUpOutside: (() -> Void)? = nil

    var body: Never {
        fatalError("PointerHandlerProbe has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            let node = Controls.panel(preferredSize: Size(width: 80, height: 24))
            node.onPointerEnter = onEnter
            node.onPointerExit = onExit
            node.onPointerUpInside = onUpInside
            node.onPointerUpOutside = onUpOutside
            return node
        }
    }
}

private struct NavigationDestinationItem: Identifiable {
    let id: String
}

private struct TestEnvironmentLabelKey: EnvironmentKey {
    static let defaultValue = "DEFAULT"
}

private extension EnvironmentValues {
    var testEnvironmentLabel: String {
        get { self[TestEnvironmentLabelKey.self] }
        set { self[TestEnvironmentLabelKey.self] = newValue }
    }
}

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

    func testEdgeInsetsDefaultInitializerMapsToZero() async {
        await MainActor.run {
            XCTAssertEqual(EdgeInsets(), .zero)
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

    func testStringProtocolInputsMapToLabelBearingControls() async {
        await MainActor.run {
            let source = "PREFIX-SAVE"
            let title = source.dropFirst(7)

            let node = makeNode(
                VStack {
                    Label(title, systemImage: "gear")
                    NavigationLink(title, destination: Text("DESTINATION"))
                    NavigationLink(title, value: "detail")
                    Menu(title) {
                        Button(title) {}
                    }
                    Toggle(title, isOn: .constant(true))
                    ProgressView(title, value: 0.5, total: 1.0)
                    Button(title) {}
                    Button(title, systemImage: "doc.text") {}
                    Button(title, role: .cancel) {}
                    Button(title, systemImage: "trash", role: .destructive) {}
                }
            )

            XCTAssertGreaterThanOrEqual(allTexts(in: node).filter { $0 == "SAVE" }.count, 10)
        }
    }

    func testStringProtocolInputsMapToTitledContainers() async {
        await MainActor.run {
            let source = "PREFIX-DETAILS"
            let title = source.dropFirst(7)

            let node = makeNode(
                VStack {
                    Section(title) {
                        Text("ROW")
                    }
                    GroupBox(title) {
                        Text("GROUP CONTENT")
                    }
                    DisclosureGroup(title, isExpanded: .constant(true)) {
                        Text("DISCLOSED")
                    }
                }
            )

            XCTAssertGreaterThanOrEqual(allTexts(in: node).filter { $0 == "DETAILS" }.count, 3)
            XCTAssertTrue(allTexts(in: node).contains("ROW"))
            XCTAssertTrue(allTexts(in: node).contains("GROUP CONTENT"))
            XCTAssertTrue(allTexts(in: node).contains("DISCLOSED"))
        }
    }

    func testStringProtocolInputsMapToSelectionAndStepperControls() async {
        await MainActor.run {
            let source = "PREFIX-VALUE"
            let title = source.dropFirst(7)

            let node = makeNode(
                VStack {
                    Picker(title, selection: .constant("compact")) {
                        Text("COMPACT").tag("compact")
                    }
                    Stepper(title, value: .constant(2.0), in: 0...10)
                    Stepper(title, value: .constant(2), in: 0...10)
                }
            )

            XCTAssertGreaterThanOrEqual(allTexts(in: node).filter { $0 == "VALUE" }.count, 3)
            XCTAssertTrue(allTexts(in: node).contains("COMPACT"))
        }
    }

    func testTextCaseAppliesExplicitAndInheritedCasing() async {
        await MainActor.run {
            let uppercaseNode = makeNode(Text("MiXeD").textCase(.uppercase))
            let inheritedNode = makeNode(
                VStack {
                    Text("One")
                    Text("Two")
                        .textCase(nil)
                    Text("THREE")
                        .textCase(.lowercase)
                }
                .textCase(.uppercase)
            )

            XCTAssertEqual(uppercaseNode.text, "MIXED")
            XCTAssertEqual(inheritedNode.children[0].text, "ONE")
            XCTAssertEqual(inheritedNode.children[1].text, "Two")
            XCTAssertEqual(inheritedNode.children[2].text, "three")
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

    func testTextFieldAndSecureFieldPromptOverloadsMapToPlaceholder() async {
        await MainActor.run {
            let source = "FIELD-NAME"
            let substringTitle = source.dropFirst(6)

            let promptedNode = makeNode(
                TextField(substringTitle, text: .constant(""), prompt: Text("DISPLAY NAME"))
            )
            let valueNode = makeNode(
                TextField(LocalizedStringKey("NAME"), text: .constant("Alice"), prompt: Text("DISPLAY NAME"))
            )
            let securePromptNode = makeNode(
                SecureField("PASSWORD", text: .constant(""), prompt: Text("SECRET PHRASE"))
            )
            let secureValueNode = makeNode(
                SecureField(LocalizedStringKey("PASSWORD"), text: .constant("open"), prompt: Text("SECRET PHRASE"))
            )

            XCTAssertEqual(promptedNode.children[0].text, "DISPLAY NAME")
            XCTAssertEqual(valueNode.children[0].text, "Alice")
            XCTAssertEqual(securePromptNode.children[0].text, "SECRET PHRASE")
            XCTAssertEqual(secureValueNode.children[0].text, "****")
        }
    }

    func testTextFieldVerticalAxisMapsToMultilineInput() async {
        await MainActor.run {
            var value = "hi"
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(
                TextField(
                    LocalizedStringKey("NOTES"),
                    text: binding,
                    prompt: Text("ENTER NOTES"),
                    axis: .vertical
                )
            )

            XCTAssertTrue(node.isFocusable)
            XCTAssertEqual(node.preferredSize, Size(width: 260, height: 120))
            XCTAssertEqual(node.children[0].text, "hi")
            XCTAssertNil(node.children[0].textStyle.maximumNumberOfLines)
            XCTAssertEqual(node.children[0].textStyle.lineBreakMode, .wrap)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x4E))

            XCTAssertEqual(value, "hi\nn")
        }
    }

    func testTextInputAutocapitalizationAndAutocorrectionModifiersPropagate() async {
        await MainActor.run {
            struct TextInputEnvironmentReader: View {
                @Environment(\.textInputAutocapitalization) var textInputAutocapitalization
                @Environment(\.isAutocorrectionDisabled) var isAutocorrectionDisabled

                var body: some View {
                    Text(
                        "\(textInputAutocapitalization == .characters ? "CHARACTERS" : "OTHER") " +
                        "\(isAutocorrectionDisabled ? "DISABLED" : "ENABLED")"
                    )
                }
            }

            var wordsValue = ""
            let wordsBinding = Binding(
                get: { wordsValue },
                set: { wordsValue = $0 }
            )
            let wordsNode = makeNode(
                TextField("NAME", text: wordsBinding)
                    .textInputAutocapitalization(.words)
            )

            wordsNode.onKeyDown?(KeyboardEvent(keyCode: 0x41))
            wordsNode.onKeyDown?(KeyboardEvent(keyCode: 0x42))
            wordsNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
            wordsNode.onKeyDown?(KeyboardEvent(keyCode: 0x43))

            var sentenceValue = "hi. "
            let sentenceBinding = Binding(
                get: { sentenceValue },
                set: { sentenceValue = $0 }
            )
            let sentenceNode = makeNode(
                TextField("NOTE", text: sentenceBinding)
                    .textInputAutocapitalization(.sentences)
            )

            sentenceNode.onKeyDown?(KeyboardEvent(keyCode: 0x44))

            let readerNode = makeNode(
                TextInputEnvironmentReader()
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            )

            XCTAssertEqual(wordsValue, "Ab C")
            XCTAssertEqual(sentenceValue, "hi. D")
            XCTAssertEqual(readerNode.text, "CHARACTERS DISABLED")
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

    func testOnSubmitRunsForTextInputEnterAndPreservesOtherKeys() async {
        await MainActor.run {
            var value = ""
            var submitCount = 0
            var invalidationCount = 0
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(
                TextField("NAME", text: binding)
                    .onSubmit(of: .text) {
                        submitCount += 1
                    },
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: 0x41))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(value, "a")
            XCTAssertEqual(submitCount, 1)
            XCTAssertEqual(invalidationCount, 2)
        }
    }

    func testOnSubmitSearchTriggerRunsForRetainedTextInput() async {
        await MainActor.run {
            var submitCount = 0
            let node = makeNode(
                SecureField("SEARCH", text: .constant(""))
                    .onSubmit(of: .search) {
                        submitCount += 1
                    }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(submitCount, 1)
        }
    }

    func testOnSubmitPropagatesToNestedTextInputs() async {
        await MainActor.run {
            var value = ""
            var submitCount = 0
            var invalidationCount = 0
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(
                VStack {
                    TextField("NAME", text: binding)
                    Button("SAVE") {}
                }
                .onSubmit {
                    submitCount += 1
                },
                onInvalidate: {
                    invalidationCount += 1
                }
            )
            let fieldNode = node.children[0]
            let buttonNode = node.children[1]

            fieldNode.onKeyDown?(KeyboardEvent(keyCode: 0x42))
            fieldNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            buttonNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(value, "b")
            XCTAssertEqual(submitCount, 1)
            XCTAssertEqual(invalidationCount, 2)
        }
    }

    func testSubmitLabelModifierAcceptsSwiftUIReturnKeyLabels() async {
        await MainActor.run {
            var value = ""
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let searchNode = makeNode(
                TextField("SEARCH", text: binding)
                    .submitLabel(.search)
            )
            let continueNode = makeNode(
                SecureField("PASSWORD", text: .constant(""))
                    .submitLabel(.continue)
            )

            searchNode.onKeyDown?(KeyboardEvent(keyCode: 0x51))

            XCTAssertEqual(value, "q")
            XCTAssertTrue(continueNode.isFocusable)
        }
    }

    func testTextFieldStyleModifierMapsToRetainedInputChrome() async {
        await MainActor.run {
            struct TextFieldStyleReaderView: View {
                @Environment(\.textFieldStyle) var textFieldStyle

                var body: some View {
                    Text(textFieldStyle == .plain ? "PLAIN" : textFieldStyle == .roundedBorder ? "ROUNDED" : "AUTOMATIC")
                }
            }

            let plainNode = makeNode(
                TextField("NAME", text: .constant(""))
                    .textFieldStyle(.plain)
            )
            let roundedNode = makeNode(
                TextField("NAME", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
            )
            let inheritedNode = makeNode(
                VStack {
                    TextField("NAME", text: .constant(""))
                    SecureField("SECRET", text: .constant(""))
                }
                .textFieldStyle(.plain)
            )
            let readerNode = makeNode(TextFieldStyleReaderView().textFieldStyle(.plain))

            XCTAssertEqual(plainNode.backgroundColor, .clear)
            XCTAssertEqual(plainNode.borderWidth, 0)
            XCTAssertEqual(plainNode.cornerRadius, 0)
            XCTAssertEqual(roundedNode.borderWidth, 1)
            XCTAssertEqual(roundedNode.cornerRadius, 8)
            XCTAssertEqual(inheritedNode.children[0].backgroundColor, .clear)
            XCTAssertEqual(inheritedNode.children[1].backgroundColor, .clear)
            XCTAssertEqual(readerNode.text, "PLAIN")
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
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.4, blue: 1.0, alpha: 1),
                    Color(red: 0.9, green: 0.3, blue: 0.7, alpha: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            let filledRectangle = makeNode(Rectangle().fill(fillColor))
            let gradientRoundedRectangle = makeNode(
                RoundedRectangle(cornerRadius: 12)
                    .fill(gradient)
            )
            let semanticCapsule = makeNode(
                Capsule()
                    .fill(ForegroundStyle.color(.secondary))
            )
            let strokedRoundedRectangle = makeNode(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor, lineWidth: 2)
            )
            let strokeBorderRectangle = makeNode(
                Rectangle()
                    .strokeBorder(strokeColor, lineWidth: 4)
            )
            let strokeBorderRoundedRectangle = makeNode(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(strokeColor, lineWidth: 5)
            )
            let inheritedRectangle = makeNode(
                VStack {
                    Rectangle()
                        .frame(width: 12, height: 10)
                }
                .foregroundStyle(inheritedColor)
            )
            let inheritedGradientRectangle = makeNode(
                VStack {
                    Rectangle()
                        .frame(width: 12, height: 10)
                }
                .foregroundStyle(gradient)
            )

            XCTAssertEqual(filledRectangle.backgroundColor, fillColor)
            XCTAssertEqual(filledRectangle.cornerRadius, 0)
            XCTAssertEqual(gradientRoundedRectangle.backgroundColor, gradient.startColor)
            XCTAssertEqual(gradientRoundedRectangle.backgroundGradient, gradient)
            XCTAssertEqual(gradientRoundedRectangle.cornerRadius, 12)
            XCTAssertEqual(semanticCapsule.backgroundColor, .secondary)
            XCTAssertEqual(strokedRoundedRectangle.backgroundColor, .clear)
            XCTAssertEqual(strokedRoundedRectangle.borderColor, strokeColor)
            XCTAssertEqual(strokedRoundedRectangle.borderWidth, 2)
            XCTAssertEqual(strokedRoundedRectangle.cornerRadius, 8)
            XCTAssertEqual(strokeBorderRectangle.backgroundColor, .clear)
            XCTAssertEqual(strokeBorderRectangle.borderColor, strokeColor)
            XCTAssertEqual(strokeBorderRectangle.borderWidth, 4)
            XCTAssertEqual(strokeBorderRoundedRectangle.backgroundColor, .clear)
            XCTAssertEqual(strokeBorderRoundedRectangle.borderColor, strokeColor)
            XCTAssertEqual(strokeBorderRoundedRectangle.borderWidth, 5)
            XCTAssertEqual(strokeBorderRoundedRectangle.cornerRadius, 10)
            XCTAssertEqual(inheritedRectangle.children[0].children[0].backgroundColor, inheritedColor)
            XCTAssertEqual(inheritedGradientRectangle.children[0].children[0].backgroundColor, gradient.startColor)
            XCTAssertEqual(inheritedGradientRectangle.children[0].children[0].backgroundGradient, gradient)
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
                Capsule()
                    .strokeBorder(strokeColor, lineWidth: 4)
                    .frame(width: 60, height: 18)
            }
            let node = root.makeComponent(context: context).makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            _ = runtime.renderFrame()

            let filledCapsule = node.children[0].children[0]
            let strokedCapsule = node.children[1].children[0]
            let strokeBorderCapsule = node.children[2].children[0]
            XCTAssertEqual(filledCapsule.backgroundColor, fillColor)
            XCTAssertEqual(filledCapsule.cornerRadius, 6)
            XCTAssertEqual(strokedCapsule.backgroundColor, .clear)
            XCTAssertEqual(strokedCapsule.borderColor, strokeColor)
            XCTAssertEqual(strokedCapsule.borderWidth, 3)
            XCTAssertEqual(strokedCapsule.cornerRadius, 10)
            XCTAssertEqual(strokeBorderCapsule.backgroundColor, .clear)
            XCTAssertEqual(strokeBorderCapsule.borderColor, strokeColor)
            XCTAssertEqual(strokeBorderCapsule.borderWidth, 4)
            XCTAssertEqual(strokeBorderCapsule.cornerRadius, 9)
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

    func testMonospacedFontConveniencesPreserveResolvedSizeAndWeight() async {
        await MainActor.run {
            let fontNode = makeNode(
                Text("CODE")
                    .font(.system(size: 14, weight: .semibold).monospaced())
            )
            let inheritedTextNode = makeNode(
                VStack {
                    Text("VALUE")
                        .monospaced()
                }
                .font(.system(size: 18, weight: .bold))
            )

            XCTAssertEqual(fontNode.textStyle.nativeFontSize, 14)
            XCTAssertEqual(fontNode.textStyle.weight, .semibold)
            XCTAssertEqual(fontNode.textStyle.fontFamily, "Cascadia Mono")

            let child = inheritedTextNode.children[0]
            XCTAssertEqual(child.textStyle.nativeFontSize, 18)
            XCTAssertEqual(child.textStyle.weight, .bold)
            XCTAssertEqual(child.textStyle.fontFamily, "Cascadia Mono")
        }
    }

    func testFontModifierAndEnvironmentValueBridgeRetainedTextFont() async {
        await MainActor.run {
            struct FontEnvironmentReaderView: View {
                @Environment(\.font) var font

                var body: some View {
                    Text(font == .system(size: 18, weight: .bold, design: .monospaced) ? "FONT" : "DEFAULT")
                }
            }

            let environmentFont = Font.system(size: 18, weight: .bold, design: .monospaced)
            let optionalFont: Font? = .system(size: 16, weight: .semibold)
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                    Text("RESET")
                        .font(nil as Font?)
                }
                .font(environmentFont)
            )
            let optionalNode = makeNode(
                Text("OPTIONAL")
                    .font(optionalFont)
            )
            let environmentNode = makeNode(
                Text("ENVIRONMENT")
                    .environment(\.font, environmentFont)
            )
            let readerNode = makeNode(
                FontEnvironmentReaderView()
                    .font(environmentFont)
            )

            XCTAssertEqual(inheritedNode.children[0].textStyle.nativeFontSize, 18)
            XCTAssertEqual(inheritedNode.children[0].textStyle.weight, .bold)
            XCTAssertEqual(inheritedNode.children[0].textStyle.fontFamily, "Cascadia Mono")
            XCTAssertEqual(inheritedNode.children[1].textStyle.nativeFontSize, 20)
            XCTAssertEqual(inheritedNode.children[1].textStyle.weight, .regular)
            XCTAssertEqual(optionalNode.textStyle.nativeFontSize, 16)
            XCTAssertEqual(optionalNode.textStyle.weight, .semibold)
            XCTAssertEqual(environmentNode.textStyle.nativeFontSize, 18)
            XCTAssertEqual(environmentNode.textStyle.fontFamily, "Cascadia Mono")
            XCTAssertEqual(readerNode.text, "FONT")
        }
    }

    func testFontDesignModifierPropagatesThroughViewContext() async {
        await MainActor.run {
            let inheritedNode = makeNode(
                VStack {
                    Text("CODE")
                }
                .font(.system(size: 18, weight: .bold))
                .fontDesign(.monospaced)
            )
            let textNode = makeNode(
                Text("DEFAULT")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .fontDesign(.default)
            )

            let child = inheritedNode.children[0]
            XCTAssertEqual(child.textStyle.nativeFontSize, 18)
            XCTAssertEqual(child.textStyle.weight, .bold)
            XCTAssertEqual(child.textStyle.fontFamily, "Cascadia Mono")

            XCTAssertEqual(textNode.textStyle.nativeFontSize, 14)
            XCTAssertEqual(textNode.textStyle.weight, .semibold)
            XCTAssertEqual(textNode.textStyle.fontFamily, "Segoe UI")
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

    func testTextSpacingModifiersMapToRetainedTextStyleAndMeasurement() async {
        await MainActor.run {
            let spacedNode = makeNode(
                Text("A\nB")
                    .lineSpacing(6)
                    .kerning(4)
            )
            let trackingNode = makeNode(
                Text("AB")
                    .tracking(3)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("A\nB")
                    Text("C\nD")
                        .lineSpacing(8)
                }
                .lineSpacing(5)
            )

            XCTAssertEqual(spacedNode.textStyle.lineSpacing, 6)
            XCTAssertEqual(spacedNode.textStyle.letterSpacing, 4)
            XCTAssertEqual(trackingNode.textStyle.letterSpacing, 3)
            XCTAssertEqual(inheritedNode.children[0].textStyle.lineSpacing, 5)
            XCTAssertEqual(inheritedNode.children[1].textStyle.lineSpacing, 8)

            let defaultMultilineHeight = makeNode(Text("A\nB")).intrinsicContentSize().height
            let spacedHeight = spacedNode.intrinsicContentSize().height
            XCTAssertGreaterThan(spacedHeight, defaultMultilineHeight)
        }
    }

    func testAllowsTighteningMapsToRetainedKerningFlag() async {
        await MainActor.run {
            let defaultNode = makeNode(Text("DEFAULT"))
            let tightenedNode = makeNode(Text("TIGHT").allowsTightening(false))
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                    Text("EXPLICIT")
                        .allowsTightening(true)
                }
                .allowsTightening(false)
            )

            XCTAssertTrue(defaultNode.textStyle.enableKerning)
            XCTAssertFalse(tightenedNode.textStyle.enableKerning)
            XCTAssertFalse(inheritedNode.children[0].textStyle.enableKerning)
            XCTAssertTrue(inheritedNode.children[1].textStyle.enableKerning)
        }
    }

    func testTruncationModeMapsToRetainedLineBreakMode() async {
        await MainActor.run {
            let headNode = makeNode(
                Text("HEAD")
                    .lineLimit(1)
                    .truncationMode(.head)
            )
            let middleNode = makeNode(
                Text("MIDDLE")
                    .lineLimit(1)
                    .truncationMode(.middle)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                    Text("EXPLICIT")
                        .truncationMode(.tail)
                }
                .lineLimit(1)
                .truncationMode(.head)
            )

            XCTAssertEqual(headNode.textStyle.lineBreakMode, .truncateHead)
            XCTAssertEqual(middleNode.textStyle.lineBreakMode, .truncateMiddle)
            XCTAssertEqual(inheritedNode.children[0].textStyle.lineBreakMode, .truncateHead)
            XCTAssertEqual(inheritedNode.children[1].textStyle.lineBreakMode, .truncateTail)
        }
    }

    func testLineLimitReservesSpaceOverloadsMapToRetainedMaximumLines() async {
        await MainActor.run {
            let textNode = makeNode(
                Text("TITLE")
                    .lineLimit(2, reservesSpace: true)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("ONE")
                    Text("TWO")
                        .lineLimit(1, reservesSpace: false)
                }
                .lineLimit(3, reservesSpace: true)
            )

            XCTAssertEqual(textNode.textStyle.maximumNumberOfLines, 2)
            XCTAssertEqual(inheritedNode.children[0].textStyle.maximumNumberOfLines, 3)
            XCTAssertEqual(inheritedNode.children[1].textStyle.maximumNumberOfLines, 1)
        }
    }

    func testTextEnvironmentValuesBridgeRetainedTextStyle() async {
        await MainActor.run {
            struct TextEnvironmentReaderView: View {
                @Environment(\.multilineTextAlignment) var alignment
                @Environment(\.lineLimit) var lineLimit
                @Environment(\.truncationMode) var truncationMode
                @Environment(\.allowsTightening) var allowsTightening
                @Environment(\.textCase) var textCase

                var body: some View {
                    Text(
                        alignment == .trailing
                            && lineLimit == 2
                            && truncationMode == .middle
                            && allowsTightening
                            && textCase == .uppercase
                            ? "ENV"
                            : "DEFAULT"
                    )
                }
            }

            let environmentNode = makeNode(
                Text("mixed")
                    .environment(\.multilineTextAlignment, .trailing)
                    .environment(\.lineLimit, 2)
                    .environment(\.truncationMode, .middle)
                    .environment(\.allowsTightening, true)
                    .environment(\.textCase, .uppercase)
            )
            let resetNode = makeNode(
                VStack {
                    Text("RESET")
                        .lineLimit(nil)
                        .environment(\.truncationMode, nil)
                        .allowsTightening(false)
                        .textCase(nil)
                }
                .lineLimit(1)
                .truncationMode(.head)
                .allowsTightening(true)
                .textCase(.uppercase)
            )
            let readerNode = makeNode(
                TextEnvironmentReaderView()
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .allowsTightening(true)
                    .textCase(.uppercase)
            )

            XCTAssertEqual(environmentNode.text, "MIXED")
            XCTAssertEqual(environmentNode.textStyle.alignment, .trailing)
            XCTAssertEqual(environmentNode.textStyle.maximumNumberOfLines, 2)
            XCTAssertEqual(environmentNode.textStyle.lineBreakMode, .truncateMiddle)
            XCTAssertTrue(environmentNode.textStyle.enableKerning)
            XCTAssertEqual(resetNode.children[0].text, "RESET")
            XCTAssertNil(resetNode.children[0].textStyle.maximumNumberOfLines)
            XCTAssertEqual(resetNode.children[0].textStyle.lineBreakMode, .wrap)
            XCTAssertFalse(resetNode.children[0].textStyle.enableKerning)
            XCTAssertEqual(readerNode.text, "ENV")
        }
    }

    func testTextDecorationModifiersMapToRetainedTextStyle() async {
        await MainActor.run {
            let decoratedNode = makeNode(
                Text("LINK")
                    .underline(color: .blue)
                    .strikethrough()
            )
            let disabledNode = makeNode(
                Text("PLAIN")
                    .underline(false)
                    .strikethrough(false, color: .red)
            )

            XCTAssertTrue(decoratedNode.textStyle.underline)
            XCTAssertTrue(decoratedNode.textStyle.strikethrough)
            XCTAssertFalse(disabledNode.textStyle.underline)
            XCTAssertFalse(disabledNode.textStyle.strikethrough)
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

    func testOptionalForegroundColorAndTextFontModifiersMapToInheritedStyle() async {
        await MainActor.run {
            let inheritedColor = Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)
            let optionalColor: Color? = Color(red: 0.1, green: 0.7, blue: 0.4, alpha: 1)
            let nilColor: Color? = nil
            let inheritedFont = Font.system(size: 16, weight: .bold, design: .monospaced)
            let optionalFont: Font? = .system(size: 18, weight: .semibold, design: .rounded)
            let nilFont: Font? = nil

            let node = makeNode(
                VStack {
                    Text("OPTIONAL")
                        .foregroundColor(optionalColor)
                        .font(optionalFont)
                    Text("RESET")
                        .foregroundColor(optionalColor)
                        .foregroundColor(nilColor)
                        .font(.system(size: 20, weight: .light))
                        .font(nilFont)
                    Image(systemName: "gear")
                        .foregroundColor(optionalColor)
                    Label("LABEL", systemImage: "info.circle")
                        .foregroundColor(optionalColor)
                    VStack {
                        Text("INHERITED")
                    }
                    .foregroundColor(nilColor)
                }
                .foregroundColor(inheritedColor)
                .font(inheritedFont)
            )

            XCTAssertEqual(node.children[0].textStyle.color, optionalColor)
            XCTAssertEqual(node.children[0].textStyle.nativeFontSize, 18)
            XCTAssertEqual(node.children[0].textStyle.weight, .semibold)
            XCTAssertEqual(node.children[0].textStyle.fontFamily, "Segoe UI")

            XCTAssertEqual(node.children[1].textStyle.color, inheritedColor)
            XCTAssertEqual(node.children[1].textStyle.nativeFontSize, 20)
            XCTAssertEqual(node.children[1].textStyle.weight, .regular)
            XCTAssertEqual(node.children[1].textStyle.fontFamily, "Segoe UI")

            XCTAssertEqual(node.children[2].textStyle.color, optionalColor)
            XCTAssertEqual(node.children[3].children[0].textStyle.color, optionalColor)
            XCTAssertEqual(node.children[3].children[1].textStyle.color, optionalColor)
            XCTAssertEqual(node.children[4].children[0].textStyle.color, inheritedColor)
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

    func testForegroundStyleValueAndSemanticShorthandPropagateToText() async {
        await MainActor.run {
            let storedStyle = ForegroundStyle.color(Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
            let storedNode = makeNode(
                VStack {
                    Text("STORED")
                }
                .foregroundStyle(storedStyle)
            )
            let secondaryNode = makeNode(
                Text("SECONDARY")
                    .foregroundStyle(.secondary)
            )
            let gradient = LinearGradient(
                colors: [.red, .blue],
                startPoint: .leading,
                endPoint: .trailing
            )
            let gradientNode = makeNode(
                Text("GRADIENT")
                    .foregroundStyle(ForegroundStyle.linearGradient(gradient))
            )

            XCTAssertEqual(storedNode.children[0].textStyle.color, Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
            XCTAssertEqual(secondaryNode.textStyle.color, .secondary)
            XCTAssertEqual(gradientNode.textStyle.color, gradient.startColor)
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

    func testLabelSupportsBuilderTitleAndIconSyntax() async {
        await MainActor.run {
            let inheritedColor = Color(red: 0.2, green: 0.8, blue: 0.5, alpha: 1)
            let node = makeNode(
                Label {
                    Text("CUSTOM")
                } icon: {
                    Image(systemName: "gear")
                }
                .foregroundColor(inheritedColor)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[1].text, "CUSTOM")
            for child in node.children {
                XCTAssertEqual(child.textStyle.color, inheritedColor)
            }
            XCTAssertEqual(node.children[1].textStyle.nativeFontSize, 14)
            XCTAssertEqual(node.children[1].textStyle.weight, .bold)
            XCTAssertEqual(node.children[1].textStyle.fontFamily, "Cascadia Mono")
        }
    }

    func testLabelStyleModifierSelectsRetainedLabelContent() async {
        await MainActor.run {
            let iconOnlyNode = makeNode(Label("SETTINGS", systemImage: "gear").labelStyle(.iconOnly))
            let titleOnlyNode = makeNode(Label("SETTINGS", systemImage: "gear").labelStyle(.titleOnly))
            let inheritedNode = makeNode(
                VStack {
                    Label("SETTINGS", systemImage: "gear")
                    Label("PROFILE", systemImage: "person")
                        .labelStyle(.titleAndIcon)
                }
                .labelStyle(.titleOnly)
            )

            XCTAssertFalse(allTexts(in: iconOnlyNode).contains("SETTINGS"))
            XCTAssertEqual(titleOnlyNode.text, "SETTINGS")
            XCTAssertEqual(inheritedNode.children[0].text, "SETTINGS")
            XCTAssertEqual(inheritedNode.children[1].children.count, 2)
            XCTAssertEqual(inheritedNode.children[1].children[1].text, "PROFILE")
        }
    }

    func testImageScalingCompatibilityModifiersMapToPreferredIconSize() async {
        await MainActor.run {
            let color = Color(red: 0.4, green: 0.7, blue: 1.0, alpha: 1)
            let fillNode = makeNode(
                Image(systemName: "gear")
                    .font(.system(size: 20))
                    .resizable(resizingMode: .stretch)
                    .aspectRatio(1, contentMode: .fill)
                    .foregroundColor(color)
            )
            let wideFitNode = makeNode(
                Image(systemName: "gear")
                    .font(.system(size: 20))
                    .resizable()
                    .aspectRatio(2, contentMode: .fit)
            )
            let scaledToFillNode = makeNode(
                Image(systemName: "gear")
                    .font(.system(size: 20))
                    .scaledToFill()
            )

            XCTAssertEqual(fillNode.textStyle.color, color)
            XCTAssertEqual(fillNode.preferredSize, Size(width: 20, height: 20))
            XCTAssertEqual(wideFitNode.preferredSize, Size(width: 20, height: 10))
            XCTAssertEqual(scaledToFillNode.preferredSize, Size(width: 20, height: 20))
        }
    }

    func testNamedImageLoadsBitmapAndAppliesAspectSizing() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-image-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let nativeNode = makeNode(Image(url.path))
            let fittedNode = makeNode(
                Image(url.path)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            )

            XCTAssertEqual(nativeNode.bitmapSurface?.width, 2)
            XCTAssertEqual(nativeNode.bitmapSurface?.height, 1)
            XCTAssertEqual(nativeNode.preferredSize, Size(width: 2, height: 1))
            XCTAssertEqual(fittedNode.preferredSize, Size(width: 1, height: 1))
        }
    }

    func testImageCompatibilityInitializersReuseBitmapAndSystemIconPaths() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-image-overloads-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let labeledNode = makeNode(Image(url.path, label: Text("PHOTO")))
            let decorativeNode = makeNode(Image(decorative: url.path))
            let variableSymbolNode = makeNode(
                Image(systemName: "gearshape", variableValue: 0.42)
                    .foregroundColor(.red)
            )

            XCTAssertEqual(labeledNode.bitmapSurface?.width, 2)
            XCTAssertEqual(labeledNode.bitmapSurface?.height, 1)
            XCTAssertEqual(decorativeNode.bitmapSurface?.width, 2)
            XCTAssertEqual(decorativeNode.bitmapSurface?.height, 1)
            XCTAssertEqual(variableSymbolNode.text, "\u{E713}")
            XCTAssertEqual(variableSymbolNode.textStyle.color, .red)
        }
    }

    func testImageLabelAndDecorativeInitializersSetAccessibilityMetadata() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-image-accessibility-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let labeledNode = makeNode(Image(url.path, label: Text("Preview image")))
            let decorativeNode = makeNode(Image(decorative: url.path))

            XCTAssertEqual(labeledNode.accessibilityLabel, "Preview image")
            XCTAssertFalse(labeledNode.isAccessibilityHidden)
            XCTAssertTrue(decorativeNode.isAccessibilityHidden)
        }
    }

    func testImageScaleModifierAndEnvironmentScaleSystemIcons() async {
        await MainActor.run {
            struct ImageScaleReaderView: View {
                @Environment(\.imageScale) var imageScale

                var body: some View {
                    Text(imageScale == .large ? "LARGE" : imageScale == .small ? "SMALL" : "MEDIUM")
                }
            }

            let defaultNode = makeNode(Image(systemName: "gear"))
            let smallNode = makeNode(Image(systemName: "gear").imageScale(.small))
            let largeNode = makeNode(
                VStack {
                    Image(systemName: "gear")
                    Label("SETTINGS", systemImage: "gear")
                }
                .imageScale(.large)
            )
            let environmentNode = makeNode(
                Image(systemName: "gear")
                    .environment(\.imageScale, .small)
            )
            let readerNode = makeNode(ImageScaleReaderView().imageScale(.large))

            XCTAssertEqual(defaultNode.textStyle.scale, 1.9)
            XCTAssertEqual(smallNode.textStyle.scale, 1.9 * 0.82)
            XCTAssertEqual(largeNode.children[0].textStyle.scale, 1.9 * 1.25)
            XCTAssertEqual(largeNode.children[1].children[0].textStyle.scale, 1.9 * 1.25)
            XCTAssertEqual(environmentNode.textStyle.scale, 1.9 * 0.82)
            XCTAssertEqual(readerNode.text, "LARGE")
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

    func testBackgroundAcceptsOptionalColorAndIgnoresSafeAreaEdgesLabel() async {
        await MainActor.run {
            let optionalColor: Color? = Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
            let nilColor: Color? = nil
            let optionalNode = makeNode(
                Text("OPTIONAL")
                    .background(optionalColor, ignoresSafeAreaEdges: .top)
            )
            let concreteNode = makeNode(
                Text("CONCRETE")
                    .background(Color(red: 0.7, green: 0.2, blue: 0.4, alpha: 1), ignoresSafeAreaEdges: .all)
            )
            let nilNode = makeNode(
                Text("PLAIN")
                    .background(nilColor)
            )

            XCTAssertEqual(optionalNode.backgroundColor, optionalColor)
            XCTAssertEqual(firstText(in: optionalNode.children[0]), "OPTIONAL")
            XCTAssertEqual(concreteNode.children[0].text, "CONCRETE")
            XCTAssertEqual(nilNode.text, "PLAIN")
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

    func testLazyStacksMapToRetainedStackPanels() async {
        await MainActor.run {
            let lazyVStack = makeNode(
                LazyVStack(alignment: .trailing, spacing: 7, pinnedViews: [.sectionHeaders]) {
                    Text("A")
                    Text("B")
                }
            )
            let lazyHStack = makeNode(
                LazyHStack(alignment: .bottom, spacing: 5, pinnedViews: [.sectionFooters]) {
                    Text("C")
                    Text("D")
                }
            )

            guard case .stack(let verticalLayout) = lazyVStack.layoutMode else {
                return XCTFail("Expected LazyVStack to use retained stack layout")
            }
            guard case .stack(let horizontalLayout) = lazyHStack.layoutMode else {
                return XCTFail("Expected LazyHStack to use retained stack layout")
            }

            XCTAssertEqual(verticalLayout, .vertical(spacing: 7, alignment: .trailing))
            XCTAssertEqual(horizontalLayout, .horizontal(spacing: 5, alignment: .trailing))
            XCTAssertEqual(lazyVStack.children.count, 2)
            XCTAssertEqual(lazyHStack.children.count, 2)
            XCTAssertEqual(lazyVStack.children[0].text, "A")
            XCTAssertEqual(lazyVStack.children[1].text, "B")
            XCTAssertEqual(lazyHStack.children[0].text, "C")
            XCTAssertEqual(lazyHStack.children[1].text, "D")
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

    func testListDataInitializerRendersRowsWithStableIDs() async {
        await MainActor.run {
            let node = makeNode(
                List(["ONE", "TWO"], id: \.self) { title in
                    Text(title)
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "ONE")
            XCTAssertEqual(node.children[1].text, "TWO")
            XCTAssertEqual(node.children[0].nodeTag, "ONE#0")
            XCTAssertEqual(node.children[1].nodeTag, "TWO#0")
        }
    }

    func testListIdentifiableInitializerRendersRowsWithStableIDs() async {
        await MainActor.run {
            struct Row: Identifiable {
                let id: Int
                let title: String
            }

            let rows = [
                Row(id: 7, title: "SEVEN"),
                Row(id: 9, title: "NINE"),
            ]
            let node = makeNode(
                List(rows) { row in
                    Text(row.title)
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "SEVEN")
            XCTAssertEqual(node.children[1].text, "NINE")
            XCTAssertEqual(node.children[0].nodeTag, "7#0")
            XCTAssertEqual(node.children[1].nodeTag, "9#0")
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

    func testSectionSupportsHeaderFooterBuilderSyntax() async {
        await MainActor.run {
            let node = makeNode(
                Section {
                    Text("ROW")
                } header: {
                    Text("HEADER")
                } footer: {
                    Text("FOOTER")
                }
            )

            guard case .stack(let stackLayout) = node.layoutMode else {
                return XCTFail("Expected Section to use retained stack layout")
            }

            XCTAssertEqual(stackLayout, .vertical(spacing: 16, padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18), alignment: .leading))
            XCTAssertEqual(node.borderWidth, 1)
            XCTAssertEqual(node.cornerRadius, 28)
            XCTAssertEqual(node.children.count, 3)
            XCTAssertEqual(node.children[0].text, "HEADER")
            XCTAssertEqual(node.children[1].text, "ROW")
            XCTAssertEqual(node.children[2].text, "FOOTER")
            XCTAssertEqual(node.children[0].textStyle.color, SectionStyle.default.headerColor)
            XCTAssertEqual(node.children[2].textStyle.color, .secondary)
        }
    }

    func testSectionContentOnlySyntaxBuildsRowsWithoutHeader() async {
        await MainActor.run {
            let node = makeNode(
                Section {
                    Text("ONE")
                    Text("TWO")
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "ONE")
            XCTAssertEqual(node.children[1].text, "TWO")
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

    func testNavigationContainersRenderTitleChromeWhenProvided() async {
        await MainActor.run {
            var path = NavigationPath()
            path.append("detail")
            path.removeLast()

            let stackNode = makeNode(
                NavigationStack(path: Binding.constant(path)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ROOT")
                        Text("DETAIL")
                    }
                    .navigationTitle(Text("HOME"))
                    .navigationBarTitleDisplayMode(.inline)
                }
            )
            let genericPathNode = makeNode(
                NavigationStack(path: Binding.constant([1, 2])) {
                    Text("GENERIC")
                        .navigationTitle("GENERIC TITLE")
                }
            )
            let legacyNode = makeNode(
                NavigationView {
                    Text("LEGACY")
                        .navigationBarTitle("LEGACY TITLE", displayMode: .large)
                }
            )

            guard case .stack(let stackLayout) = stackNode.layoutMode else {
                return XCTFail("Expected NavigationStack to wrap titled content in retained chrome")
            }

            XCTAssertTrue(path.isEmpty)
            XCTAssertEqual(stackLayout, .vertical(spacing: 10, alignment: .stretch))
            XCTAssertEqual(stackNode.children.count, 2)
            XCTAssertTrue(allTexts(in: stackNode.children[0]).contains("HOME"))
            XCTAssertEqual(stackNode.children[1].children.count, 2)
            XCTAssertEqual(stackNode.children[1].children[0].text, "ROOT")
            XCTAssertEqual(stackNode.children[1].children[1].text, "DETAIL")
            XCTAssertTrue(allTexts(in: genericPathNode.children[0]).contains("GENERIC TITLE"))
            XCTAssertEqual(genericPathNode.children[1].text, "GENERIC")
            XCTAssertTrue(allTexts(in: legacyNode.children[0]).contains("LEGACY TITLE"))
            XCTAssertEqual(legacyNode.children[1].text, "LEGACY")
        }
    }

    func testNavigationContainersWithoutTitlePreserveRootLayout() async {
        await MainActor.run {
            let stackNode = makeNode(
                NavigationStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ROOT")
                        Text("DETAIL")
                    }
                }
            )

            guard case .stack(let stackLayout) = stackNode.layoutMode else {
                return XCTFail("Expected untitled NavigationStack root content to render directly")
            }

            XCTAssertEqual(stackLayout, .vertical(spacing: 3, alignment: .leading))
            XCTAssertEqual(stackNode.children.count, 2)
            XCTAssertEqual(stackNode.children[0].text, "ROOT")
            XCTAssertEqual(stackNode.children[1].text, "DETAIL")
        }
    }

    func testNavigationSplitViewMapsColumnsToHorizontalStack() async {
        await MainActor.run {
            let threeColumnNode = makeNode(
                NavigationSplitView {
                    Text("SIDEBAR")
                } content: {
                    Text("CONTENT")
                } detail: {
                    Text("DETAIL")
                }
            )
            let twoColumnNode = makeNode(
                NavigationSplitView(columnVisibility: Binding.constant(.all)) {
                    Text("LIST")
                } detail: {
                    Text("SELECTED")
                }
            )

            guard case .stack(let threeColumnLayout) = threeColumnNode.layoutMode else {
                return XCTFail("Expected NavigationSplitView to use retained stack layout")
            }
            guard case .stack(let twoColumnLayout) = twoColumnNode.layoutMode else {
                return XCTFail("Expected NavigationSplitView to use retained stack layout")
            }

            XCTAssertEqual(threeColumnLayout, .horizontal(spacing: 0, alignment: .stretch))
            XCTAssertEqual(twoColumnLayout, .horizontal(spacing: 0, alignment: .stretch))
            XCTAssertEqual(threeColumnNode.children.count, 3)
            XCTAssertEqual(twoColumnNode.children.count, 2)
            XCTAssertEqual(threeColumnNode.children[0].text, "SIDEBAR")
            XCTAssertEqual(threeColumnNode.children[1].text, "CONTENT")
            XCTAssertEqual(threeColumnNode.children[2].text, "DETAIL")
            XCTAssertEqual(twoColumnNode.children[0].text, "LIST")
            XCTAssertEqual(twoColumnNode.children[1].text, "SELECTED")
        }
    }

    func testNavigationSplitViewColumnVisibilityFiltersRetainedColumns() async {
        await MainActor.run {
            let doubleColumnNode = makeNode(
                NavigationSplitView(columnVisibility: Binding.constant(.doubleColumn)) {
                    Text("SIDEBAR")
                } content: {
                    Text("CONTENT")
                } detail: {
                    Text("DETAIL")
                }
            )
            let detailOnlyNode = makeNode(
                NavigationSplitView(columnVisibility: Binding.constant(.detailOnly)) {
                    Text("SIDEBAR")
                } content: {
                    Text("CONTENT")
                } detail: {
                    Text("DETAIL")
                }
            )
            let twoColumnDetailNode = makeNode(
                NavigationSplitView(columnVisibility: Binding.constant(.detailOnly)) {
                    Text("LIST")
                } detail: {
                    Text("SELECTED")
                }
            )

            XCTAssertEqual(doubleColumnNode.children.count, 2)
            XCTAssertEqual(doubleColumnNode.children[0].text, "CONTENT")
            XCTAssertEqual(doubleColumnNode.children[1].text, "DETAIL")
            XCTAssertEqual(detailOnlyNode.children.count, 1)
            XCTAssertEqual(detailOnlyNode.children[0].text, "DETAIL")
            XCTAssertEqual(twoColumnDetailNode.children.count, 1)
            XCTAssertEqual(twoColumnDetailNode.children[0].text, "SELECTED")
        }
    }

    func testTabViewRendersSelectedTaggedPage() async {
        await MainActor.run {
            var didInvalidate = false
            let tabView = TabView {
                Text("FIRST")
                    .tabItem { Label("FIRST TAB", systemImage: "house") }
                Text("SECOND")
                    .tag("second")
                    .tabItem { Text("SECOND TAB") }
            }
            let defaultNode = makeNode(
                tabView,
                onInvalidate: {
                    didInvalidate = true
                }
            )
            let selectedNode = makeNode(
                TabView(selection: Binding.constant("second")) {
                    Text("FIRST")
                        .tag("first")
                    Text("SECOND")
                        .tag("second")
                    Text("THIRD")
                        .tag("third")
                }
            )
            let fallbackNode = makeNode(
                TabView(selection: Binding.constant("missing")) {
                    Text("FALLBACK")
                        .tag("fallback")
                    Text("OTHER")
                        .tag("other")
                }
            )

            XCTAssertEqual(defaultNode.children.count, 2)
            XCTAssertTrue(allTexts(in: defaultNode.children[0]).contains("FIRST TAB"))
            XCTAssertTrue(allTexts(in: defaultNode.children[0]).contains("SECOND TAB"))
            XCTAssertEqual(defaultNode.children[1].text, "FIRST")
            defaultNode.children[0].children[1].onActivate?()
            XCTAssertTrue(didInvalidate)

            let switchedNode = makeNode(tabView)
            XCTAssertEqual(switchedNode.children[1].text, "SECOND")
            XCTAssertEqual(selectedNode.children[1].text, "SECOND")
            XCTAssertEqual(fallbackNode.children[1].text, "FALLBACK")
        }
    }

    func testBoundTabViewWritesSelectionFromTabChrome() async {
        await MainActor.run {
            var selection = "first"
            let tabView = TabView(
                selection: Binding(
                    get: { selection },
                    set: { selection = $0 }
                )
            ) {
                Text("FIRST")
                    .tag("first")
                    .tabItem { Text("FIRST TAB") }
                Text("SECOND")
                    .tag("second")
                    .tabItem { Text("SECOND TAB") }
            }
            let node = makeNode(tabView)

            XCTAssertEqual(node.children[1].text, "FIRST")

            node.children[0].children[1].onActivate?()

            XCTAssertEqual(selection, "second")
            XCTAssertEqual(makeNode(tabView).children[1].text, "SECOND")
        }
    }

    func testNavigationLinkRendersLabelContent() async {
        await MainActor.run {
            let node = makeNode(
                VStack(alignment: .leading, spacing: 2) {
                    NavigationLink("SHOW", destination: Text("DESTINATION"))
                    NavigationLink(value: "settings") {
                        Label("SETTINGS", systemImage: "gear")
                    }
                    NavigationLink(LocalizedStringKey("ITEM"), value: 3)
                }
            )

            XCTAssertEqual(node.children.count, 3)
            XCTAssertTrue(allTexts(in: node.children[0]).contains("SHOW"))
            XCTAssertTrue(allTexts(in: node.children[1]).contains("SETTINGS"))
            XCTAssertTrue(allTexts(in: node.children[2]).contains("ITEM"))
        }
    }

    func testNavigationLinkDestinationBuilderRendersLabelAndPushesDestination() async {
        await MainActor.run {
            var didInvalidate = false
            let stack = NavigationStack {
                NavigationLink {
                    VStack {
                        Text("DETAIL")
                        Text("MORE")
                    }
                    .navigationTitle("DETAIL TITLE")
                } label: {
                    Label("OPEN", systemImage: "chevron.right")
                }
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(
                stack,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(allTexts(in: rootNode.children[1]).contains("OPEN"))

            rootNode.children[1].onActivate?()

            XCTAssertTrue(didInvalidate)

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("DETAIL TITLE"))
            XCTAssertEqual(detailNode.children[1].children[0].text, "DETAIL")
            XCTAssertEqual(detailNode.children[1].children[1].text, "MORE")
        }
    }

    func testNavigationLinkDestinationPushesInRetainedNavigationContainer() async {
        await MainActor.run {
            var didInvalidate = false
            let stack = NavigationStack {
                VStack(alignment: .leading, spacing: 2) {
                    NavigationLink("OPEN", destination: Text("DETAIL").navigationTitle("DETAIL TITLE"))
                }
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(
                stack,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(allTexts(in: rootNode.children[0]).contains("ROOT TITLE"))
            XCTAssertTrue(allTexts(in: rootNode.children[1]).contains("OPEN"))

            rootNode.children[1].children[0].onActivate?()

            XCTAssertTrue(didInvalidate)

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("DETAIL TITLE"))
            XCTAssertEqual(detailNode.children[1].text, "DETAIL")

            detailNode.children[0].children[0].onActivate?()

            let poppedNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: poppedNode.children[0]).contains("ROOT TITLE"))
            XCTAssertTrue(allTexts(in: poppedNode.children[1]).contains("OPEN"))
        }
    }

    func testNavigationLinkValueResolvesNavigationDestination() async {
        await MainActor.run {
            var didInvalidate = false
            let stack = NavigationStack {
                VStack(alignment: .leading, spacing: 2) {
                    NavigationLink("OPEN", value: "detail")
                }
                .navigationTitle("ROOT TITLE")
            }
            .navigationDestination(for: String.self) { value in
                Text("VALUE \(value)")
                    .navigationTitle("VALUE TITLE")
            }

            let rootNode = makeNode(
                stack,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            rootNode.children[1].children[0].onActivate?()

            XCTAssertTrue(didInvalidate)

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("VALUE TITLE"))
            XCTAssertEqual(detailNode.children[1].text, "VALUE detail")
        }
    }

    func testNavigationStackPathBindingSyncsValuePushAndBack() async {
        await MainActor.run {
            var path = NavigationPath()
            let stack = NavigationStack(
                path: Binding(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    NavigationLink("OPEN", value: "detail")
                }
                .navigationTitle("ROOT TITLE")
            }
            .navigationDestination(for: String.self) { value in
                Text("VALUE \(value)")
                    .navigationTitle("VALUE TITLE")
            }

            let rootNode = makeNode(stack)

            rootNode.children[1].children[0].onActivate?()

            XCTAssertEqual(path.count, 1)

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("VALUE TITLE"))
            XCTAssertEqual(detailNode.children[1].text, "VALUE detail")

            detailNode.children[0].children[0].onActivate?()

            XCTAssertTrue(path.isEmpty)

            let poppedNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: poppedNode.children[0]).contains("ROOT TITLE"))
            XCTAssertTrue(allTexts(in: poppedNode.children[1]).contains("OPEN"))
        }
    }

    func testNavigationStackInitialPathBindingRendersResolvedDestination() async {
        await MainActor.run {
            var path = ["detail"]
            let stack = NavigationStack(
                path: Binding(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                Text("ROOT")
                    .navigationTitle("ROOT TITLE")
            }
            .navigationDestination(for: String.self) { value in
                Text("VALUE \(value)")
                    .navigationTitle("VALUE TITLE")
            }

            let node = makeNode(stack)

            XCTAssertTrue(allTexts(in: node.children[0]).contains("VALUE TITLE"))
            XCTAssertEqual(node.children[1].text, "VALUE detail")
        }
    }

    func testNavigationStackInitialPathBindingResolvesNestedDestinations() async {
        await MainActor.run {
            var path = NavigationPath()
            path.appendAnyHashable(AnyHashable("detail"))
            path.appendAnyHashable(AnyHashable(7))
            let stack = NavigationStack(
                path: Binding(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                Text("ROOT")
                    .navigationTitle("ROOT TITLE")
            }
            .navigationDestination(for: String.self) { value in
                VStack {
                    Text("VALUE \(value)")
                    NavigationLink("COUNT", value: 9)
                }
                .navigationTitle("VALUE TITLE")
                .navigationDestination(for: Int.self) { count in
                    Text("COUNT \(count)")
                        .navigationTitle("COUNT TITLE")
                }
            }

            let node = makeNode(stack)

            XCTAssertTrue(allTexts(in: node.children[0]).contains("COUNT TITLE"))
            XCTAssertEqual(node.children[1].text, "COUNT 7")
        }
    }

    func testNavigationStackPathBindingAppendsNestedValueDestinations() async {
        await MainActor.run {
            var path = NavigationPath()
            path.appendAnyHashable(AnyHashable("detail"))
            let stack = NavigationStack(
                path: Binding(
                    get: { path },
                    set: { path = $0 }
                )
            ) {
                Text("ROOT")
                    .navigationTitle("ROOT TITLE")
            }
            .navigationDestination(for: String.self) { value in
                VStack {
                    Text("VALUE \(value)")
                    NavigationLink("COUNT", value: 9)
                }
                .navigationTitle("VALUE TITLE")
                .navigationDestination(for: Int.self) { count in
                    Text("COUNT \(count)")
                        .navigationTitle("COUNT TITLE")
                }
            }

            let detailNode = makeNode(stack)

            XCTAssertEqual(path.count, 1)
            XCTAssertTrue(allTexts(in: detailNode.children[1]).contains("COUNT"))

            detailNode.children[1].children[1].onActivate?()

            XCTAssertEqual(path.count, 2)

            let countNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: countNode.children[0]).contains("COUNT TITLE"))
            XCTAssertEqual(countNode.children[1].text, "COUNT 9")
        }
    }

    func testNavigationDestinationModifiersPreserveRootContent() async {
        await MainActor.run {
            let item: NavigationDestinationItem? = nil
            let node = makeNode(
                NavigationStack {
                    NavigationLink("OPEN", value: "detail")
                }
                .navigationDestination(for: String.self) { value in
                    Text(value)
                }
                .navigationDestination(isPresented: Binding.constant(false)) {
                    Text("PRESENTED")
                }
                .navigationDestination(item: Binding.constant(item)) { selectedItem in
                    Text(selectedItem.id)
                }
            )

            XCTAssertTrue(allTexts(in: node).contains("OPEN"))
        }
    }

    func testNavigationDestinationIsPresentedShowsAndDismissesRetainedDestination() async {
        await MainActor.run {
            var isPresented = true
            let stack = NavigationStack {
                Text("ROOT")
                    .navigationTitle("ROOT TITLE")
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { isPresented },
                    set: { isPresented = $0 }
                )
            ) {
                Text("PRESENTED")
                    .navigationTitle("PRESENTED TITLE")
            }

            let presentedNode = makeNode(stack)

            XCTAssertTrue(allTexts(in: presentedNode.children[0]).contains("PRESENTED TITLE"))
            XCTAssertEqual(presentedNode.children[1].text, "PRESENTED")

            presentedNode.children[0].children[0].onActivate?()

            XCTAssertFalse(isPresented)

            let rootNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: rootNode.children[0]).contains("ROOT TITLE"))
            XCTAssertEqual(rootNode.children[1].text, "ROOT")
        }
    }

    func testNavigationDestinationItemShowsAndClearsRetainedDestination() async {
        await MainActor.run {
            var selectedItem: NavigationDestinationItem? = NavigationDestinationItem(id: "selected")
            let stack = NavigationStack {
                Text("ROOT")
                    .navigationTitle("ROOT TITLE")
            }
            .navigationDestination(
                item: Binding(
                    get: { selectedItem },
                    set: { selectedItem = $0 }
                )
            ) { item in
                Text("ITEM \(item.id)")
                    .navigationTitle("ITEM TITLE")
            }

            let itemNode = makeNode(stack)

            XCTAssertTrue(allTexts(in: itemNode.children[0]).contains("ITEM TITLE"))
            XCTAssertEqual(itemNode.children[1].text, "ITEM selected")

            itemNode.children[0].children[0].onActivate?()

            XCTAssertNil(selectedItem)
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

    func testToggleStyleModifierMapsToRetainedToggleChrome() async {
        await MainActor.run {
            struct ToggleStyleReaderView: View {
                @Environment(\.toggleStyle) var toggleStyle

                var body: some View {
                    Text(toggleStyle == .checkbox ? "CHECKBOX" : toggleStyle == .button ? "BUTTON" : "SWITCH")
                }
            }

            let tint = Color(red: 0.25, green: 0.75, blue: 0.55, alpha: 1)
            var checkboxValue = true
            var didInvalidate = false

            let checkboxNode = makeNode(
                Toggle(
                    "ENABLED",
                    isOn: Binding(
                        get: { checkboxValue },
                        set: { checkboxValue = $0 }
                    )
                )
                .toggleStyle(.checkbox)
                .tint(tint),
                onInvalidate: {
                    didInvalidate = true
                }
            )
            let buttonNode = makeNode(
                Toggle("FILTER", isOn: .constant(true))
                    .toggleStyle(.button)
                    .tint(tint)
            )
            let inheritedNode = makeNode(
                VStack {
                    Toggle("FIRST", isOn: .constant(false))
                    Toggle("SECOND", isOn: .constant(true))
                }
                .toggleStyle(.button)
            )
            let readerNode = makeNode(ToggleStyleReaderView().toggleStyle(.checkbox))

            XCTAssertTrue(checkboxNode.isFocusable)
            XCTAssertEqual(checkboxNode.children[0].cornerRadius, 4)
            XCTAssertEqual(checkboxNode.children[0].backgroundColor, tint)
            XCTAssertTrue(allTexts(in: checkboxNode).contains("ENABLED"))

            checkboxNode.onActivate?()

            XCTAssertFalse(checkboxValue)
            XCTAssertTrue(didInvalidate)
            XCTAssertEqual(buttonNode.backgroundColor, tint.opacity(0.82))
            XCTAssertTrue(buttonNode.isFocusable)
            XCTAssertTrue(inheritedNode.children[0].isFocusable)
            XCTAssertTrue(inheritedNode.children[1].isFocusable)
            XCTAssertEqual(readerNode.text, "CHECKBOX")
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

    func testLabelsHiddenSuppressesControlLabels() async {
        await MainActor.run {
            let toggleNode = makeNode(
                Toggle("ENABLED", isOn: .constant(true))
                    .labelsHidden()
            )
            let pickerNode = makeNode(
                Picker("MODE", selection: .constant("compact")) {
                    Text("COMPACT").tag("compact")
                    Text("EXPANDED").tag("expanded")
                }
                .labelsHidden()
            )
            let stepperNode = makeNode(
                Stepper("VALUE", value: .constant(2), in: 0...10)
                    .labelsHidden()
            )
            let sliderNode = makeNode(
                Slider(
                    value: .constant(0.5),
                    in: 0...1,
                    minimumValueLabel: Text("LOW"),
                    maximumValueLabel: Text("HIGH")
                ) {
                    Text("GAIN")
                }
                .labelsHidden()
            )
            let progressNode = makeNode(
                ProgressView(value: 0.5, total: 1.0) {
                    Text("DOWNLOAD")
                } currentValueLabel: {
                    Text("50%")
                }
                .labelsHidden()
            )

            XCTAssertFalse(allTexts(in: toggleNode).contains("ENABLED"))
            XCTAssertNotNil(firstFocusable(in: toggleNode))

            XCTAssertFalse(allTexts(in: pickerNode).contains("MODE"))
            XCTAssertTrue(allTexts(in: pickerNode).contains("COMPACT"))

            XCTAssertEqual(stepperNode.children.count, 2)
            XCTAssertFalse(allTexts(in: stepperNode).contains("VALUE"))

            XCTAssertFalse(sliderNode.children.isEmpty)
            XCTAssertTrue(allTexts(in: sliderNode).isEmpty)

            XCTAssertFalse(progressNode.children.isEmpty)
            XCTAssertTrue(allTexts(in: progressNode).isEmpty)
        }
    }

    func testControlSizeModifierScalesRetainedControlSurfaces() async {
        await MainActor.run {
            let textFieldNode = makeNode(
                TextField("NAME", text: .constant(""))
                    .controlSize(.small)
            )
            let textEditorNode = makeNode(
                TextEditor(text: .constant(""))
                    .controlSize(.large)
            )
            let toggleNode = makeNode(
                Toggle("ENABLED", isOn: .constant(true))
                    .controlSize(.large)
            )
            let pickerNode = makeNode(
                Picker("MODE", selection: .constant("compact")) {
                    Text("COMPACT").tag("compact")
                    Text("EXPANDED").tag("expanded")
                }
                .pickerStyle(.menu)
                .controlSize(.large)
            )
            let stepperNode = makeNode(
                Stepper("VALUE", value: .constant(2), in: 0...10)
                    .controlSize(.small)
            )
            let sliderNode = makeNode(
                Slider(value: .constant(0.5), in: 0...1)
                    .controlSize(.large)
            )
            let progressNode = makeNode(
                ProgressView(value: 0.5, total: 1.0)
                    .controlSize(.extraLarge)
            )

            XCTAssertEqual(textFieldNode.preferredSize, Size(width: 200, height: 32))
            XCTAssertEqual(textEditorNode.preferredSize, Size(width: 300, height: 144))
            XCTAssertEqual(toggleNode.children[1].preferredSize, Size(width: 60, height: 38))
            XCTAssertEqual(pickerNode.children[1].preferredSize, Size(width: 232, height: 44))
            XCTAssertEqual(stepperNode.children[1].preferredSize, Size(width: 30, height: 26))
            XCTAssertEqual(stepperNode.children[2].preferredSize, Size(width: 30, height: 26))
            XCTAssertEqual(sliderNode.preferredSize, Size(width: 240, height: 34))
            XCTAssertEqual(progressNode.preferredSize, Size(width: 280, height: 12))
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

    func testStepperActionInitializersRunHandlersAndDisableMissingDirections() async {
        await MainActor.run {
            var increments = 0
            var decrements = 0
            var didInvalidate = false
            var editingChanges: [Bool] = []

            let source = "PREFIX-ACTIONS"
            let title = source.dropFirst(7)
            let node = makeNode(
                Stepper(
                    title,
                    onIncrement: {
                        increments += 1
                    },
                    onDecrement: nil,
                    onEditingChanged: { isEditing in
                        editingChanges.append(isEditing)
                    }
                ),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(firstText(in: node.children[0]), "ACTIONS")
            XCTAssertFalse(node.children[1].isFocusable)
            XCTAssertTrue(node.children[2].isFocusable)

            node.children[1].onActivate?()
            XCTAssertEqual(decrements, 0)

            node.children[2].onActivate?()
            XCTAssertEqual(increments, 1)
            XCTAssertTrue(didInvalidate)
            XCTAssertEqual(editingChanges, [true, false])

            let builderNode = makeNode(
                Stepper(
                    onIncrement: nil,
                    onDecrement: {
                        decrements += 1
                    }
                ) {
                    Label("BUILDER", systemImage: "minus")
                }
            )

            XCTAssertTrue(allTexts(in: builderNode.children[0]).contains("BUILDER"))
            XCTAssertTrue(builderNode.children[1].isFocusable)
            XCTAssertFalse(builderNode.children[2].isFocusable)

            builderNode.children[1].onActivate?()
            XCTAssertEqual(decrements, 1)
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

    func testOptionalTintModifierMapsToTintOrDefault() async {
        await MainActor.run {
            let parentAccent = Color(red: 0.1, green: 0.8, blue: 0.3, alpha: 1)
            let optionalTint: Color? = Color(red: 0.9, green: 0.2, blue: 0.5, alpha: 1)
            let nilTint: Color? = nil

            let node = makeNode(
                VStack {
                    ProgressView(value: 0.25, total: 1.0)
                    ProgressView(value: 0.5, total: 1.0)
                        .tint(optionalTint)
                    ProgressView(value: 0.75, total: 1.0)
                        .tint(nilTint)
                }
                .accentColor(parentAccent)
            )

            XCTAssertEqual(node.children[0].children[1].backgroundColor, parentAccent)
            XCTAssertEqual(node.children[1].children[1].backgroundColor, optionalTint)
            XCTAssertEqual(node.children[2].children[1].backgroundColor, ViewBuildContext.defaultTint)
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

    func testAccessibilityModifiersMapToRetainedMetadata() async {
        await MainActor.run {
            let node = makeNode(
                Text("SAVE")
                    .accessibilityLabel(Text("Save changes"))
                    .accessibilityValue(LocalizedStringKey("Ready"))
                    .accessibilityHint("Writes the current document")
                    .accessibilityIdentifier("save-button")
                    .accessibilityHidden(true)
            )

            XCTAssertEqual(node.accessibilityLabel, "Save changes")
            XCTAssertEqual(node.accessibilityValue, "Ready")
            XCTAssertEqual(node.accessibilityHint, "Writes the current document")
            XCTAssertEqual(node.accessibilityIdentifier, "save-button")
            XCTAssertTrue(node.isAccessibilityHidden)
        }
    }

    func testHelpModifierMapsToRetainedAccessibilityHint() async {
        await MainActor.run {
            let stringNode = makeNode(Text("SAVE").help("Writes changes"))
            let keyNode = makeNode(Text("OPEN").help(LocalizedStringKey("Opens a file")))
            let textNode = makeNode(Text("CLOSE").help(Text("Closes the window")))

            XCTAssertEqual(stringNode.accessibilityHint, "Writes changes")
            XCTAssertEqual(keyNode.accessibilityHint, "Opens a file")
            XCTAssertEqual(textNode.accessibilityHint, "Closes the window")
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

    func testCustomEnvironmentKeysPropagateThroughViewContext() async {
        await MainActor.run {
            struct CustomEnvironmentReaderView: View {
                @Environment(\.testEnvironmentLabel) var label

                var body: some View {
                    Text(label)
                }
            }

            let defaultNode = makeNode(CustomEnvironmentReaderView())
            let overriddenNode = makeNode(
                VStack {
                    CustomEnvironmentReaderView()
                }
                .environment(\.testEnvironmentLabel, "OVERRIDE")
            )
            let nestedOverrideNode = makeNode(
                VStack {
                    CustomEnvironmentReaderView()
                    CustomEnvironmentReaderView()
                        .environment(\.testEnvironmentLabel, "INNER")
                }
                .environment(\.testEnvironmentLabel, "OUTER")
            )

            XCTAssertEqual(defaultNode.text, "DEFAULT")
            XCTAssertEqual(overriddenNode.children[0].text, "OVERRIDE")
            XCTAssertEqual(nestedOverrideNode.children[0].text, "OUTER")
            XCTAssertEqual(nestedOverrideNode.children[1].text, "INNER")
        }
    }

    func testTintAndControlSizeBridgeThroughEnvironmentValues() async {
        await MainActor.run {
            struct InheritedControlEnvironmentReaderView: View {
                @Environment(\.tint) var tint
                @Environment(\.controlSize) var controlSize

                var body: some View {
                    Text(
                        "\(tint == Color.red ? "RED" : "DEFAULT") "
                            + "\(controlSize == .large ? "LARGE" : controlSize == .small ? "SMALL" : "REGULAR")"
                    )
                }
            }

            let modifierNode = makeNode(
                InheritedControlEnvironmentReaderView()
                    .tint(.red)
                    .controlSize(.large)
            )
            let environmentNode = makeNode(
                InheritedControlEnvironmentReaderView()
                    .environment(\.tint, Color.red)
                    .environment(\.controlSize, .small)
            )
            let progressNode = makeNode(
                ProgressView(value: 0.5, total: 1.0)
                    .environment(\.tint, Color.red)
            )
            let toggleNode = makeNode(
                Toggle("ENABLED", isOn: .constant(true))
                    .environment(\.controlSize, .large)
            )

            XCTAssertEqual(modifierNode.text, "RED LARGE")
            XCTAssertEqual(environmentNode.text, "RED SMALL")
            XCTAssertEqual(progressNode.children[1].backgroundColor, Color.red)
            XCTAssertEqual(toggleNode.children[1].preferredSize, Size(width: 60, height: 38))
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

    func testOnHoverModifierEnablesHitTestingAndReportsPointerTransitions() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var hoverStates: [Bool] = []

            let node = Text("HOVER")
                .frame(width: 80, height: 24)
                .onHover { isHovered in
                    hoverStates.append(isHovered)
                }
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()

            XCTAssertTrue(node.isHitTestVisible)

            runtime.pointerMoved(to: Point(x: 10, y: 10))
            runtime.pointerMoved(to: Point(x: 12, y: 12))
            runtime.pointerMoved(to: Point(x: 120, y: 50))
            runtime.pointerExitedWindow()

            XCTAssertEqual(hoverStates, [true, false])
        }
    }

    func testOnHoverModifierPreservesExistingPointerHandlers() async {
        await MainActor.run {
            var hoverStates: [Bool] = []
            var enterCount = 0
            var exitCount = 0

            let node = makeNode(
                PointerHandlerProbe(
                    onEnter: {
                        enterCount += 1
                    },
                    onExit: {
                        exitCount += 1
                    }
                )
                    .onHover { isHovered in
                        hoverStates.append(isHovered)
                    }
            )

            node.onPointerEnter?()
            node.onPointerExit?()

            XCTAssertEqual(enterCount, 1)
            XCTAssertEqual(exitCount, 1)
            XCTAssertEqual(hoverStates, [true, false])
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

    func testOnTapGestureCountRequiresConsecutiveInsideTaps() async {
        await MainActor.run {
            var tapCount = 0
            let node = makeNode(
                Text("TAP")
                    .onTapGesture(count: 2) {
                        tapCount += 1
                    }
            )

            XCTAssertTrue(node.isHitTestVisible)

            node.onPointerUpInside?()
            XCTAssertEqual(tapCount, 0)

            node.onPointerUpOutside?()
            node.onPointerUpInside?()
            XCTAssertEqual(tapCount, 0)

            node.onPointerUpInside?()
            XCTAssertEqual(tapCount, 1)

            node.onPointerUpInside?()
            node.onPointerUpInside?()
            XCTAssertEqual(tapCount, 2)
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

    func testOnTapGestureCountPreservesExistingPointerUpHandlers() async {
        await MainActor.run {
            var insideCount = 0
            var outsideCount = 0
            var tapCount = 0
            let node = makeNode(
                PointerHandlerProbe(
                    onUpInside: {
                        insideCount += 1
                    },
                    onUpOutside: {
                        outsideCount += 1
                    }
                )
                .onTapGesture(count: 3) {
                    tapCount += 1
                }
            )

            node.onPointerUpInside?()
            node.onPointerUpOutside?()
            node.onPointerUpInside?()
            node.onPointerUpInside?()
            node.onPointerUpInside?()

            XCTAssertEqual(insideCount, 4)
            XCTAssertEqual(outsideCount, 1)
            XCTAssertEqual(tapCount, 1)
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

private func twoPixelBGRA32BMPData() -> Data {
    Data([
        0x42, 0x4D,
        0x3E, 0x00, 0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x36, 0x00, 0x00, 0x00,
        0x28, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x00,
        0x01, 0x00,
        0x20, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xFF, 0xFF,
        0x00, 0xFF, 0x00, 0xFF
    ])
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
