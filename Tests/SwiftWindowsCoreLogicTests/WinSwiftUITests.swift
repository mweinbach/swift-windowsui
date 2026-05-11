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

private actor AsyncTaskCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private struct EmphasisModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(.red)
            .font(.system(size: 1.7, weight: .bold))
    }
}

private struct IdentityModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
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

    func testTextConcatenationFlattensIntoRetainedLabel() async {
        await MainActor.run {
            let inheritedColor = Color(red: 0.4, green: 0.8, blue: 0.9, alpha: 1)
            let leftColor = Color(red: 0.9, green: 0.2, blue: 0.3, alpha: 1)
            let rightColor = Color(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)
            let combinedNode = makeNode(
                (
                    Text("HELLO ")
                        .foregroundColor(leftColor)
                        .font(.system(size: 18, weight: .bold))
                        .underline()
                    + Text("WORLD")
                        .foregroundColor(rightColor)
                        .font(.system(size: 12, weight: .regular))
                        .strikethrough()
                )
            )
            let rightStyledNode = makeNode(
                Text("PLAIN ") + Text("RIGHT").foregroundColor(rightColor)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("A") + Text("B")
                }
                .foregroundColor(inheritedColor)
            )

            XCTAssertEqual(combinedNode.text, "HELLO WORLD")
            XCTAssertEqual(combinedNode.textStyle.color, leftColor)
            XCTAssertEqual(combinedNode.textStyle.nativeFontSize, 18)
            XCTAssertEqual(combinedNode.textStyle.weight, .bold)
            XCTAssertTrue(combinedNode.textStyle.underline)
            XCTAssertTrue(combinedNode.textStyle.strikethrough)
            XCTAssertEqual(rightStyledNode.text, "PLAIN RIGHT")
            XCTAssertEqual(rightStyledNode.textStyle.color, rightColor)
            XCTAssertEqual(inheritedNode.children[0].text, "AB")
            XCTAssertEqual(inheritedNode.children[0].textStyle.color, inheritedColor)
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
                    Menu(title, systemImage: "ellipsis.circle") {
                        Button(title) {}
                    }
                    ControlGroup(title) {
                        Button(title) {}
                    }
                    Toggle(title, isOn: .constant(true))
                    ProgressView(title, value: 0.5, total: 1.0)
                    Button(title) {}
                    Button(title, systemImage: "doc.text") {}
                    Button(title, role: .cancel) {}
                    Button(title, systemImage: "trash", role: .destructive) {}
                    LabeledContent(title, value: "READY")
                }
            )

            XCTAssertGreaterThanOrEqual(allTexts(in: node).filter { $0 == "SAVE" }.count, 13)
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

    func testSearchableAddsSearchFieldAndDismissSearchEnvironment() async {
        await MainActor.run {
            struct SearchEnvironmentReader: View {
                @Environment(\.isSearching) var isSearching
                @Environment(\.dismissSearch) var dismissSearch

                var body: some View {
                    Button(isSearching ? "SEARCHING" : "IDLE") {
                        dismissSearch()
                    }
                }
            }

            var query = "needle"
            var invalidationCount = 0
            let binding = Binding(
                get: { query },
                set: { query = $0 }
            )

            let node = makeNode(
                SearchEnvironmentReader()
                    .searchable(text: binding, placement: .toolbar, prompt: "Find"),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].children[0].text, "needle")
            XCTAssertTrue(allTexts(in: node.children[1]).contains("SEARCHING"))

            node.children[1].onActivate?()

            XCTAssertEqual(query, "")
            XCTAssertEqual(invalidationCount, 2)

            let updatedNode = makeNode(
                SearchEnvironmentReader()
                    .searchable(text: binding, prompt: LocalizedStringKey("Find"))
            )

            XCTAssertEqual(updatedNode.children[0].children[0].text, "Find")
            XCTAssertTrue(allTexts(in: updatedNode.children[1]).contains("IDLE"))
        }
    }

    func testSearchableIsPresentedBindingControlsSearchFieldVisibility() async {
        await MainActor.run {
            struct SearchPresentedReader: View {
                @Environment(\.isSearching) var isSearching

                var body: some View {
                    Text(isSearching ? "SEARCHING" : "IDLE")
                }
            }

            var query = "needle"
            var isPresented = false
            let queryBinding = Binding(
                get: { query },
                set: { query = $0 }
            )
            let presentedBinding = Binding(
                get: { isPresented },
                set: { isPresented = $0 }
            )

            let hiddenNode = makeNode(
                SearchPresentedReader()
                    .searchable(
                        text: queryBinding,
                        isPresented: presentedBinding,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Find")
                    )
            )

            XCTAssertEqual(hiddenNode.children.count, 1)
            XCTAssertFalse(allTexts(in: hiddenNode).contains("needle"))
            XCTAssertTrue(allTexts(in: hiddenNode.children[0]).contains("IDLE"))

            isPresented = true

            let visibleNode = makeNode(
                SearchPresentedReader()
                    .searchable(
                        text: queryBinding,
                        isPresented: presentedBinding,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Find")
                    )
            )

            XCTAssertEqual(visibleNode.children.count, 2)
            XCTAssertEqual(visibleNode.children[0].children[0].text, "needle")
            XCTAssertTrue(allTexts(in: visibleNode.children[1]).contains("SEARCHING"))
            XCTAssertEqual(
                SearchFieldPlacement.navigationBarDrawer(displayMode: .always),
                SearchFieldPlacement.navigationBarDrawer(displayMode: .always)
            )
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

    func testShapeStrokeStyleOverloadsMapToRetainedBorders() async {
        await MainActor.run {
            let inheritedColor = Color(red: 0.7, green: 0.4, blue: 0.9, alpha: 1)
            let storedStroke = Color(red: 0.1, green: 0.8, blue: 0.5, alpha: 1)
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.9, green: 0.1, blue: 0.3, alpha: 1),
                    Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            let strokeStyle = StrokeStyle(
                lineWidth: 6,
                lineCap: .round,
                lineJoin: .bevel,
                miterLimit: 3,
                dash: [4, 2],
                dashPhase: 1
            )
            let root = renderedNode(
                VStack {
                    Rectangle()
                        .stroke(style: strokeStyle)
                        .frame(width: 24, height: 12)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ForegroundStyle.color(storedStroke), style: StrokeStyle(lineWidth: 3, dash: [2]))
                        .frame(width: 28, height: 16)
                    Circle()
                        .stroke(gradient, style: StrokeStyle(lineWidth: 4, lineCap: .square))
                        .frame(width: 20, height: 20)
                    Ellipse()
                        .strokeBorder(ForegroundStyle.linearGradient(gradient), lineWidth: 5)
                        .frame(width: 32, height: 14)
                }
                .foregroundStyle(inheritedColor)
            )

            let inheritedStroke = root.children[0].children[0]
            let storedForegroundStroke = root.children[1].children[0]
            let gradientStroke = root.children[2].children[0]
            let gradientStrokeBorder = root.children[3].children[0]
            XCTAssertEqual(strokeStyle.lineWidth, 6)
            XCTAssertEqual(strokeStyle.dashPattern, [4, 2])
            XCTAssertEqual(strokeStyle.dashOffset, 1)
            XCTAssertEqual(strokeStyle.lineCap, .round)
            XCTAssertEqual(strokeStyle.lineJoin, .bevel)
            XCTAssertEqual(inheritedStroke.backgroundColor, .clear)
            XCTAssertEqual(inheritedStroke.borderColor, inheritedColor)
            XCTAssertEqual(inheritedStroke.borderWidth, 6)
            XCTAssertEqual(storedForegroundStroke.backgroundColor, .clear)
            XCTAssertEqual(storedForegroundStroke.borderColor, storedStroke)
            XCTAssertEqual(storedForegroundStroke.borderWidth, 3)
            XCTAssertEqual(storedForegroundStroke.cornerRadius, 8)
            XCTAssertEqual(gradientStroke.backgroundColor, .clear)
            XCTAssertEqual(gradientStroke.borderColor, gradient.startColor)
            XCTAssertEqual(gradientStroke.borderWidth, 4)
            XCTAssertEqual(gradientStroke.cornerRadius, 10)
            XCTAssertEqual(gradientStrokeBorder.borderColor, gradient.startColor)
            XCTAssertEqual(gradientStrokeBorder.borderWidth, 5)
            XCTAssertEqual(gradientStrokeBorder.cornerRadius, 7)
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

    func testCircleMapsToDynamicRoundedRetainedShapeNode() async {
        await MainActor.run {
            let fillColor = Color(red: 0.2, green: 0.7, blue: 0.9, alpha: 1)
            let strokeColor = Color(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.2, blue: 0.9, alpha: 1),
                    Color(red: 0.8, green: 0.1, blue: 0.7, alpha: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            let root = renderedNode(
                VStack {
                    Circle()
                        .fill(fillColor)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(strokeColor, lineWidth: 2)
                        .frame(width: 30, height: 30)
                    Circle()
                        .fill(gradient)
                        .frame(width: 28, height: 28)
                }
            )

            let filledCircle = root.children[0].children[0]
            let strokedCircle = root.children[1].children[0]
            let gradientCircle = root.children[2].children[0]
            XCTAssertEqual(filledCircle.backgroundColor, fillColor)
            XCTAssertEqual(filledCircle.cornerRadius, 12)
            XCTAssertEqual(strokedCircle.backgroundColor, .clear)
            XCTAssertEqual(strokedCircle.borderColor, strokeColor)
            XCTAssertEqual(strokedCircle.borderWidth, 2)
            XCTAssertEqual(strokedCircle.cornerRadius, 15)
            XCTAssertEqual(gradientCircle.backgroundColor, gradient.startColor)
            XCTAssertEqual(gradientCircle.backgroundGradient, gradient)
            XCTAssertEqual(gradientCircle.cornerRadius, 14)
        }
    }

    func testEllipseMapsToDynamicRoundedRetainedShapeFallback() async {
        await MainActor.run {
            let fillColor = Color(red: 0.6, green: 0.8, blue: 0.2, alpha: 1)
            let strokeColor = Color(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
            let root = renderedNode(
                VStack {
                    Ellipse()
                        .fill(fillColor)
                        .frame(width: 48, height: 20)
                    Ellipse()
                        .stroke(strokeColor, lineWidth: 3)
                        .frame(width: 64, height: 24)
                }
            )

            let filledEllipse = root.children[0].children[0]
            let strokedEllipse = root.children[1].children[0]
            XCTAssertEqual(filledEllipse.backgroundColor, fillColor)
            XCTAssertEqual(filledEllipse.cornerRadius, 10)
            XCTAssertEqual(strokedEllipse.backgroundColor, .clear)
            XCTAssertEqual(strokedEllipse.borderColor, strokeColor)
            XCTAssertEqual(strokedEllipse.borderWidth, 3)
            XCTAssertEqual(strokedEllipse.cornerRadius, 12)
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

    @MainActor
    private static func assertNativeFontSize(_ node: ViewNode, _ expectedSize: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let nativeFontSize = node.textStyle.nativeFontSize else {
            XCTFail("Expected native font size", file: file, line: line)
            return
        }

        XCTAssertEqual(nativeFontSize, expectedSize, accuracy: 0.001, file: file, line: line)
    }

    func testDynamicTypeSizeScalesRetainedTextAndInputs() async {
        await MainActor.run {
            struct DynamicTypeReaderView: View {
                @Environment(\.dynamicTypeSize) var dynamicTypeSize

                var body: some View {
                    Text(dynamicTypeSize.isAccessibilitySize ? "ACCESS" : "REGULAR")
                }
            }

            let defaultNode = makeNode(
                Text("DEFAULT")
                    .font(.system(size: 10))
            )
            let explicitNode = makeNode(
                Text("EXPLICIT")
                    .font(.system(size: 10))
                    .dynamicTypeSize(.xxLarge)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                }
                .font(.system(size: 10))
                .dynamicTypeSize(.xxLarge)
            )
            let inputNode = makeNode(
                TextField("NAME", text: .constant(""))
                    .font(.system(size: 10))
                    .dynamicTypeSize(.xxxLarge)
            )
            let readerNode = makeNode(
                DynamicTypeReaderView()
                    .dynamicTypeSize(.accessibility1)
            )

            Self.assertNativeFontSize(defaultNode, 10)
            Self.assertNativeFontSize(explicitNode, 12.4)
            Self.assertNativeFontSize(inheritedNode.children[0], 12.4)
            Self.assertNativeFontSize(inputNode.children[0], 13.6)
            XCTAssertEqual(readerNode.text, "ACCESS")
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
                @Environment(\.legibilityWeight) var legibilityWeight

                var body: some View {
                    Text(
                        alignment == .trailing
                            && lineLimit == 2
                            && truncationMode == .middle
                            && allowsTightening
                            && textCase == .uppercase
                            && legibilityWeight == .bold
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
                    .environment(\.legibilityWeight, .bold)
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
            let legibilityNode = makeNode(
                VStack {
                    Text("BOLD")
                    Text("REGULAR")
                        .fontWeight(.regular)
                }
                .legibilityWeight(.bold)
            )
            let readerNode = makeNode(
                TextEnvironmentReaderView()
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .allowsTightening(true)
                    .textCase(.uppercase)
                    .legibilityWeight(.bold)
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
            XCTAssertEqual(legibilityNode.children[0].textStyle.weight, .bold)
            XCTAssertEqual(legibilityNode.children[1].textStyle.weight, .regular)
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
            struct ContrastEnvironmentReaderView: View {
                @Environment(\.colorSchemeContrast) var colorSchemeContrast

                var body: some View {
                    Text(colorSchemeContrast == .increased ? "INCREASED" : "STANDARD")
                }
            }

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
            let increasedSecondaryNode = makeNode(
                Text("SECONDARY")
                    .foregroundStyle(.secondary)
                    .environment(\.colorSchemeContrast, .increased)
            )
            let explicitSecondaryNode = makeNode(
                Text("EXPLICIT")
                    .foregroundColor(.secondary)
                    .environment(\.colorSchemeContrast, .increased)
            )
            let readerNode = makeNode(
                ContrastEnvironmentReaderView()
                    .environment(\.colorSchemeContrast, .increased)
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
            XCTAssertEqual(increasedSecondaryNode.textStyle.color, .highContrastSecondary)
            XCTAssertEqual(explicitSecondaryNode.textStyle.color, .highContrastSecondary)
            XCTAssertEqual(readerNode.text, "INCREASED")
            XCTAssertEqual(gradientNode.textStyle.color, gradient.startColor)
        }
    }

    func testCustomViewModifierMapsThroughRetainedComponentPipeline() async {
        await MainActor.run {
            let node = makeNode(
                Text("ALERT")
                    .modifier(EmphasisModifier())
            )

            XCTAssertEqual(node.text, "ALERT")
            XCTAssertEqual(node.textStyle.color, .red)
            XCTAssertEqual(node.textStyle.weight, .bold)
        }
    }

    func testForegroundStyleMultiArgumentOverloadsUsePrimaryStyle() async {
        await MainActor.run {
            let primaryColor = Color(red: 0.6, green: 0.2, blue: 0.9, alpha: 1)
            let storedPrimary = ForegroundStyle.color(Color(red: 0.1, green: 0.7, blue: 0.4, alpha: 1))
            let primaryGradient = LinearGradient(
                colors: [.red, .blue],
                startPoint: .top,
                endPoint: .bottom
            )
            let secondaryGradient = LinearGradient(
                colors: [.green, .yellow],
                startPoint: .leading,
                endPoint: .trailing
            )
            let colorNode = makeNode(
                Text("COLOR")
                    .foregroundStyle(primaryColor, .secondary)
            )
            let tertiaryColorNode = makeNode(
                Text("TERTIARY")
                    .foregroundStyle(primaryColor, .red, .blue)
            )
            let storedNode = makeNode(
                Text("STORED")
                    .foregroundStyle(storedPrimary, .color(.secondary))
            )
            let gradientNode = makeNode(
                Rectangle()
                    .foregroundStyle(primaryGradient, secondaryGradient)
                    .frame(width: 20, height: 10)
            )

            XCTAssertEqual(colorNode.textStyle.color, primaryColor)
            XCTAssertEqual(tertiaryColorNode.textStyle.color, primaryColor)
            XCTAssertEqual(storedNode.textStyle.color, Color(red: 0.1, green: 0.7, blue: 0.4, alpha: 1))
            XCTAssertEqual(gradientNode.children[0].backgroundColor, primaryGradient.startColor)
            XCTAssertEqual(gradientNode.children[0].backgroundGradient, primaryGradient)
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
            let defaultPaddingNode = makeNode(
                Text("DEFAULT")
                    .safeAreaPadding()
            )
            let edgePaddingNode = makeNode(
                Text("EDGE")
                    .safeAreaPadding(.horizontal, 12)
            )
            let optionalPaddingNode = makeNode(
                Text("OPTIONAL")
                    .safeAreaPadding(.vertical, nil)
            )
            let insetPaddingNode = makeNode(
                Text("INSETS")
                    .safeAreaPadding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
            )

            XCTAssertEqual(ignoredNode.text, "SAFE")
            XCTAssertEqual(legacyNode.text, "LEGACY")
            XCTAssertEqual(defaultPaddingNode.text, "DEFAULT")
            XCTAssertEqual(edgePaddingNode.text, "EDGE")
            XCTAssertEqual(optionalPaddingNode.text, "OPTIONAL")
            XCTAssertEqual(insetPaddingNode.text, "INSETS")
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

    func testOverlayStyleOverloadsFillBaseLayout() async {
        await MainActor.run {
            let color = Color(red: 0.9, green: 0.2, blue: 0.4, alpha: 0.75)
            let optionalColor: Color? = Color(red: 0.1, green: 0.6, blue: 0.8, alpha: 0.5)
            let nilColor: Color? = nil
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.4, blue: 0.9, alpha: 1),
                    Color(red: 0.8, green: 0.2, blue: 0.6, alpha: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            let colorNode = renderedNode(
                Text("BASE")
                    .frame(width: 80, height: 32)
                    .overlay(color)
            )
            let optionalNode = renderedNode(
                Text("OPTIONAL")
                    .frame(width: 72, height: 28)
                    .overlay(optionalColor, ignoresSafeAreaEdges: .vertical)
            )
            let gradientNode = renderedNode(
                Text("GRADIENT")
                    .frame(width: 90, height: 36)
                    .overlay(gradient, ignoresSafeAreaEdges: .horizontal)
            )
            let storedColorNode = renderedNode(
                Text("STORED")
                    .frame(width: 70, height: 24)
                    .overlay(ForegroundStyle.color(color), ignoresSafeAreaEdges: .bottom)
            )
            let storedGradientNode = renderedNode(
                Text("STORED GRADIENT")
                    .frame(width: 96, height: 40)
                    .overlay(ForegroundStyle.linearGradient(gradient))
            )
            let nilNode = makeNode(
                Text("PLAIN")
                    .overlay(nilColor)
            )

            XCTAssertEqual(colorNode.children[1].backgroundColor, color)
            XCTAssertEqual(colorNode.children[1].frame, Rect(x: 0, y: 0, width: 80, height: 32))
            XCTAssertEqual(optionalNode.children[1].backgroundColor, optionalColor)
            XCTAssertEqual(optionalNode.children[1].frame, Rect(x: 0, y: 0, width: 72, height: 28))
            XCTAssertEqual(gradientNode.children[1].backgroundGradient, gradient)
            XCTAssertEqual(gradientNode.children[1].frame, Rect(x: 0, y: 0, width: 90, height: 36))
            XCTAssertEqual(storedColorNode.children[1].backgroundColor, color)
            XCTAssertEqual(storedColorNode.children[1].frame, Rect(x: 0, y: 0, width: 70, height: 24))
            XCTAssertEqual(storedGradientNode.children[1].backgroundGradient, gradient)
            XCTAssertEqual(storedGradientNode.children[1].frame, Rect(x: 0, y: 0, width: 96, height: 40))
            XCTAssertEqual(nilNode.text, "PLAIN")
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
            let storedColor = Color(red: 0.4, green: 0.7, blue: 0.3, alpha: 1)
            let nilColor: Color? = nil
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.6, blue: 0.9, alpha: 1),
                    Color(red: 0.8, green: 0.2, blue: 0.5, alpha: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            let optionalNode = makeNode(
                Text("OPTIONAL")
                    .background(optionalColor, ignoresSafeAreaEdges: .top)
            )
            let concreteNode = makeNode(
                Text("CONCRETE")
                    .background(Color(red: 0.7, green: 0.2, blue: 0.4, alpha: 1), ignoresSafeAreaEdges: .all)
            )
            let gradientNode = makeNode(
                Text("GRADIENT")
                    .background(gradient, ignoresSafeAreaEdges: .horizontal)
            )
            let storedColorNode = makeNode(
                Text("STORED")
                    .background(ForegroundStyle.color(storedColor), ignoresSafeAreaEdges: .bottom)
            )
            let storedGradientNode = makeNode(
                Text("STORED GRADIENT")
                    .background(ForegroundStyle.linearGradient(gradient))
            )
            let nilNode = makeNode(
                Text("PLAIN")
                    .background(nilColor)
            )

            XCTAssertEqual(optionalNode.backgroundColor, optionalColor)
            XCTAssertEqual(firstText(in: optionalNode.children[0]), "OPTIONAL")
            XCTAssertEqual(concreteNode.children[0].text, "CONCRETE")
            XCTAssertEqual(gradientNode.backgroundGradient, gradient)
            XCTAssertEqual(firstText(in: gradientNode.children[0]), "GRADIENT")
            XCTAssertEqual(storedColorNode.backgroundColor, storedColor)
            XCTAssertEqual(firstText(in: storedColorNode.children[0]), "STORED")
            XCTAssertEqual(storedGradientNode.backgroundGradient, gradient)
            XCTAssertEqual(firstText(in: storedGradientNode.children[0]), "STORED GRADIENT")
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

    func testGridAndGridRowMapToRetainedStackPanels() async {
        await MainActor.run {
            let node = makeNode(
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                    GridRow(alignment: .bottom) {
                        Text("A1")
                        Text("A2")
                    }
                    GridRow {
                        Text("B1")
                        Text("B2")
                    }
                }
            )

            guard case .stack(let gridLayout) = node.layoutMode else {
                return XCTFail("Expected Grid to use retained vertical stack layout")
            }
            guard case .stack(let firstRowLayout) = node.children[0].layoutMode else {
                return XCTFail("Expected GridRow to use retained horizontal stack layout")
            }
            guard case .stack(let secondRowLayout) = node.children[1].layoutMode else {
                return XCTFail("Expected GridRow to use retained horizontal stack layout")
            }

            XCTAssertEqual(gridLayout, .vertical(spacing: 9, alignment: .leading))
            XCTAssertEqual(firstRowLayout, .horizontal(spacing: 12, alignment: .trailing))
            XCTAssertEqual(secondRowLayout, .horizontal(spacing: 12, alignment: .center))
            XCTAssertEqual(allTexts(in: node), ["A1", "A2", "B1", "B2"])
        }
    }

    func testStandaloneGridRowUsesDefaultRetainedHorizontalSpacing() async {
        await MainActor.run {
            let node = makeNode(
                GridRow {
                    Text("A")
                    Text("B")
                }
            )

            guard case .stack(let layout) = node.layoutMode else {
                return XCTFail("Expected GridRow to use retained horizontal stack layout")
            }

            XCTAssertEqual(layout, .horizontal(spacing: 0, alignment: .center))
            XCTAssertEqual(allTexts(in: node), ["A", "B"])
        }
    }

    func testGridCellColumnsMapsToRetainedGrowthPriority() async {
        await MainActor.run {
            let node = makeNode(
                GridRow {
                    Text("A")
                        .gridCellColumns(3)
                    Text("B")
                        .layoutPriority(5)
                        .gridCellColumns(2)
                    Text("C")
                        .gridCellColumns(0)
                }
            )

            XCTAssertEqual(node.children[0].layoutPriority, 3)
            XCTAssertEqual(node.children[1].layoutPriority, 5)
            XCTAssertEqual(node.children[2].layoutPriority, 1)
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

    func testLinkMapsToPlainRetainedButtonAndUsesOpenURLEnvironment() async {
        await MainActor.run {
            var openedURLs: [URL] = []
            var didInvalidate = false
            let docsURL = URL(string: "https://example.com/docs")!
            let statusURL = URL(string: "https://example.com/status")!
            let linkTint = Color(red: 0.1, green: 0.7, blue: 0.9, alpha: 1)
            let openURL = OpenURLAction { url in
                openedURLs.append(url)
                return .handled
            }

            let node = makeNode(
                VStack {
                    Link("DOCS", destination: docsURL)
                    Link(destination: statusURL) {
                        Label("STATUS", systemImage: "link")
                    }
                }
                .environment(\.openURL, openURL)
                .tint(linkTint),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertTrue(allTexts(in: node.children[0]).contains("DOCS"))
            XCTAssertTrue(allTexts(in: node.children[1]).contains("STATUS"))
            XCTAssertTrue(node.children[0].isFocusable)
            XCTAssertEqual(node.children[0].backgroundColor, ButtonSurfaceStyle.plain.palette.idle)
            XCTAssertEqual(firstTextNode(in: node.children[0])?.textStyle.color, linkTint)

            node.children[0].onActivate?()
            node.children[1].onActivate?()

            XCTAssertEqual(openedURLs, [docsURL, statusURL])
            XCTAssertTrue(didInvalidate)
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

    func testScrollDisabledPropagatesToRetainedScrollContainers() async {
        await MainActor.run {
            struct ScrollEnvironmentReader: View {
                @Environment(\.isScrollEnabled) var isScrollEnabled

                var body: some View {
                    Text(isScrollEnabled ? "SCROLL" : "LOCKED")
                }
            }

            let scrollViewNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .scrollDisabled()
            )
            let listNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .scrollDisabled(true)
            )
            let sectionNode = makeNode(
                Section("GROUP", style: SectionStyle(scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .scrollDisabled()
            )
            let enabledEnvironmentNode = makeNode(ScrollEnvironmentReader())
            let disabledEnvironmentNode = makeNode(ScrollEnvironmentReader().scrollDisabled())
            let enabledCallNode = makeNode(
                ScrollView {
                    Text("OPEN")
                }
                .scrollDisabled(false)
            )

            XCTAssertNil(scrollViewNode.scrollAxis)
            XCTAssertFalse(scrollViewNode.showsScrollIndicator)
            XCTAssertTrue(scrollViewNode.clipsToBounds)
            XCTAssertEqual(scrollViewNode.children[0].text, "ROW")

            XCTAssertNil(listNode.scrollAxis)
            XCTAssertFalse(listNode.showsScrollIndicator)
            XCTAssertEqual(listNode.children.count, 2)

            XCTAssertNil(sectionNode.scrollAxis)
            XCTAssertFalse(sectionNode.showsScrollIndicator)
            XCTAssertEqual(sectionNode.children[1].text, "ITEM")

            XCTAssertEqual(enabledEnvironmentNode.text, "SCROLL")
            XCTAssertEqual(disabledEnvironmentNode.text, "LOCKED")
            XCTAssertEqual(enabledCallNode.scrollAxis, .vertical)
            XCTAssertTrue(enabledCallNode.showsScrollIndicator)
        }
    }

    func testScrollIndicatorsPropagateToRetainedScrollContainers() async {
        await MainActor.run {
            struct IndicatorEnvironmentReader: View {
                @Environment(\.verticalScrollIndicatorVisibility) var vertical
                @Environment(\.horizontalScrollIndicatorVisibility) var horizontal

                var body: some View {
                    Text(vertical == .hidden && horizontal == .visible ? "CUSTOM" : "DEFAULT")
                }
            }

            let hiddenScrollViewNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .scrollIndicators(.hidden)
            )
            let visibleScrollViewNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .scrollIndicators(.visible)
            )
            let verticalOnlyNode = makeNode(
                ScrollView(.vertical) {
                    Text("ROW")
                }
                .scrollIndicators(.hidden, axes: .horizontal)
            )
            let horizontalHiddenNode = makeNode(
                ScrollView(.horizontal) {
                    Text("ROW")
                }
                .scrollIndicators(.hidden, axes: .horizontal)
            )
            let listNode = makeNode(
                List {
                    Text("ONE")
                }
                .scrollIndicators(.never)
            )
            let sectionNode = makeNode(
                Section("GROUP", style: SectionStyle(scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .scrollIndicators(.hidden)
            )
            let readerNode = makeNode(
                IndicatorEnvironmentReader()
                    .scrollIndicators(.hidden, axes: .vertical)
                    .scrollIndicators(.visible, axes: .horizontal)
            )

            XCTAssertEqual(hiddenScrollViewNode.scrollAxis, .vertical)
            XCTAssertFalse(hiddenScrollViewNode.showsScrollIndicator)
            XCTAssertTrue(visibleScrollViewNode.showsScrollIndicator)
            XCTAssertTrue(verticalOnlyNode.showsScrollIndicator)
            XCTAssertFalse(horizontalHiddenNode.showsScrollIndicator)
            XCTAssertFalse(listNode.showsScrollIndicator)
            XCTAssertFalse(sectionNode.showsScrollIndicator)
            XCTAssertEqual(readerNode.text, "CUSTOM")
        }
    }

    func testScrollClipDisabledMapsToRetainedScrollClipping() async {
        await MainActor.run {
            let scrollViewNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .scrollClipDisabled()
            )
            let explicitEnabledNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .scrollClipDisabled(false)
            )
            let listNode = makeNode(
                List {
                    Text("ONE")
                }
                .scrollClipDisabled()
            )
            let sectionNode = makeNode(
                Section("GROUP", style: SectionStyle(scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .scrollClipDisabled()
            )
            let plainSectionNode = makeNode(
                Section("GROUP") {
                    Text("ITEM")
                }
                .scrollClipDisabled()
            )

            XCTAssertFalse(scrollViewNode.clipsToBounds)
            XCTAssertEqual(scrollViewNode.scrollAxis, .vertical)
            XCTAssertTrue(explicitEnabledNode.clipsToBounds)
            XCTAssertFalse(listNode.clipsToBounds)
            XCTAssertFalse(sectionNode.clipsToBounds)
            XCTAssertTrue(plainSectionNode.clipsToBounds)
        }
    }

    func testScrollContentBackgroundVisibilityMapsToRetainedScrollChrome() async {
        await MainActor.run {
            let scrollBackground = Color(red: 0.18, green: 0.24, blue: 0.32, alpha: 0.92)
            let scrollStyle = ScrollViewStyle(backgroundColor: scrollBackground)
            let sectionGradient = LinearGradient(
                colors: [.red, .blue],
                startPoint: .top,
                endPoint: .bottom
            )
            let sectionStyle = SectionStyle(
                backgroundColor: scrollBackground,
                backgroundGradient: sectionGradient,
                scrollAxis: .vertical
            )

            let hiddenScrollViewNode = makeNode(
                ScrollView(style: scrollStyle) {
                    Text("ROW")
                }
                .scrollContentBackground(.hidden)
            )
            let visibleScrollViewNode = makeNode(
                ScrollView(style: scrollStyle) {
                    Text("ROW")
                }
                .scrollContentBackground(.visible)
            )
            let hiddenSectionNode = makeNode(
                Section("GROUP", style: sectionStyle) {
                    Text("ITEM")
                }
                .scrollContentBackground(.hidden)
            )
            let plainSectionNode = makeNode(
                Section("GROUP", style: SectionStyle(backgroundColor: scrollBackground)) {
                    Text("ITEM")
                }
                .scrollContentBackground(.hidden)
            )
            let listNode = makeNode(
                List {
                    Text("ONE")
                }
                .scrollContentBackground(.hidden)
            )

            XCTAssertNil(hiddenScrollViewNode.backgroundColor)
            XCTAssertEqual(visibleScrollViewNode.backgroundColor, scrollBackground)
            XCTAssertNil(hiddenSectionNode.backgroundColor)
            XCTAssertNil(hiddenSectionNode.backgroundGradient)
            XCTAssertEqual(hiddenSectionNode.scrollAxis, .vertical)
            XCTAssertEqual(plainSectionNode.backgroundColor, scrollBackground)
            XCTAssertEqual(listNode.scrollAxis, .vertical)
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

    func testListRowBackgroundMapsToRetainedRowBackgrounds() async {
        await MainActor.run {
            let rowColor = Color(red: 0.20, green: 0.28, blue: 0.38, alpha: 0.90)
            let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
            let listNode = makeNode(
                List {
                    Text("ONE")
                        .listRowBackground(rowColor)
                    Text("TWO")
                        .listRowBackground(gradient)
                    Text("THREE")
                        .listRowBackground(nil as Color?)
                }
            )
            let viewBackgroundNode = makeNode(
                Text("FOUR")
                    .listRowBackground(
                        Rectangle()
                            .fill(.blue)
                    )
            )

            XCTAssertEqual(listNode.children[0].backgroundColor, rowColor)
            XCTAssertEqual(listNode.children[0].children[0].text, "ONE")
            XCTAssertEqual(listNode.children[1].backgroundGradient, gradient)
            XCTAssertEqual(listNode.children[1].children[0].text, "TWO")
            XCTAssertEqual(listNode.children[2].text, "THREE")
            XCTAssertEqual(viewBackgroundNode.children.count, 2)
            XCTAssertEqual(viewBackgroundNode.children[0].backgroundColor, .blue)
            XCTAssertEqual(viewBackgroundNode.children[1].text, "FOUR")
        }
    }

    func testListRowInsetsMapToRetainedRowPadding() async {
        await MainActor.run {
            let explicitInsets = EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 8)
            let listNode = makeNode(
                List {
                    Text("ONE")
                        .listRowInsets(explicitInsets)
                    Text("TWO")
                        .listRowInsets(.horizontal, 10)
                    Text("THREE")
                        .listRowInsets(nil)
                }
            )

            guard case .stack(let explicitLayout) = listNode.children[0].layoutMode else {
                return XCTFail("Expected listRowInsets to wrap the row in a retained stack panel")
            }
            guard case .stack(let horizontalLayout) = listNode.children[1].layoutMode else {
                return XCTFail("Expected listRowInsets edge overload to wrap the row in a retained stack panel")
            }

            XCTAssertEqual(explicitLayout, .vertical(padding: explicitInsets, alignment: .stretch))
            XCTAssertEqual(listNode.children[0].children[0].text, "ONE")
            XCTAssertEqual(
                horizontalLayout,
                .vertical(padding: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10), alignment: .stretch)
            )
            XCTAssertEqual(listNode.children[1].children[0].text, "TWO")
            XCTAssertEqual(listNode.children[2].text, "THREE")
        }
    }

    func testListRowSpacingMapsToRetainedListStackSpacing() async {
        await MainActor.run {
            let spacedListNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listRowSpacing(12)
            )
            let resetListNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listRowSpacing(nil)
            )

            guard case .stack(let spacedLayout) = spacedListNode.layoutMode else {
                return XCTFail("Expected List to keep retained stack layout")
            }
            guard case .stack(let resetLayout) = resetListNode.layoutMode else {
                return XCTFail("Expected List to keep retained stack layout")
            }

            XCTAssertEqual(spacedLayout, .vertical(spacing: 12, padding: .zero, alignment: .stretch))
            XCTAssertEqual(resetLayout, .vertical(spacing: 0, padding: .zero, alignment: .stretch))
        }
    }

    func testListStyleModifierMapsToRetainedListChrome() async {
        await MainActor.run {
            let plainNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listStyle(.plain)
            )
            let insetGroupedNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listStyle(.insetGrouped)
            )
            let overriddenSpacingNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listStyle(.grouped)
                .listRowSpacing(18)
            )

            guard case .stack(let plainLayout) = plainNode.layoutMode else {
                return XCTFail("Expected plain List to keep retained stack layout")
            }
            guard case .stack(let insetGroupedLayout) = insetGroupedNode.layoutMode else {
                return XCTFail("Expected insetGrouped List to keep retained stack layout")
            }
            guard case .stack(let overriddenSpacingLayout) = overriddenSpacingNode.layoutMode else {
                return XCTFail("Expected grouped List to keep retained stack layout")
            }

            XCTAssertNil(plainNode.backgroundColor)
            XCTAssertEqual(plainNode.borderWidth, 0)
            XCTAssertEqual(plainNode.cornerRadius, 0)
            XCTAssertEqual(plainLayout, .vertical(spacing: 0, padding: .zero, alignment: .stretch))

            XCTAssertEqual(insetGroupedNode.backgroundColor, Color(red: 0.09, green: 0.12, blue: 0.18, alpha: 0.78))
            XCTAssertEqual(insetGroupedNode.borderWidth, 1)
            XCTAssertEqual(insetGroupedNode.cornerRadius, 14)
            XCTAssertEqual(
                insetGroupedLayout,
                .vertical(
                    spacing: 8,
                    padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12),
                    alignment: .stretch
                )
            )
            XCTAssertEqual(
                overriddenSpacingLayout,
                .vertical(
                    spacing: 18,
                    padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
                    alignment: .stretch
                )
            )
        }
    }

    func testListStyleEnvironmentCanBeRead() async {
        await MainActor.run {
            struct ListStyleReader: View {
                @Environment(\.listStyle) var listStyle

                var body: some View {
                    Text(listStyle == .sidebar ? "SIDEBAR" : "OTHER")
                }
            }

            let defaultNode = makeNode(ListStyleReader())
            let sidebarNode = makeNode(ListStyleReader().listStyle(.sidebar))

            XCTAssertEqual(defaultNode.text, "OTHER")
            XCTAssertEqual(sidebarNode.text, "SIDEBAR")
        }
    }

    func testDefaultMinListRowHeightMapsToRetainedRowConstraints() async {
        await MainActor.run {
            let node = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                        .frame(minHeight: 60)
                }
                .environment(\.defaultMinListRowHeight, 44)
            )

            XCTAssertEqual(node.children[0].layoutConstraints?.minHeight, 44)
            XCTAssertEqual(node.children[0].layoutConstraints?.maxHeight, .infinity)
            XCTAssertEqual(node.children[1].layoutConstraints?.minHeight, 60)
            XCTAssertEqual(node.children[1].layoutConstraints?.maxHeight, .infinity)
        }
    }

    func testDefaultMinListRowHeightEnvironmentCanBeRead() async {
        await MainActor.run {
            struct RowHeightReader: View {
                @Environment(\.defaultMinListRowHeight) var rowHeight

                var body: some View {
                    Text(rowHeight == 44 ? "CUSTOM" : "DEFAULT")
                }
            }

            let defaultNode = makeNode(RowHeightReader())
            let customNode = makeNode(RowHeightReader().environment(\.defaultMinListRowHeight, 44))

            XCTAssertEqual(defaultNode.text, "DEFAULT")
            XCTAssertEqual(customNode.text, "CUSTOM")
        }
    }

    func testBadgeModifierMapsToRetainedTrailingBadgeChrome() async {
        await MainActor.run {
            let numericNode = makeNode(Text("ROW").badge(3))
            let hiddenCountNode = makeNode(Text("ROW").badge(0))
            let hiddenStringNode = makeNode(Text("ROW").badge(nil as String?))
            let stringNode = makeNode(Text("ROW").badge("NEW"))

            guard case .stack(let numericLayout) = numericNode.layoutMode else {
                return XCTFail("Expected badge to wrap content in a retained horizontal stack")
            }

            XCTAssertEqual(numericLayout, .horizontal(spacing: 8, padding: .zero, alignment: .center))
            XCTAssertEqual(numericNode.children.count, 3)
            XCTAssertEqual(numericNode.children[0].text, "ROW")
            XCTAssertEqual(numericNode.children[1].layoutPriority, 1)
            XCTAssertEqual(numericNode.children[2].children[0].text, "3")
            XCTAssertEqual(numericNode.children[2].cornerRadius, 9)
            XCTAssertEqual(numericNode.children[2].layoutConstraints?.minWidth, 18)
            XCTAssertEqual(numericNode.children[2].layoutConstraints?.minHeight, 18)
            XCTAssertEqual(hiddenCountNode.text, "ROW")
            XCTAssertEqual(hiddenStringNode.text, "ROW")
            XCTAssertEqual(stringNode.children[2].children[0].text, "NEW")
        }
    }

    func testBadgeProminenceMapsToRetainedBadgeColorsAndEnvironment() async {
        await MainActor.run {
            struct BadgeProminenceReader: View {
                @Environment(\.badgeProminence) var badgeProminence

                var body: some View {
                    Text(badgeProminence == .increased ? "INCREASED" : "STANDARD")
                }
            }

            let standardNode = makeNode(Text("ROW").badge(1))
            let increasedNode = makeNode(Text("ROW").badge(1).badgeProminence(.increased))
            let environmentNode = makeNode(BadgeProminenceReader().badgeProminence(.increased))

            XCTAssertEqual(
                standardNode.children[2].backgroundColor,
                Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22)
            )
            XCTAssertEqual(
                increasedNode.children[2].backgroundColor,
                Color(red: 0.92, green: 0.18, blue: 0.24, alpha: 0.96)
            )
            XCTAssertEqual(environmentNode.text, "INCREASED")
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

    func testHeaderProminenceMapsToRetainedSectionHeaderFontWeight() async {
        await MainActor.run {
            let standardNode = makeNode(
                Section("TITLE") {
                    Text("ROW")
                }
            )
            let increasedNode = makeNode(
                Section("TITLE") {
                    Text("ROW")
                }
                .headerProminence(.increased)
            )
            let explicitHeaderNode = makeNode(
                Section {
                    Text("ROW")
                } header: {
                    Text("HEADER")
                        .font(.system(size: 12, weight: .regular))
                }
                .headerProminence(.increased)
            )

            XCTAssertEqual(standardNode.children[0].textStyle.weight, .semibold)
            XCTAssertEqual(increasedNode.children[0].textStyle.weight, .bold)
            XCTAssertEqual(explicitHeaderNode.children[0].textStyle.weight, .regular)
        }
    }

    func testHeaderProminenceEnvironmentCanBeRead() async {
        await MainActor.run {
            struct HeaderProminenceReader: View {
                @Environment(\.headerProminence) var headerProminence

                var body: some View {
                    Text(headerProminence == .increased ? "INCREASED" : "STANDARD")
                }
            }

            let defaultNode = makeNode(HeaderProminenceReader())
            let customNode = makeNode(HeaderProminenceReader().headerProminence(.increased))

            XCTAssertEqual(defaultNode.text, "STANDARD")
            XCTAssertEqual(customNode.text, "INCREASED")
        }
    }

    func testDefaultMinListHeaderHeightMapsToRetainedSectionHeaderConstraints() async {
        await MainActor.run {
            let node = makeNode(
                Section {
                    Text("ROW")
                } header: {
                    Text("HEADER")
                    Text("TALL")
                        .frame(minHeight: 60)
                }
                .environment(\.defaultMinListHeaderHeight, 32)
            )

            XCTAssertEqual(node.children[0].layoutConstraints?.minHeight, 32)
            XCTAssertEqual(node.children[0].layoutConstraints?.maxHeight, .infinity)
            XCTAssertEqual(node.children[1].layoutConstraints?.minHeight, 60)
            XCTAssertEqual(node.children[1].layoutConstraints?.maxHeight, .infinity)
            XCTAssertNil(node.children[2].layoutConstraints)
        }
    }

    func testDefaultMinListHeaderHeightEnvironmentCanBeRead() async {
        await MainActor.run {
            struct HeaderHeightReader: View {
                @Environment(\.defaultMinListHeaderHeight) var headerHeight

                var body: some View {
                    Text(headerHeight == 32 ? "CUSTOM" : "DEFAULT")
                }
            }

            let defaultNode = makeNode(HeaderHeightReader())
            let customNode = makeNode(HeaderHeightReader().environment(\.defaultMinListHeaderHeight, 32))

            XCTAssertEqual(defaultNode.text, "DEFAULT")
            XCTAssertEqual(customNode.text, "CUSTOM")
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

    func testControlGroupComposesCompactControlsAndPreservesActions() async {
        await MainActor.run {
            var activationCount = 0
            let node = makeNode(
                ControlGroup {
                    Button("EXPORT") {
                        activationCount += 1
                    }
                    Button("ARCHIVE") {}
                } label: {
                    Text("TOOLS")
                }
            )
            let titleNode = makeNode(
                ControlGroup(LocalizedStringKey("ACTIONS")) {
                    Button("SYNC") {}
                }
            )

            XCTAssertEqual(allTexts(in: node), ["TOOLS", "EXPORT", "ARCHIVE"])
            XCTAssertEqual(node.children[0].layoutPriority, 1)
            XCTAssertEqual(node.cornerRadius, 10)

            node.children[1].onActivate?()

            XCTAssertEqual(activationCount, 1)
            XCTAssertEqual(allTexts(in: titleNode), ["ACTIONS", "SYNC"])
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

    func testTabViewRendersBadgesInTabChrome() async {
        await MainActor.run {
            let node = makeNode(
                TabView {
                    Text("FIRST")
                        .tabItem { Text("FIRST TAB") }
                        .badge(3)
                    Text("SECOND")
                        .tabItem { Text("SECOND TAB") }
                        .badge(nil as String?)
                }
                .badgeProminence(.increased)
            )

            let tabTexts = allTexts(in: node.children[0])
            XCTAssertTrue(tabTexts.contains("FIRST TAB"))
            XCTAssertTrue(tabTexts.contains("3"))
            XCTAssertTrue(tabTexts.contains("SECOND TAB"))
            XCTAssertEqual(node.children[1].text, "FIRST")

            let firstTabButton = node.children[0].children[0]
            let firstTabContent = firstTabButton.children[0]
            XCTAssertEqual(firstTabContent.children[1].backgroundColor, Color(red: 0.92, green: 0.18, blue: 0.24, alpha: 0.96))
            XCTAssertEqual(node.children[0].children[1].children[0].text, "SECOND TAB")
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

    func testNavigationDestinationsUpdateIsPresentedEnvironment() async {
        await MainActor.run {
            struct PresentationStateReader: View {
                @Environment(\.isPresented) var isPresented

                var body: some View {
                    Text(isPresented ? "PRESENTED" : "ROOT")
                }
            }

            var isPresented = true
            let stack = NavigationStack {
                PresentationStateReader()
                    .navigationTitle("ROOT TITLE")
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { isPresented },
                    set: { isPresented = $0 }
                )
            ) {
                PresentationStateReader()
                    .navigationTitle("PRESENTED TITLE")
            }

            let presentedNode = makeNode(stack)

            XCTAssertTrue(allTexts(in: presentedNode.children[0]).contains("PRESENTED TITLE"))
            XCTAssertEqual(presentedNode.children[1].text, "PRESENTED")

            isPresented = false

            let rootNode = makeNode(stack)

            XCTAssertTrue(allTexts(in: rootNode.children[0]).contains("ROOT TITLE"))
            XCTAssertEqual(rootNode.children[1].text, "ROOT")
        }
    }

    func testDismissEnvironmentActionDismissesPresentedNavigationDestination() async {
        await MainActor.run {
            struct DismissButtonView: View {
                @Environment(\.dismiss) var dismiss

                var body: some View {
                    Button("CLOSE") {
                        dismiss()
                    }
                }
            }

            var isPresented = true
            var didInvalidate = false
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
                DismissButtonView()
                    .navigationTitle("PRESENTED TITLE")
            }

            let presentedNode = makeNode(
                stack,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(allTexts(in: presentedNode.children[0]).contains("PRESENTED TITLE"))
            XCTAssertTrue(allTexts(in: presentedNode.children[1]).contains("CLOSE"))

            firstFocusable(in: presentedNode.children[1])?.onActivate?()

            XCTAssertFalse(isPresented)
            XCTAssertTrue(didInvalidate)

            let rootNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: rootNode.children[0]).contains("ROOT TITLE"))
            XCTAssertEqual(rootNode.children[1].text, "ROOT")
        }
    }

    func testDismissEnvironmentActionPopsNavigationLinkDestination() async {
        await MainActor.run {
            struct DismissDetailView: View {
                @Environment(\.dismiss) var dismiss

                var body: some View {
                    Button("DONE") {
                        dismiss()
                    }
                }
            }

            var didInvalidate = false
            let stack = NavigationStack {
                NavigationLink("OPEN", destination: DismissDetailView().navigationTitle("DETAIL TITLE"))
                    .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(
                stack,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            firstFocusable(in: rootNode.children[1])?.onActivate?()

            XCTAssertTrue(didInvalidate)

            didInvalidate = false
            let detailNode = makeNode(
                stack,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("DETAIL TITLE"))
            XCTAssertTrue(allTexts(in: detailNode.children[1]).contains("DONE"))

            firstFocusable(in: detailNode.children[1])?.onActivate?()

            XCTAssertTrue(didInvalidate)

            let poppedNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: poppedNode.children[0]).contains("ROOT TITLE"))
            XCTAssertTrue(allTexts(in: poppedNode.children[1]).contains("OPEN"))
        }
    }

    func testDismissEnvironmentActionPopsNavigationPathBinding() async {
        await MainActor.run {
            struct DismissValueView: View {
                @Environment(\.dismiss) var dismiss
                let value: String

                var body: some View {
                    Button("DONE \(value)") {
                        dismiss()
                    }
                }
            }

            var path = ["detail"]
            var didInvalidate = false
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
                DismissValueView(value: value)
                    .navigationTitle("VALUE TITLE")
            }

            let detailNode = makeNode(
                stack,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("VALUE TITLE"))
            XCTAssertTrue(allTexts(in: detailNode.children[1]).contains("DONE detail"))

            firstFocusable(in: detailNode.children[1])?.onActivate?()

            XCTAssertTrue(path.isEmpty)
            XCTAssertTrue(didInvalidate)

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

    func testCustomViewModifierPreservesTaggedPickerMetadata() async {
        await MainActor.run {
            var selection = "one"

            let node = makeNode(
                Picker(
                    "MODE",
                    selection: Binding(
                        get: { selection },
                        set: { selection = $0 }
                    )
                ) {
                    Text("ONE")
                        .tag("one")
                        .modifier(IdentityModifier())
                    Text("TWO")
                        .tag("two")
                        .modifier(IdentityModifier())
                }
            )

            node.children[1].children[1].onActivate?()

            XCTAssertEqual(selection, "two")
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

    func testDatePickerMapsToRetainedLabelValueRow() async {
        await MainActor.run {
            struct DateEnvironmentReaderView: View {
                @Environment(\.calendar) var calendar
                @Environment(\.timeZone) var timeZone
                @Environment(\.locale) var locale

                var body: some View {
                    Text(
                        calendar.identifier == .gregorian
                            && timeZone.secondsFromGMT() == 3_600
                            && locale.identifier == "fr_FR"
                            ? "DATEENV"
                            : "DEFAULT"
                    )
                }
            }

            let date = Date(timeIntervalSince1970: 1_778_423_880)
            let dateNode = makeNode(
                DatePicker("START", selection: .constant(date), displayedComponents: .date)
            )
            let timeNode = makeNode(
                DatePicker(selection: .constant(date), displayedComponents: .hourAndMinute) {
                    Label("WINDOW", systemImage: "calendar")
                }
            )
            let rangedNode = makeNode(
                DatePicker(
                    LocalizedStringKey("DUE"),
                    selection: .constant(date),
                    in: date...date,
                    displayedComponents: .all
                )
            )
            let partialRangeNode = makeNode(
                DatePicker("AFTER", selection: .constant(date), in: date..., displayedComponents: .date)
            )
            let throughRangeNode = makeNode(
                DatePicker("BEFORE", selection: .constant(date), in: ...date, displayedComponents: .hourAndMinute)
            )
            let upToRangeNode = makeNode(
                DatePicker(selection: .constant(date), in: ..<date, displayedComponents: .date) {
                    Text("UNTIL")
                }
            )
            let timeZoneNode = makeNode(
                DatePicker("LOCAL", selection: .constant(date), displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 3_600)!)
            )
            let environmentReaderNode = makeNode(
                DateEnvironmentReaderView()
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 3_600)!)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
            )

            XCTAssertEqual(allTexts(in: dateNode), ["START", "2026-05-10"])
            XCTAssertTrue(allTexts(in: timeNode).contains("WINDOW"))
            XCTAssertTrue(allTexts(in: timeNode).contains("14:38"))
            XCTAssertEqual(allTexts(in: rangedNode), ["DUE", "2026-05-10 14:38"])
            XCTAssertEqual(allTexts(in: partialRangeNode), ["AFTER", "2026-05-10"])
            XCTAssertEqual(allTexts(in: throughRangeNode), ["BEFORE", "14:38"])
            XCTAssertEqual(allTexts(in: upToRangeNode), ["UNTIL", "2026-05-10"])
            XCTAssertEqual(allTexts(in: timeZoneNode), ["LOCAL", "15:38"])
            XCTAssertEqual(environmentReaderNode.text, "DATEENV")
            XCTAssertEqual(dateNode.children[0].layoutPriority, 1)
        }
    }

    func testColorPickerMapsToRetainedLabelValueSwatch() async {
        await MainActor.run {
            let color = Color(red: 51.0 / 255.0, green: 102.0 / 255.0, blue: 153.0 / 255.0, opacity: 128.0 / 255.0)
            let titledNode = makeNode(
                ColorPicker("ACCENT", selection: .constant(color))
            )
            let noOpacityNode = makeNode(
                ColorPicker(LocalizedStringKey("BRAND"), selection: .constant(color), supportsOpacity: false)
            )
            let builderNode = makeNode(
                ColorPicker(selection: .constant(.orange), supportsOpacity: true) {
                    Label("TINT", systemImage: "paintpalette")
                }
                .controlSize(.large)
            )

            XCTAssertEqual(allTexts(in: titledNode), ["ACCENT", "#33669980"])
            XCTAssertEqual(titledNode.children[1].children[0].backgroundColor, color)
            XCTAssertEqual(titledNode.children[1].children[0].preferredSize, Size(width: 34, height: 28))
            XCTAssertEqual(titledNode.children[0].layoutPriority, 1)
            XCTAssertEqual(allTexts(in: noOpacityNode), ["BRAND", "#336699"])
            XCTAssertTrue(allTexts(in: builderNode).contains("TINT"))
            XCTAssertEqual(builderNode.children[1].children[0].backgroundColor, .orange)
            XCTAssertEqual(builderNode.children[1].children[0].preferredSize, Size(width: 40, height: 34))
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
            let gaugeNode = makeNode(
                Gauge(value: 0.5, in: 0...1) {
                    Text("BATTERY")
                } currentValueLabel: {
                    Text("50%")
                } minimumValueLabel: {
                    Text("EMPTY")
                } maximumValueLabel: {
                    Text("FULL")
                }
                .labelsHidden()
            )
            let datePickerNode = makeNode(
                DatePicker("START", selection: .constant(Date(timeIntervalSince1970: 1_778_423_880)))
                    .labelsHidden()
            )
            let colorPickerNode = makeNode(
                ColorPicker("ACCENT", selection: .constant(.blue), supportsOpacity: false)
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

            XCTAssertFalse(gaugeNode.children.isEmpty)
            XCTAssertTrue(allTexts(in: gaugeNode).isEmpty)

            XCTAssertFalse(allTexts(in: datePickerNode).contains("START"))
            XCTAssertEqual(allTexts(in: datePickerNode), ["2026-05-10 14:38"])

            XCTAssertFalse(allTexts(in: colorPickerNode).contains("ACCENT"))
            XCTAssertEqual(allTexts(in: colorPickerNode), ["#0000FF"])
            XCTAssertEqual(colorPickerNode.children[0].backgroundColor, .blue)
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

    func testGaugeMapsToRetainedProgressBarWithSwiftUIShapedLabels() async {
        await MainActor.run {
            let stringNode = makeNode(Gauge("BATTERY", value: 0.75, in: 0...1))
            let keyNode = makeNode(Gauge(LocalizedStringKey("LOAD"), value: 0.5, in: 0...1))
            let node = makeNode(
                Gauge(value: 50, in: 0...200) {
                    Label("SPEED", systemImage: "speedometer")
                } currentValueLabel: {
                    Text("50 MPH")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("200")
                }
            )

            XCTAssertEqual(stringNode.children.count, 2)
            XCTAssertTrue(allTexts(in: stringNode.children[0]).contains("BATTERY"))
            XCTAssertEqual(stringNode.children[1].children[1].frame.size.width, 150)

            XCTAssertTrue(allTexts(in: keyNode.children[0]).contains("LOAD"))
            XCTAssertEqual(keyNode.children[1].children[1].frame.size.width, 100)

            XCTAssertEqual(node.children.count, 3)
            XCTAssertTrue(allTexts(in: node.children[0]).contains("SPEED"))
            XCTAssertTrue(allTexts(in: node.children[0]).contains("50 MPH"))
            XCTAssertEqual(node.children[1].children[1].frame.size.width, 50)
            XCTAssertEqual(firstText(in: node.children[2].children[0]), "0")
            XCTAssertEqual(firstText(in: node.children[2].children[2]), "200")
            XCTAssertEqual(node.children[2].children[0].textStyle.color, .secondary)
            XCTAssertEqual(node.children[2].children[2].textStyle.color, .secondary)
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
                    Gauge(value: 0.5, in: 0...1) {
                        Text("CAPACITY")
                    }
                }
                .tint(tint)
            )

            let toggleTrack = node.children[0].children[1].children[0]
            let sliderFilled = node.children[1].children[1]
            let progressFilled = node.children[2].children[1]
            let gaugeFilled = node.children[3].children[1].children[1]

            XCTAssertEqual(toggleTrack.backgroundColor, tint)
            XCTAssertEqual(sliderFilled.backgroundColor, tint)
            XCTAssertEqual(progressFilled.backgroundColor, tint)
            XCTAssertEqual(gaugeFilled.backgroundColor, tint)
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

    func testFocusableModifierMapsToRetainedFocusState() async {
        await MainActor.run {
            let focusableNode = makeNode(
                Text("FOCUS")
                    .allowsHitTesting(false)
                    .focusable()
            )
            let disabledNode = makeNode(
                Button("PRESS") {}
                    .focusable(false)
            )

            XCTAssertTrue(focusableNode.isFocusable)
            XCTAssertTrue(focusableNode.isHitTestVisible)
            XCTAssertFalse(disabledNode.isFocusable)
        }
    }

    func testHoverEffectModifiersMapToRetainedEffectMetadata() async {
        await MainActor.run {
            let liftNode = makeNode(
                Text("HOVER")
                    .allowsHitTesting(false)
                    .hoverEffect(.lift)
            )
            let defaultNode = makeNode(
                Text("DEFAULT")
                    .hoverEffect()
                    .defaultHoverEffect(.highlight)
            )
            let disabledNode = makeNode(
                Text("DISABLED")
                    .hoverEffect(.highlight)
                    .hoverEffectDisabled()
            )

            XCTAssertEqual(liftNode.hoverEffect, .lift)
            XCTAssertTrue(liftNode.isHitTestVisible)
            XCTAssertFalse(liftNode.isHoverEffectDisabled)
            XCTAssertEqual(defaultNode.hoverEffect, .highlight)
            XCTAssertNil(disabledNode.hoverEffect)
            XCTAssertTrue(disabledNode.isHoverEffectDisabled)
        }
    }

    func testFocusEffectDisabledModifierMapsToRetainedMetadata() async {
        await MainActor.run {
            let disabledNode = makeNode(Text("FOCUS").focusEffectDisabled())
            let enabledNode = makeNode(Text("FOCUS").focusEffectDisabled(false))

            XCTAssertTrue(disabledNode.isFocusEffectDisabled)
            XCTAssertFalse(enabledNode.isFocusEffectDisabled)
        }
    }

    func testRedactionModifiersPropagateThroughEnvironmentAndRetainedNodes() async {
        await MainActor.run {
            struct RedactionEnvironmentReader: View {
                @Environment(\.redactionReasons) var redactionReasons

                var body: some View {
                    Text(redactionReasons.contains(.placeholder) ? "REDACTED" : "PLAIN")
                }
            }

            let redactedNode = makeNode(Text("SECRET").redacted(reason: .placeholder))
            let inheritedNode = makeNode(RedactionEnvironmentReader().redacted(reason: .placeholder))
            let unredactedNode = makeNode(
                VStack {
                    RedactionEnvironmentReader()
                        .unredacted()
                }
                .redacted(reason: .placeholder)
            )

            XCTAssertEqual(redactedNode.redactionReasons, [.placeholder])
            XCTAssertEqual(inheritedNode.redactionReasons, [.placeholder])
            XCTAssertEqual(inheritedNode.text, "REDACTED")
            XCTAssertEqual(unredactedNode.redactionReasons, [.placeholder])
            XCTAssertEqual(unredactedNode.children.first?.redactionReasons, [])
            XCTAssertEqual(unredactedNode.children.first?.text, "PLAIN")
        }
    }

    func testPrivacySensitiveModifierPropagatesThroughEnvironmentAndRetainedNodes() async {
        await MainActor.run {
            struct PrivacyEnvironmentReader: View {
                @Environment(\.isPrivacySensitive) var isPrivacySensitive

                var body: some View {
                    Text(isPrivacySensitive ? "PRIVATE" : "PUBLIC")
                }
            }

            let privateNode = makeNode(Text("TOKEN").privacySensitive())
            let inheritedNode = makeNode(PrivacyEnvironmentReader().privacySensitive())
            let publicNode = makeNode(
                VStack {
                    PrivacyEnvironmentReader()
                        .privacySensitive(false)
                }
                .privacySensitive()
            )

            XCTAssertTrue(privateNode.isPrivacySensitive)
            XCTAssertTrue(inheritedNode.isPrivacySensitive)
            XCTAssertEqual(inheritedNode.text, "PRIVATE")
            XCTAssertTrue(publicNode.isPrivacySensitive)
            XCTAssertFalse(publicNode.children.first?.isPrivacySensitive ?? true)
            XCTAssertEqual(publicNode.children.first?.text, "PUBLIC")
        }
    }

    func testKeyboardShortcutModifierMapsAndActivatesRetainedNode() async {
        await MainActor.run {
            var activations = 0
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {}
            )
            let node = Button("SAVE") {
                activations += 1
            }
            .keyboardShortcut("s")
            .makeComponent(context: context)
            .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            _ = runtime.renderFrame()

            XCTAssertEqual(
                node.keyboardShortcuts,
                [KeyboardShortcutBinding(keyCode: 0x53, modifiers: [.control])]
            )

            runtime.keyDown(KeyboardEvent(keyCode: 0x53, modifiers: []))
            XCTAssertEqual(activations, 0)

            runtime.keyDown(KeyboardEvent(keyCode: 0x53, modifiers: [.control]))
            XCTAssertEqual(activations, 1)
        }
    }

    func testKeyboardShortcutSupportsExplicitModifiersAndDefaultAction() async {
        await MainActor.run {
            var modifiedActivations = 0
            var defaultActivations = 0
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {}
            )
            let modifiedNode = Button("RUN") {
                modifiedActivations += 1
            }
            .keyboardShortcut("r", modifiers: [.shift, .option])
            .makeComponent(context: context)
            .makeNode(runtime: runtime)
            let defaultNode = Button("OK") {
                defaultActivations += 1
            }
            .keyboardShortcut(.defaultAction)
            .makeComponent(context: context)
            .makeNode(runtime: runtime)

            runtime.root.addChild(modifiedNode)
            runtime.root.addChild(defaultNode)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            _ = runtime.renderFrame()

            XCTAssertEqual(
                modifiedNode.keyboardShortcuts,
                [KeyboardShortcutBinding(keyCode: 0x52, modifiers: [.shift, .alt])]
            )
            XCTAssertEqual(
                defaultNode.keyboardShortcuts,
                [KeyboardShortcutBinding(keyCode: KeyboardKey.enter.rawValue, modifiers: [])]
            )

            runtime.keyDown(KeyboardEvent(keyCode: 0x52, modifiers: [.shift, .alt]))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(modifiedActivations, 1)
            XCTAssertEqual(defaultActivations, 1)
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

    func testClipShapeCircleUsesDynamicRetainedCornerRadius() async {
        await MainActor.run {
            let node = renderedNode(
                Text("DOT")
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            )

            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.cornerRadius, 14)
            XCTAssertEqual(node.children[0].preferredSize, Size(width: 28, height: 28))
        }
    }

    func testClipShapeEllipseUsesDynamicRoundedRetainedFallback() async {
        await MainActor.run {
            let node = renderedNode(
                Text("OVAL")
                    .frame(width: 64, height: 24)
                    .clipShape(Ellipse())
            )

            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.cornerRadius, 12)
            XCTAssertEqual(node.children[0].preferredSize, Size(width: 64, height: 24))
        }
    }

    func testContentShapeCompatibilityOverloadsPreserveRetainedHitTesting() async {
        struct CustomContentShape: Shape {}

        await MainActor.run {
            let plainNode = makeNode(
                Text("PLAIN")
                    .contentShape(Rectangle())
            )
            let gestureNode = makeNode(
                Text("TAP")
                    .contentShape(Circle(), eoFill: true)
                    .onTapGesture {}
            )
            let kindNode = makeNode(
                Text("KIND")
                    .onTapGesture {}
                    .contentShape([.interaction, .hoverEffect, .accessibility], Capsule(), eoFill: true)
            )
            let customNode = makeNode(
                Text("CUSTOM")
                    .contentShape(.dragPreview, CustomContentShape())
            )

            XCTAssertEqual(plainNode.text, "PLAIN")
            XCTAssertTrue(gestureNode.isHitTestVisible)
            XCTAssertEqual(gestureNode.text, "TAP")
            XCTAssertTrue(kindNode.isHitTestVisible)
            XCTAssertEqual(kindNode.text, "KIND")
            XCTAssertEqual(customNode.text, "CUSTOM")
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

    func testBorderAcceptsStoredForegroundStyleAndGradientOverloads() async {
        await MainActor.run {
            let storedColor = Color(red: 0.25, green: 0.7, blue: 0.45, alpha: 1)
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.8, green: 0.2, blue: 0.6, alpha: 1),
                    Color(red: 0.1, green: 0.4, blue: 0.9, alpha: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            let storedColorNode = makeNode(
                Text("BORDER")
                    .border(ForegroundStyle.color(storedColor), width: 3, cornerRadius: 7)
            )
            let storedGradientNode = makeNode(
                Text("GRADIENT")
                    .border(ForegroundStyle.linearGradient(gradient), width: 4, cornerRadius: 9)
            )
            let gradientNode = makeNode(
                Text("DIRECT")
                    .border(gradient, width: 5, cornerRadius: 11)
            )

            XCTAssertEqual(storedColorNode.borderColor, storedColor)
            XCTAssertEqual(storedColorNode.borderWidth, 3)
            XCTAssertEqual(storedColorNode.cornerRadius, 7)
            XCTAssertEqual(storedColorNode.children[0].text, "BORDER")

            XCTAssertEqual(storedGradientNode.borderColor, gradient.startColor)
            XCTAssertEqual(storedGradientNode.borderWidth, 4)
            XCTAssertEqual(storedGradientNode.cornerRadius, 9)
            XCTAssertEqual(storedGradientNode.children[0].text, "GRADIENT")

            XCTAssertEqual(gradientNode.borderColor, gradient.startColor)
            XCTAssertEqual(gradientNode.borderWidth, 5)
            XCTAssertEqual(gradientNode.cornerRadius, 11)
            XCTAssertEqual(gradientNode.children[0].text, "DIRECT")
        }
    }

    func testShadowModifierAcceptsDefaultColorOverload() async {
        await MainActor.run {
            let defaultNode = makeNode(Text("CARD").shadow(radius: 6, x: 2, y: 3))
            let explicitNode = makeNode(Text("PANEL").shadow(color: .red, radius: 4, x: -1, y: 5))

            XCTAssertEqual(defaultNode.shadowColor, .black.opacity(0.33))
            XCTAssertEqual(defaultNode.shadowSpread, 6)
            XCTAssertEqual(defaultNode.shadowOffset, Point(x: 2, y: 3))
            XCTAssertEqual(defaultNode.children[0].text, "CARD")

            XCTAssertEqual(explicitNode.shadowColor, .red)
            XCTAssertEqual(explicitNode.shadowSpread, 4)
            XCTAssertEqual(explicitNode.shadowOffset, Point(x: -1, y: 5))
            XCTAssertEqual(explicitNode.children[0].text, "PANEL")
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
            let reduceMotionNode = makeNode(
                Text("QUIET")
                    .animation(.linear(duration: 0.4), value: true)
                    .environment(\.accessibilityReduceMotion, true)
            )

            XCTAssertEqual(animatedNode.animationStates[.opacity]?.duration, 0.4)
            if case .linear? = animatedNode.animationStates[.opacity]?.easing {
            } else {
                XCTFail("Expected linear easing")
            }
            XCTAssertTrue(disabledNode.animationStates.isEmpty)
            XCTAssertTrue(reduceMotionNode.animationStates.isEmpty)
        }
    }

    func testAccessibilityPreferenceEnvironmentValuesCanBeReadAndOverrideAnimation() async {
        await MainActor.run {
            struct AccessibilityPreferenceReaderView: View {
                @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
                @Environment(\.accessibilityInvertColors) var invertColors
                @Environment(\.accessibilityReduceMotion) var reduceMotion
                @Environment(\.accessibilityReduceTransparency) var reduceTransparency
                @Environment(\.accessibilityShowButtonShapes) var showButtonShapes
                @Environment(\.accessibilitySwitchControlEnabled) var switchControlEnabled
                @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled

                var body: some View {
                    Text(
                        differentiateWithoutColor
                            && invertColors
                            && reduceMotion
                            && reduceTransparency
                            && showButtonShapes
                            && switchControlEnabled
                            && voiceOverEnabled
                            ? "ACCESS"
                            : "DEFAULT"
                    )
                }
            }

            let defaultNode = makeNode(AccessibilityPreferenceReaderView())
            let overriddenNode = makeNode(
                AccessibilityPreferenceReaderView()
                    .environment(\.accessibilityDifferentiateWithoutColor, true)
                    .environment(\.accessibilityInvertColors, true)
                    .environment(\.accessibilityReduceMotion, true)
                    .environment(\.accessibilityReduceTransparency, true)
                    .environment(\.accessibilityShowButtonShapes, true)
                    .environment(\.accessibilitySwitchControlEnabled, true)
                    .environment(\.accessibilityVoiceOverEnabled, true)
            )

            XCTAssertEqual(defaultNode.text, "DEFAULT")
            XCTAssertEqual(overriddenNode.text, "ACCESS")
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

    func testScenePhaseEnvironmentValueCanBeReadAndOverridden() async {
        await MainActor.run {
            struct ScenePhaseReaderView: View {
                @Environment(\.scenePhase) var scenePhase

                var body: some View {
                    Text(
                        scenePhase == .active
                            ? "ACTIVE"
                            : scenePhase == .inactive
                                ? "INACTIVE"
                                : "BACKGROUND"
                    )
                }
            }

            let defaultNode = makeNode(ScenePhaseReaderView())
            let inactiveNode = makeNode(
                ScenePhaseReaderView()
                    .environment(\.scenePhase, .inactive)
            )
            let backgroundNode = makeNode(
                ScenePhaseReaderView()
                    .environment(\.scenePhase, .background)
            )

            XCTAssertEqual(defaultNode.text, "ACTIVE")
            XCTAssertEqual(inactiveNode.text, "INACTIVE")
            XCTAssertEqual(backgroundNode.text, "BACKGROUND")
        }
    }

    func testControlActiveEnvironmentValuesCanBeReadAndOverridden() async {
        await MainActor.run {
            struct ControlActiveReaderView: View {
                @Environment(\.controlActiveState) var controlActiveState
                @Environment(\.appearsActive) var appearsActive

                var body: some View {
                    Text(
                        "\(controlActiveState == .key ? "KEY" : controlActiveState == .active ? "ACTIVE" : "INACTIVE") "
                            + "\(appearsActive ? "APPEARS" : "DIMMED")"
                    )
                }
            }

            let defaultNode = makeNode(ControlActiveReaderView())
            let keyNode = makeNode(
                ControlActiveReaderView()
                    .environment(\.controlActiveState, .key)
            )
            let inactiveNode = makeNode(
                ControlActiveReaderView()
                    .environment(\.controlActiveState, .inactive)
                    .environment(\.appearsActive, false)
            )

            XCTAssertEqual(defaultNode.text, "ACTIVE APPEARS")
            XCTAssertEqual(keyNode.text, "KEY APPEARS")
            XCTAssertEqual(inactiveNode.text, "INACTIVE DIMMED")
        }
    }

    func testEditModeEnvironmentCanBeReadAndEditButtonTogglesBinding() async {
        await MainActor.run {
            struct EditModeReaderView: View {
                @Environment(\.editMode) var editMode

                var body: some View {
                    Text(
                        editMode == nil
                            ? "NO EDIT"
                            : editMode?.wrappedValue.isEditing == true
                                ? "EDITING"
                                : "INACTIVE"
                    )
                }
            }

            var editMode = EditMode.inactive
            let binding = Binding(
                get: { editMode },
                set: { editMode = $0 }
            )
            let defaultNode = makeNode(EditModeReaderView())
            let inactiveNode = makeNode(EditModeReaderView().environment(\.editMode, binding))
            let editButtonNode = makeNode(EditButton().environment(\.editMode, binding))

            XCTAssertEqual(defaultNode.text, "NO EDIT")
            XCTAssertEqual(inactiveNode.text, "INACTIVE")
            XCTAssertTrue(allTexts(in: editButtonNode).contains("Edit"))

            firstFocusable(in: editButtonNode)?.onActivate?()
            XCTAssertEqual(editMode, .active)

            let activeNode = makeNode(EditModeReaderView().environment(\.editMode, binding))
            let doneButtonNode = makeNode(EditButton().environment(\.editMode, binding))
            XCTAssertEqual(activeNode.text, "EDITING")
            XCTAssertTrue(allTexts(in: doneButtonNode).contains("Done"))

            firstFocusable(in: doneButtonNode)?.onActivate?()
            XCTAssertEqual(editMode, .inactive)
        }
    }

    func testDisplayScaleAndPixelLengthEnvironmentValuesCanBeReadAndOverridden() async {
        await MainActor.run {
            struct ScaleReaderView: View {
                @Environment(\.displayScale) var displayScale
                @Environment(\.pixelLength) var pixelLength

                var body: some View {
                    Text(
                        displayScale == 3 && abs(pixelLength - (1.0 / 3.0)) < 0.001
                            ? "SCALE3"
                            : displayScale == 2 && abs(pixelLength - 0.5) < 0.001
                                ? "SCALE2"
                                : "SCALE1"
                    )
                }
            }

            let defaultNode = makeNode(ScaleReaderView())
            let overrideNode = makeNode(
                ScaleReaderView()
                    .environment(\.displayScale, 3.0)
                    .environment(\.pixelLength, 1.0 / 3.0)
            )
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: ScaleReaderView(),
                size: IntSize(width: 200, height: 100),
                displayScale: 2
            )

            XCTAssertEqual(defaultNode.text, "SCALE1")
            XCTAssertEqual(overrideNode.text, "SCALE3")
            XCTAssertEqual(firstText(in: snapshot.runtime.root), "SCALE2")
            XCTAssertEqual(snapshot.runtime.displayScale, 2)
        }
    }

    func testLayoutDirectionEnvironmentFlipsLeadingTrailingAlignment() async {
        await MainActor.run {
            struct LayoutDirectionReaderView: View {
                @Environment(\.layoutDirection) var layoutDirection

                var body: some View {
                    Text(layoutDirection == .rightToLeft ? "RTL" : "LTR")
                        .multilineTextAlignment(.leading)
                }
            }

            let defaultNode = makeNode(LayoutDirectionReaderView())
            let rtlTextNode = makeNode(
                LayoutDirectionReaderView()
                    .environment(\.layoutDirection, .rightToLeft)
            )
            let rtlStackNode = makeNode(
                VStack(alignment: .leading) {
                    Text("ROW")
                }
                .environment(\.layoutDirection, .rightToLeft)
            )

            XCTAssertEqual(defaultNode.text, "LTR")
            XCTAssertEqual(defaultNode.textStyle.alignment, .leading)
            XCTAssertEqual(rtlTextNode.text, "RTL")
            XCTAssertEqual(rtlTextNode.textStyle.alignment, .trailing)
            if case .stack(let stackLayout) = rtlStackNode.layoutMode {
                XCTAssertEqual(stackLayout, .vertical(alignment: .trailing))
            } else {
                XCTFail("Expected retained stack layout")
            }
        }
    }

    func testSizeClassEnvironmentValuesCanBeReadAndOverridden() async {
        await MainActor.run {
            struct SizeClassReaderView: View {
                @Environment(\.horizontalSizeClass) var horizontalSizeClass
                @Environment(\.verticalSizeClass) var verticalSizeClass

                var body: some View {
                    Text(
                        "\(horizontalSizeClass == .compact ? "HC" : horizontalSizeClass == .regular ? "HR" : "HN") "
                            + "\(verticalSizeClass == .compact ? "VC" : verticalSizeClass == .regular ? "VR" : "VN")"
                    )
                }
            }

            let defaultNode = makeNode(SizeClassReaderView())
            let overrideNode = makeNode(
                SizeClassReaderView()
                    .environment(\.horizontalSizeClass, .compact)
                    .environment(\.verticalSizeClass, .regular)
            )

            XCTAssertEqual(defaultNode.text, "HN VN")
            XCTAssertEqual(overrideNode.text, "HC VR")
        }
    }

    func testUndoManagerEnvironmentCanBeReadAndPerformUndoRedo() async {
        await MainActor.run {
            final class UndoTarget {
                var value = 1
            }

            struct UndoManagerReaderView: View {
                @Environment(\.undoManager) var undoManager

                var body: some View {
                    Text(
                        undoManager == nil
                            ? "NO UNDO"
                            : undoManager?.canUndo == true
                                ? "CAN UNDO"
                                : "UNDO READY"
                    )
                }
            }

            let undoManager = UndoManager()
            let target = UndoTarget()
            undoManager.registerUndo(withTarget: target) { target in
                target.value = 0
                undoManager.registerUndo(withTarget: target) { target in
                    target.value = 1
                }
                undoManager.setActionName("Restore")
            }
            undoManager.setActionName("Clear")

            let defaultNode = makeNode(UndoManagerReaderView())
            let overrideNode = makeNode(UndoManagerReaderView().environment(\.undoManager, undoManager))

            XCTAssertEqual(defaultNode.text, "NO UNDO")
            XCTAssertEqual(overrideNode.text, "CAN UNDO")
            XCTAssertTrue(undoManager.canUndo)
            XCTAssertFalse(undoManager.canRedo)
            XCTAssertEqual(undoManager.undoActionName, "Clear")

            undoManager.undo()

            XCTAssertEqual(target.value, 0)
            XCTAssertFalse(undoManager.canUndo)
            XCTAssertTrue(undoManager.canRedo)
            XCTAssertEqual(undoManager.redoActionName, "Restore")

            undoManager.redo()

            XCTAssertEqual(target.value, 1)
            XCTAssertFalse(undoManager.canRedo)

            undoManager.registerUndo(withTarget: target) { target in
                target.value = 2
            }
            XCTAssertTrue(undoManager.canUndo)

            undoManager.removeAllActions()
            XCTAssertFalse(undoManager.canUndo)
            XCTAssertFalse(undoManager.canRedo)
        }
    }

    func testWindowSceneActionsCanBeReadAndOverridden() async {
        await MainActor.run {
            struct WindowActionReaderView: View {
                @Environment(\.openWindow) var openWindow
                @Environment(\.dismissWindow) var dismissWindow

                var body: some View {
                    VStack {
                        Button("OPEN") {
                            openWindow(id: "inspector")
                            openWindow(id: "detail", value: 7)
                            openWindow(value: "payload")
                        }
                        Button("DISMISS") {
                            dismissWindow()
                            dismissWindow(id: "inspector")
                            dismissWindow(id: "detail", value: 7)
                            dismissWindow(value: "payload")
                        }
                    }
                }
            }

            var opened: [String?] = []
            var dismissed: [String?] = []
            let node = makeNode(
                WindowActionReaderView()
                    .environment(
                        \.openWindow,
                        OpenWindowAction { id in
                            opened.append(id)
                        }
                    )
                    .environment(
                        \.dismissWindow,
                        DismissWindowAction { id in
                            dismissed.append(id)
                        }
                    )
            )

            let focusableNodes = focusableNodes(in: node)
            XCTAssertEqual(allTexts(in: node), ["OPEN", "DISMISS"])
            XCTAssertEqual(focusableNodes.count, 2)

            focusableNodes[0].onActivate?()
            focusableNodes[1].onActivate?()

            XCTAssertEqual(opened, ["inspector", "detail", nil])
            XCTAssertEqual(dismissed, [nil, "inspector", "detail", nil])
        }
    }

    func testSupportsMultipleWindowsEnvironmentCanBeReadAndOverridden() async {
        await MainActor.run {
            struct MultipleWindowsReaderView: View {
                @Environment(\.supportsMultipleWindows) var supportsMultipleWindows

                var body: some View {
                    Text(supportsMultipleWindows ? "MULTIWINDOW" : "SINGLEWINDOW")
                }
            }

            let defaultNode = makeNode(MultipleWindowsReaderView())
            let overrideNode = makeNode(
                MultipleWindowsReaderView()
                    .environment(\.supportsMultipleWindows, true)
            )

            XCTAssertEqual(defaultNode.text, "SINGLEWINDOW")
            XCTAssertEqual(overrideNode.text, "MULTIWINDOW")
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

    func testTransformEnvironmentMutatesInheritedValuesForSubtree() async {
        await MainActor.run {
            struct TransformEnvironmentReaderView: View {
                @Environment(\.lineLimit) var lineLimit
                @Environment(\.testEnvironmentLabel) var label

                var body: some View {
                    Text("\(label)-\(lineLimit ?? 0)")
                }
            }

            let node = makeNode(
                VStack {
                    TransformEnvironmentReaderView()
                    TransformEnvironmentReaderView()
                        .transformEnvironment(\.lineLimit) { limit in
                            limit = (limit ?? 0) + 1
                        }
                        .transformEnvironment(\.testEnvironmentLabel) { label in
                            label += "-INNER"
                        }
                }
                .environment(\.lineLimit, 2)
                .environment(\.testEnvironmentLabel, "OUTER")
            )

            XCTAssertEqual(node.children[0].text, "OUTER-2")
            XCTAssertEqual(node.children[1].text, "OUTER-INNER-3")
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

    func testTaskModifierRunsOnceWhenRendered() async {
        let counter = AsyncTaskCounter()

        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )

            let node = Text("LOAD")
                .task {
                    await counter.increment()
                }
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()
            _ = runtime.renderFrame()
        }

        await waitForAsyncTaskCounter(counter, toReach: 1)
        let finalCount = await counter.value()
        XCTAssertEqual(finalCount, 1)
    }

    func testTaskIDModifierRerunsWhenValueChanges() async {
        let counter = AsyncTaskCounter()

        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var taskID = 1

            host.setComponents {
                [
                    Text("LOAD")
                        .task(id: taskID) {
                            await counter.increment()
                        }
                        .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()

            taskID = 2
            host.reload()
        }

        await waitForAsyncTaskCounter(counter, toReach: 2)
        let finalCount = await counter.value()
        XCTAssertEqual(finalCount, 2)
    }

    func testRefreshableProvidesRefreshEnvironmentAction() async {
        let counter = AsyncTaskCounter()

        await MainActor.run {
            struct RefreshEnvironmentReaderView: View {
                @Environment(\.refresh) var refresh

                var body: some View {
                    Button(refresh == nil ? "NO REFRESH" : "REFRESH") {
                        guard let refresh else {
                            return
                        }

                        Swift.Task {
                            await refresh()
                        }
                    }
                }
            }

            let defaultNode = makeNode(RefreshEnvironmentReaderView())
            let refreshableNode = makeNode(
                RefreshEnvironmentReaderView()
                    .refreshable {
                        await counter.increment()
                    }
            )

            XCTAssertTrue(allTexts(in: defaultNode).contains("NO REFRESH"))
            XCTAssertTrue(allTexts(in: refreshableNode).contains("REFRESH"))

            firstFocusable(in: refreshableNode)?.onActivate?()
        }

        await waitForAsyncTaskCounter(counter, toReach: 1)
        let finalCount = await counter.value()
        XCTAssertEqual(finalCount, 1)
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

    func testViewThatFitsSelectsFirstCandidateMatchingRequestedAxes() async {
        await MainActor.run {
            let horizontalNode = makeNode(
                ViewThatFits(in: .horizontal) {
                    Text("WIDE").frame(width: 120, height: 12)
                    Text("NARROW").frame(width: 40, height: 80)
                },
                size: Size(width: 50, height: 20)
            )
            let verticalNode = makeNode(
                ViewThatFits(in: .vertical) {
                    Text("TALL").frame(width: 120, height: 80)
                    Text("SHORT").frame(width: 120, height: 12)
                },
                size: Size(width: 50, height: 20)
            )
            let fallbackNode = makeNode(
                ViewThatFits {
                    Text("TOO WIDE").frame(width: 120, height: 12)
                    Text("TOO TALL").frame(width: 40, height: 80)
                },
                size: Size(width: 50, height: 20)
            )

            XCTAssertEqual(firstText(in: horizontalNode), "NARROW")
            XCTAssertEqual(firstText(in: verticalNode), "SHORT")
            XCTAssertEqual(firstText(in: fallbackNode), "TOO TALL")
        }
    }

    func testLabeledContentMapsToRetainedLabelValueRow() async {
        await MainActor.run {
            let builderNode = makeNode(
                LabeledContent {
                    Text("VALUE")
                } label: {
                    Text("LABEL")
                }
            )
            let stringNode = makeNode(LabeledContent("STATUS", value: "READY"))
            let keyNode = makeNode(LabeledContent(LocalizedStringKey("MODE"), value: "AUTO"))

            XCTAssertEqual(allTexts(in: builderNode), ["LABEL", "VALUE"])
            XCTAssertEqual(builderNode.children[0].layoutPriority, 1)
            XCTAssertEqual(builderNode.children[0].textStyle.color, .secondary)
            XCTAssertEqual(allTexts(in: stringNode), ["STATUS", "READY"])
            XCTAssertEqual(allTexts(in: keyNode), ["MODE", "AUTO"])
        }
    }

    func testContentUnavailableViewMapsToRetainedPlaceholderSurface() async {
        await MainActor.run {
            var retryCount = 0
            let builderNode = makeNode(
                ContentUnavailableView {
                    Label("OFFLINE", systemImage: "wifi.slash")
                } description: {
                    Text("CHECK CONNECTION")
                } actions: {
                    Button("RETRY") {
                        retryCount += 1
                    }
                }
            )
            let titledNode = makeNode(
                ContentUnavailableView(
                    "NO RESULTS",
                    systemImage: "magnifyingglass",
                    description: Text("TRY ANOTHER TERM")
                )
            )
            let searchNode = makeNode(ContentUnavailableView.search(text: "widgets"))

            let builderTexts = allTexts(in: builderNode)
            XCTAssertTrue(builderTexts.contains("OFFLINE"))
            XCTAssertTrue(builderTexts.contains("CHECK CONNECTION"))
            XCTAssertTrue(builderTexts.contains("RETRY"))
            XCTAssertEqual(builderNode.children.count, 3)
            XCTAssertEqual(firstText(in: builderNode.children[1]), "CHECK CONNECTION")
            XCTAssertEqual(builderNode.children[1].textStyle.color, .secondary)

            builderNode.children[2].onActivate?()

            XCTAssertEqual(retryCount, 1)
            XCTAssertTrue(allTexts(in: titledNode).contains("NO RESULTS"))
            XCTAssertTrue(allTexts(in: titledNode).contains("TRY ANOTHER TERM"))
            XCTAssertTrue(allTexts(in: searchNode).contains("No Results"))
            XCTAssertTrue(allTexts(in: searchNode).contains("No results for widgets"))
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

private func waitForAsyncTaskCounter(_ counter: AsyncTaskCounter, toReach expectedValue: Int) async {
    for _ in 0..<50 {
        if await counter.value() >= expectedValue {
            return
        }
        try? await Swift.Task.sleep(nanoseconds: 10_000_000)
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
private func firstTextNode(in node: ViewNode) -> ViewNode? {
    if node.text != nil {
        return node
    }

    for child in node.children {
        if let textNode = firstTextNode(in: child) {
            return textNode
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
private func focusableNodes(in node: ViewNode) -> [ViewNode] {
    var nodes: [ViewNode] = node.isFocusable ? [node] : []

    for child in node.children {
        nodes.append(contentsOf: focusableNodes(in: child))
    }

    return nodes
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
