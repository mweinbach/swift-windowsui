import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private struct OneThirdHorizontalAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double {
        context.width / 3
    }
}
private struct ThreeQuarterVerticalAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double {
        context.height * 0.75
    }
}
@MainActor
private struct PointerHandlerProbe: View {
    typealias Body = Never

    var onEnter: (() -> Void)? = nil
    var onExit: (() -> Void)? = nil
    var onMove: ((Point) -> Void)? = nil
    var onDown: (() -> Void)? = nil
    var onUpInside: (() -> Void)? = nil
    var onUpOutside: (() -> Void)? = nil
    var onKeyDown: ((KeyboardEvent) -> Void)? = nil

    var body: Never {
        fatalError("PointerHandlerProbe has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            let node = Controls.panel(preferredSize: Size(width: 80, height: 24))
            node.onPointerEnter = onEnter
            node.onPointerExit = onExit
            node.onPointerMove = onMove
            node.onPointerDown = onDown
            node.onPointerUpInside = onUpInside
            node.onPointerUpOutside = onUpOutside
            node.onKeyDown = onKeyDown
            return node
        }
    }
}
private struct NavigationDestinationItem: Identifiable {
    let id: String
}
private enum TestParseError: Error {
    case invalid
}
private struct TestIntegerParseStrategy: ParseStrategy {
    func parse(_ value: String) throws -> Int {
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let parsed = Int(normalized) else {
            throw TestParseError.invalid
        }
        return parsed
    }
}
private struct TestIntegerParseableFormatStyle: ParseableFormatStyle {
    var parseStrategy: TestIntegerParseStrategy {
        TestIntegerParseStrategy()
    }

    func format(_ value: Int) -> String {
        "#\(value)"
    }
}
private struct TestEnvironmentLabelKey: EnvironmentKey {
    static let defaultValue = "DEFAULT"
}
extension EnvironmentValues {
    fileprivate var testEnvironmentLabel: String {
        get { self[TestEnvironmentLabelKey.self] }
        set { self[TestEnvironmentLabelKey.self] = newValue }
    }
}
private struct TestFocusedLabelKey: FocusedValueKey {
    typealias Value = String
}
private struct TestFocusedBindingKey: FocusedValueKey {
    typealias Value = Binding<String>
}
extension FocusedValues {
    fileprivate var testFocusedLabel: String? {
        get { self[TestFocusedLabelKey.self] }
        set { self[TestFocusedLabelKey.self] = newValue }
    }

    fileprivate var testFocusedBinding: Binding<String>? {
        get { self[TestFocusedBindingKey.self] }
        set { self[TestFocusedBindingKey.self] = newValue }
    }
}
private struct TestStringPreferenceKey: PreferenceKey {
    static let defaultValue = "DEFAULT"

    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}
private struct TestSumPreferenceKey: PreferenceKey {
    static let defaultValue = 0

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}
private struct TestAnchorListPreferenceKey: PreferenceKey {
    static let defaultValue: [Anchor<Rect>] = []

    static func reduce(value: inout [Anchor<Rect>], nextValue: () -> [Anchor<Rect>]) {
        value.append(contentsOf: nextValue())
    }
}
private struct TestLayoutRoleKey: LayoutValueKey {
    static let defaultValue = "regular"
}
private struct TestLayoutCountKey: LayoutValueKey {
    static let defaultValue = 0
}
private struct TestContainerRoleKey: ContainerValueKey {
    static let defaultValue = "regular"
}
private struct TestContainerCountKey: ContainerValueKey {
    static let defaultValue = 0
}
extension ContainerValues {
    fileprivate var testContainerRole: String {
        get { self[TestContainerRoleKey.self] }
        set { self[TestContainerRoleKey.self] = newValue }
    }

    fileprivate var testContainerCount: Int {
        get { self[TestContainerCountKey.self] }
        set { self[TestContainerCountKey.self] = newValue }
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
private actor AsyncTaskLifecycleRecorder {
    private var starts: [Int] = []
    private var cancellationCount = 0

    func recordStart(_ id: Int = 0) {
        starts.append(id)
    }

    func recordCancellation() {
        cancellationCount += 1
    }

    func startCount() -> Int {
        starts.count
    }

    func startedIDs() -> [Int] {
        starts
    }

    func cancellations() -> Int {
        cancellationCount
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
            // Values match Apple's documented macOS / SF Symbols system
            // colors — see docs/MacOSDesignParity.md for the canonical
            // table and provenance. Use an accuracy tolerance to absorb
            // Float rounding from the 3-decimal hex conversions.
            XCTAssertEqual(Color.red.red, 1.0, accuracy: 0.005)
            XCTAssertEqual(Color.red.green, 0.231, accuracy: 0.005)
            XCTAssertEqual(Color.red.blue, 0.188, accuracy: 0.005)

            XCTAssertEqual(Color.orange.red, 1.0, accuracy: 0.005)
            XCTAssertEqual(Color.orange.green, 0.584, accuracy: 0.005)
            XCTAssertEqual(Color.orange.blue, 0.0, accuracy: 0.005)

            XCTAssertEqual(Color.yellow.red, 1.0, accuracy: 0.005)
            XCTAssertEqual(Color.yellow.green, 0.8, accuracy: 0.005)
            XCTAssertEqual(Color.yellow.blue, 0.0, accuracy: 0.005)

            XCTAssertEqual(Color.green.red, 0.204, accuracy: 0.005)
            XCTAssertEqual(Color.green.green, 0.78, accuracy: 0.005)
            XCTAssertEqual(Color.green.blue, 0.349, accuracy: 0.005)

            XCTAssertEqual(Color.blue.red, 0.0, accuracy: 0.005)
            XCTAssertEqual(Color.blue.green, 0.478, accuracy: 0.005)
            XCTAssertEqual(Color.blue.blue, 1.0, accuracy: 0.005)

            XCTAssertEqual(Color.mint.red, 0.0, accuracy: 0.005)
            XCTAssertEqual(Color.mint.green, 0.78, accuracy: 0.005)
            XCTAssertEqual(Color.mint.blue, 0.745, accuracy: 0.005)

            XCTAssertEqual(Color.teal.red, 0.188, accuracy: 0.005)
            XCTAssertEqual(Color.teal.green, 0.69, accuracy: 0.005)
            XCTAssertEqual(Color.teal.blue, 0.78, accuracy: 0.005)

            XCTAssertEqual(Color.cyan.red, 0.196, accuracy: 0.005)
            XCTAssertEqual(Color.cyan.green, 0.678, accuracy: 0.005)
            XCTAssertEqual(Color.cyan.blue, 0.902, accuracy: 0.005)

            XCTAssertEqual(Color.indigo.red, 0.345, accuracy: 0.005)
            XCTAssertEqual(Color.indigo.green, 0.337, accuracy: 0.005)
            XCTAssertEqual(Color.indigo.blue, 0.839, accuracy: 0.005)

            XCTAssertEqual(Color.purple.red, 0.686, accuracy: 0.005)
            XCTAssertEqual(Color.purple.green, 0.322, accuracy: 0.005)
            XCTAssertEqual(Color.purple.blue, 0.871, accuracy: 0.005)

            XCTAssertEqual(Color.pink.red, 1.0, accuracy: 0.005)
            XCTAssertEqual(Color.pink.green, 0.176, accuracy: 0.005)
            XCTAssertEqual(Color.pink.blue, 0.333, accuracy: 0.005)

            XCTAssertEqual(Color.brown.red, 0.635, accuracy: 0.005)
            XCTAssertEqual(Color.brown.green, 0.518, accuracy: 0.005)
            XCTAssertEqual(Color.brown.blue, 0.369, accuracy: 0.005)

            XCTAssertEqual(Color.gray.red, 0.557, accuracy: 0.005)
            XCTAssertEqual(Color.gray.green, 0.557, accuracy: 0.005)
            XCTAssertEqual(Color.gray.blue, 0.576, accuracy: 0.005)

            // The semantic label rungs: one achromatic alpha ladder, whose
            // base the appearance picks. They used to be an opaque white and
            // a blue-cast slate with no light counterpart.
            XCTAssertEqual(Color.primary, Color(red: 1, green: 1, blue: 1, alpha: LabelHierarchy.primaryAlpha))
            XCTAssertEqual(
                Color.secondary, Color(red: 1, green: 1, blue: 1, alpha: LabelHierarchy.secondaryAlpha))
            XCTAssertEqual(
                Color.accentColor, ControlPalette.darkStandard.accentFill,
                "the accent is the design system's own #5B4DE0, not the OS blue")
            XCTAssertEqual(Color.accentColor, ViewBuildContext.defaultTint)
        }
    }

    func testSwiftUIColorInitializersMapToCoreRGBA() async {
        await MainActor.run {
            assertColor(Color(white: 0.25, opacity: 0.75), red: 0.25, green: 0.25, blue: 0.25, alpha: 0.75)
            assertColor(Color(white: 1.5, opacity: -0.25), red: 1, green: 1, blue: 1, alpha: 0)
            assertColor(Color(hue: 0, saturation: 1, brightness: 1), red: 1, green: 0, blue: 0, alpha: 1)
            assertColor(Color(hue: 1.0 / 3.0, saturation: 1, brightness: 1), red: 0, green: 1, blue: 0, alpha: 1)
            assertColor(
                Color(hue: 0.5, saturation: 0.5, brightness: 0.8, opacity: 0.6), red: 0.4, green: 0.8, blue: 0.8,
                alpha: 0.6)
            assertColor(Color(hue: -0.25, saturation: 1, brightness: 0.5), red: 0.25, green: 0, blue: 0.5, alpha: 1)
        }
    }

    func testSwiftUIColorRGBColorSpaceInitializersMapToCoreRGBA() async {
        await MainActor.run {
            XCTAssertEqual(Set<Color.RGBColorSpace>([.sRGB, .sRGBLinear, .displayP3]).count, 3)
            assertColor(
                Color(.displayP3, red: 0.1, green: 0.2, blue: 0.3, opacity: 0.4),
                red: 0.05935608, green: 0.20308941, blue: 0.30873041,
                alpha: 0.4)
            assertColor(
                Color(.sRGBLinear, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.6), red: 0.5370987, green: 0.735357,
                blue: 0.880825, alpha: 0.6)
            assertColor(
                Color(.sRGBLinear, white: 0.35, opacity: 0.65), red: 0.6262097, green: 0.6262097, blue: 0.6262097,
                alpha: 0.65)
            assertColor(
                Color(.sRGBLinear, red: -1, green: 2, blue: .nan, opacity: 1.5),
                red: -1, green: 1.35325605, blue: 0, alpha: 1.5)
            assertColor(
                Color(.sRGB, red: 1.2, green: -0.2, blue: 0.5, opacity: 1.5), red: 1.2, green: -0.2, blue: 0.5,
                alpha: 1.5)
        }
    }

    func testColorResourceInitializersResolveHexNamesAndFallbackDeterministically() async {
        await MainActor.run {
            let resource = ColorResource(name: "BrandColor", bundle: .main)
            let sameResource = ColorResource(name: "BrandColor", bundle: .main)
            let otherResource = ColorResource(name: "AccentFill", bundle: .main)

            XCTAssertEqual(resource, sameResource)
            XCTAssertNotEqual(resource, otherResource)
            XCTAssertTrue(Set([resource]).contains(sameResource))
            XCTAssertEqual(Color(resource), .accentColor)
            XCTAssertEqual(Color("BrandColor", bundle: .main), .accentColor)
            XCTAssertEqual(Color("BrandColor"), .accentColor)
            assertColor(
                Color("#33669980"), red: 51.0 / 255.0, green: 102.0 / 255.0, blue: 153.0 / 255.0, alpha: 128.0 / 255.0)
            assertColor(Color("0xF80"), red: 1, green: 136.0 / 255.0, blue: 0, alpha: 1)
            assertColor(
                Color(ColorResource(name: "0F08", bundle: .main)), red: 0, green: 1, blue: 0, alpha: 136.0 / 255.0)
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
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )

            XCTAssertEqual(node.text, "HELLO")
            // Points are points: `.system(size: 24)` renders at 24, and the
            // 5x7 atlas scale is derived from it rather than being a second
            // meaning for the same argument.
            XCTAssertEqual(node.textStyle.scale, 2.4)
            XCTAssertEqual(node.textStyle.nativeFontSize, 24)
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
                (Text("HELLO ")
                    .foregroundColor(leftColor)
                    .font(.system(size: 18, weight: .bold))
                    .underline()
                    + Text("WORLD")
                    .foregroundColor(rightColor)
                    .font(.system(size: 12, weight: .regular))
                    .strikethrough())
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
                    ControlGroup(title, systemImage: "slider.horizontal.3") {
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

            XCTAssertGreaterThanOrEqual(allTexts(in: node).filter { $0 == "SAVE" }.count, 15)
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

    func testTextSelectionRetainsExplicitAndInheritedSelectability() async {
        await MainActor.run {
            let enabledNode = makeNode(Text("COPY").textSelection(.enabled))
            let inheritedNode = makeNode(
                VStack {
                    Text("ONE")
                    Text("TWO")
                }
                .textSelection(.disabled)
            )

            XCTAssertEqual(enabledNode.textSelectability, .enabled)
            XCTAssertEqual(inheritedNode.children[0].textSelectability, .disabled)
            XCTAssertEqual(inheritedNode.children[1].textSelectability, .disabled)
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

    func testTextLocalizedStringKeyTableBundleCommentInitializerMapsToPlainRetainedText() async {
        await MainActor.run {
            let key = LocalizedStringKey("PROFILE TITLE")
            let node = makeNode(
                Text(
                    key,
                    tableName: "Account",
                    bundle: .main,
                    comment: "Displayed above the account settings form"
                )
            )

            XCTAssertEqual(node.text, "PROFILE TITLE")
        }
    }

    func testLocalizedStringResourceInputMapsToLocalizedRetainedText() async {
        await MainActor.run {
            let count = 3
            let resource: LocalizedStringResource = "SYNC \(count)"
            let sameResource = LocalizedStringResource("SYNC 3")
            let otherResource = LocalizedStringResource("IDLE")
            let textNode = makeNode(Text(resource))

            XCTAssertEqual(resource, sameResource)
            XCTAssertNotEqual(resource, otherResource)
            XCTAssertTrue(Set([resource]).contains(sameResource))
            XCTAssertEqual(String(describing: resource), "SYNC 3")
            XCTAssertEqual(String(localized: resource), "SYNC 3")
            XCTAssertEqual(textNode.text, "SYNC 3")
        }
    }

    func testTextDateStyleInitializersMapToDeterministicRetainedText() async {
        await MainActor.run {
            let date = Date(timeIntervalSince1970: 90_061)

            XCTAssertEqual(makeNode(Text(date, style: .date)).text, "1970-01-02")
            XCTAssertEqual(makeNode(Text(date, style: .time)).text, "01:01")
            XCTAssertEqual(makeNode(Text(date, style: .relative)).text, "1970-01-02 01:01")
            XCTAssertEqual(makeNode(Text(date, style: .offset)).text, "1970-01-02 01:01")
            XCTAssertEqual(makeNode(Text(date, style: .timer)).text, "1970-01-02 01:01")
            XCTAssertTrue(Set([Text.DateStyle.date]).contains(.date))
        }
    }

    func testTextDateIntervalInitializerMapsToDeterministicRetainedText() async {
        await MainActor.run {
            let start = Date(timeIntervalSince1970: 0)
            let end = Date(timeIntervalSince1970: 5_400)
            let node = makeNode(Text(DateInterval(start: start, end: end)))

            XCTAssertEqual(node.text, "1970-01-01 00:00 - 1970-01-01 01:30")
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

    func testDeprecatedTextFieldEditingAndCommitInitializerHooksRetainedInput() async {
        await MainActor.run {
            var value = ""
            var editingChanges: [Bool] = []
            var commitCount = 0
            var invalidationCount = 0
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(
                TextField(
                    "NAME",
                    text: binding,
                    onEditingChanged: { isEditing in
                        editingChanges.append(isEditing)
                    },
                    onCommit: {
                        commitCount += 1
                    }
                ),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            node.onFocusEnter?()
            node.onKeyDown?(KeyboardEvent(keyCode: 0x41))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            node.onFocusExit?()

            XCTAssertEqual(value, "a")
            XCTAssertEqual(editingChanges, [true, false])
            XCTAssertEqual(commitCount, 1)
            XCTAssertEqual(invalidationCount, 2)
        }
    }

    func testDeprecatedTextFieldCommitOnlyInitializerSupportsLocalizedTitle() async {
        await MainActor.run {
            var commitCount = 0
            let node = makeNode(
                TextField(LocalizedStringKey("SEARCH"), text: .constant("")) {
                    commitCount += 1
                }
            )

            XCTAssertEqual(node.children[0].text, "SEARCH")

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(commitCount, 1)
        }
    }

    func testDeprecatedTextFieldFormatterEditingAndCommitInitializerHooksRetainedInput() async {
        await MainActor.run {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none

            var value = 4
            var editingChanges: [Bool] = []
            var commitCount = 0
            var invalidationCount = 0
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(
                TextField(
                    "COUNT",
                    value: binding,
                    formatter: formatter,
                    onEditingChanged: { isEditing in
                        editingChanges.append(isEditing)
                    },
                    onCommit: {
                        commitCount += 1
                    }
                ),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertEqual(node.children[0].text, "4")

            node.onFocusEnter?()
            node.onKeyDown?(KeyboardEvent(keyCode: 0x32))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            node.onFocusExit?()

            XCTAssertEqual(value, 42)
            XCTAssertEqual(editingChanges, [true, false])
            XCTAssertEqual(commitCount, 1)
            XCTAssertEqual(invalidationCount, 2)
        }
    }

    func testDeprecatedTextFieldFormatterCommitOnlyInitializerSupportsLocalizedTitle() async {
        await MainActor.run {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none

            var value = 6
            var commitCount = 0
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(
                TextField(LocalizedStringKey("COUNT"), value: binding, formatter: formatter) {
                    commitCount += 1
                }
            )

            XCTAssertEqual(node.children[0].text, "6")

            node.onKeyDown?(KeyboardEvent(keyCode: 0x31))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(value, 61)
            XCTAssertEqual(commitCount, 1)
        }
    }

    func testDeprecatedTextFieldOptionalFormatterEditingAndCommitInitializerHooksRetainedInput() async {
        await MainActor.run {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none

            var value: Int?
            var editingChanges: [Bool] = []
            var commitCount = 0
            var invalidationCount = 0
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(
                TextField(
                    "COUNT",
                    value: binding,
                    formatter: formatter,
                    onEditingChanged: { isEditing in
                        editingChanges.append(isEditing)
                    },
                    onCommit: {
                        commitCount += 1
                    }
                ),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertEqual(node.children[0].text, "COUNT")

            node.onFocusEnter?()
            node.onKeyDown?(KeyboardEvent(keyCode: 0x35))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            node.onFocusExit?()

            XCTAssertEqual(value, 5)
            XCTAssertEqual(editingChanges, [true, false])
            XCTAssertEqual(commitCount, 1)
            XCTAssertEqual(invalidationCount, 2)
        }
    }

    func testDeprecatedTextFieldOptionalFormatterCommitOnlyInitializerSupportsLocalizedTitle() async {
        await MainActor.run {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none

            var value: Int?
            var commitCount = 0
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )

            let node = makeNode(
                TextField(LocalizedStringKey("COUNT"), value: binding, formatter: formatter) {
                    commitCount += 1
                }
            )

            XCTAssertEqual(node.children[0].text, "COUNT")

            node.onKeyDown?(KeyboardEvent(keyCode: 0x38))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(value, 8)
            XCTAssertEqual(commitCount, 1)
        }
    }

    func testTextInputSupportsBasicCaretNavigationAndDeletion() async {
        await MainActor.run {
            var value = "abc"
            var invalidationCount = 0
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let node = makeNode(
                TextField("NAME", text: binding),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertEqual(node.textInputCaretOffset, 3)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x58))
            XCTAssertEqual(value, "abxc")
            XCTAssertEqual(node.textInputCaretOffset, 3)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.home.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x51))
            XCTAssertEqual(value, "qabxc")
            XCTAssertEqual(node.textInputCaretOffset, 1)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.deleteForward.rawValue))
            XCTAssertEqual(value, "qbxc")
            XCTAssertEqual(node.textInputCaretOffset, 1)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.end.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))
            XCTAssertEqual(value, "qbc")
            XCTAssertEqual(node.textInputCaretOffset, 2)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x5A))
            XCTAssertEqual(value, "qbcz")
            XCTAssertEqual(node.textInputCaretOffset, 4)
            XCTAssertEqual(invalidationCount, 10)
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
            // macOS masks with U+2022 BULLET, not the ASCII asterisk.
            XCTAssertEqual(secureValueNode.children[0].text, "••••")
        }
    }

    func testTextFieldBuilderLabelInitializerMapsLabelAndPromptToPlaceholder() async {
        await MainActor.run {
            let labelNode = makeNode(
                TextField(text: .constant("")) {
                    Label("DISPLAY NAME", systemImage: "person")
                }
            )
            let promptNode = makeNode(
                TextField(text: .constant(""), prompt: Text("PROMPT")) {
                    Text("LABEL")
                }
            )
            var value = "hi"
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let multilineNode = makeNode(
                TextField(text: binding, axis: .vertical) {
                    Text("NOTES")
                }
            )

            XCTAssertEqual(labelNode.children[0].text, "DISPLAY NAME")
            XCTAssertEqual(promptNode.children[0].text, "PROMPT")
            XCTAssertEqual(multilineNode.preferredSize, Size(width: 260, height: 120))
            XCTAssertNil(multilineNode.children[0].textStyle.maximumNumberOfLines)

            multilineNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            multilineNode.onKeyDown?(KeyboardEvent(keyCode: 0x4E))

            XCTAssertEqual(value, "hi\nn")
        }
    }

    func testTextFieldFormatterValueInitializersDisplayAndWriteBinding() async {
        await MainActor.run {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none

            var count = 12
            let countBinding = Binding(
                get: { count },
                set: { count = $0 }
            )
            let countNode = makeNode(
                TextField("COUNT", value: countBinding, formatter: formatter)
            )

            XCTAssertEqual(countNode.children[0].text, "12")

            countNode.onKeyDown?(KeyboardEvent(keyCode: 0x33))

            XCTAssertEqual(count, 123)
            XCTAssertEqual(countNode.textInputCaretOffset, 3)

            countNode.onKeyDown?(KeyboardEvent(keyCode: 0x41))

            XCTAssertEqual(count, 123)

            var builderValue = 7
            let builderNode = makeNode(
                TextField(
                    value: Binding(
                        get: { builderValue },
                        set: { builderValue = $0 }
                    ),
                    formatter: formatter,
                    prompt: Text("COUNT")
                ) {
                    Text("TOTAL")
                }
            )

            XCTAssertEqual(builderNode.children[0].text, "7")

            builderNode.onKeyDown?(KeyboardEvent(keyCode: 0x39))

            XCTAssertEqual(builderValue, 79)

            var optionalValue: Int? = 5
            let optionalNode = makeNode(
                TextField(
                    LocalizedStringKey("COUNT"),
                    value: Binding(
                        get: { optionalValue },
                        set: { optionalValue = $0 }
                    ),
                    formatter: formatter
                )
            )

            XCTAssertEqual(optionalNode.children[0].text, "5")

            optionalNode.onKeyDown?(KeyboardEvent(keyCode: 0x36))

            XCTAssertEqual(optionalValue, 56)

            optionalNode.onKeyDown?(KeyboardEvent(keyCode: 0x41))

            XCTAssertEqual(optionalValue, 56)

            var emptyOptional: Int? = nil
            let emptyOptionalNode = makeNode(
                TextField(
                    value: Binding(
                        get: { emptyOptional },
                        set: { emptyOptional = $0 }
                    ),
                    formatter: formatter,
                    prompt: Text("COUNT")
                ) {
                    Text("COUNT")
                }
            )

            XCTAssertEqual(emptyOptionalNode.children[0].text, "COUNT")

            emptyOptionalNode.onKeyDown?(KeyboardEvent(keyCode: 0x38))

            XCTAssertEqual(emptyOptional, 8)
        }
    }

    func testTextFieldParseableFormatStyleValueInitializersDisplayAndWriteBinding() async {
        await MainActor.run {
            let format = TestIntegerParseableFormatStyle()

            var count = 12
            let countBinding = Binding(
                get: { count },
                set: { count = $0 }
            )
            let countNode = makeNode(
                TextField("COUNT", value: countBinding, format: format)
            )

            XCTAssertEqual(countNode.children[0].text, "#12")

            countNode.onKeyDown?(KeyboardEvent(keyCode: 0x33))

            XCTAssertEqual(count, 123)

            countNode.onKeyDown?(KeyboardEvent(keyCode: 0x41))

            XCTAssertEqual(count, 123)

            var optionalCount: Int? = 4
            let optionalNode = makeNode(
                TextField(
                    value: Binding(
                        get: { optionalCount },
                        set: { optionalCount = $0 }
                    ),
                    format: format,
                    prompt: Text("COUNT")
                ) {
                    Text("TOTAL")
                }
            )

            XCTAssertEqual(optionalNode.children[0].text, "#4")

            optionalNode.onKeyDown?(KeyboardEvent(keyCode: 0x35))

            XCTAssertEqual(optionalCount, 45)

            optionalNode.onKeyDown?(KeyboardEvent(keyCode: 0x41))

            XCTAssertNil(optionalCount)
        }
    }

    func testSecureFieldBuilderLabelInitializerMapsLabelAndPromptToPlaceholder() async {
        await MainActor.run {
            let labelNode = makeNode(
                SecureField(text: .constant("")) {
                    Text("PASSWORD")
                }
            )
            let promptNode = makeNode(
                SecureField(text: .constant(""), prompt: Text("SECRET")) {
                    Text("PASSWORD")
                }
            )
            let valueNode = makeNode(
                SecureField(text: .constant("open")) {
                    Text("PASSWORD")
                }
            )

            XCTAssertEqual(labelNode.children[0].text, "PASSWORD")
            XCTAssertEqual(promptNode.children[0].text, "SECRET")
            XCTAssertEqual(valueNode.children[0].text, "••••")
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
            XCTAssertEqual(node.children.count, 1)
            guard let viewport = node.children.first else {
                XCTFail("The multiline input must retain its viewport")
                return
            }
            XCTAssertEqual(viewport.scrollAxis, .vertical)
            XCTAssertTrue(viewport.clipsToBounds)
            XCTAssertNil(viewport.text)
            XCTAssertEqual(viewport.children.count, 1)
            guard let content = viewport.children.first else {
                XCTFail("The viewport must retain its text content")
                return
            }
            let fragments = content.children.filter { $0.text != nil }
            XCTAssertEqual(fragments.compactMap(\.text), ["hi"])
            XCTAssertEqual(node.accessibilityValue, "hi")
            XCTAssertNil(viewport.textStyle.maximumNumberOfLines)
            XCTAssertEqual(viewport.textStyle.lineBreakMode, .wrap)
            for fragment in fragments {
                XCTAssertFalse(fragment.isHidden)
                XCTAssertEqual(fragment.textStyle.maximumNumberOfLines, 1)
                XCTAssertEqual(fragment.textStyle.lineBreakMode, .clip)
            }

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
                        "\(textInputAutocapitalization == .characters ? "CHARACTERS" : "OTHER") "
                            + "\(isAutocorrectionDisabled ? "DISABLED" : "ENABLED")"
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
                    .disableAutocorrection(true)
            )
            let resetNode = makeNode(
                TextInputEnvironmentReader()
                    .disableAutocorrection(nil)
            )

            XCTAssertEqual(wordsValue, "Ab C")
            XCTAssertEqual(sentenceValue, "hi. D")
            XCTAssertEqual(readerNode.text, "CHARACTERS DISABLED")
            XCTAssertEqual(resetNode.text, "OTHER ENABLED")
        }
    }

    func testTextContentTypeModifierRetainsMetadata() async {
        await MainActor.run {
            var value = ""
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let explicitNode = makeNode(
                TextField("USER", text: binding)
                    .textContentType(.username)
            )
            let secureNode = makeNode(
                SecureField("PASSWORD", text: binding)
                    .textContentType(.password)
            )
            let resetNode = makeNode(
                TextField("RESET", text: binding)
                    .textContentType(nil)
            )
            let inheritedNode = makeNode(
                VStack {
                    TextField("EMAIL", text: binding)
                    TextEditor(text: binding)
                        .textContentType(.URL)
                }
                .textContentType(.emailAddress)
            )

            XCTAssertEqual(explicitNode.textContentType, RetainedTextContentType(rawValue: "username"))
            XCTAssertEqual(secureNode.textContentType, RetainedTextContentType(rawValue: "password"))
            XCTAssertNil(resetNode.textContentType)
            XCTAssertEqual(inheritedNode.children[0].textContentType, RetainedTextContentType(rawValue: "emailAddress"))
            XCTAssertEqual(inheritedNode.children[1].textContentType, RetainedTextContentType(rawValue: "URL"))
        }
    }

    func testTextSelectionAffinityModifierRetainsTextAndInputMetadata() async {
        await MainActor.run {
            struct TextSelectionAffinityReader: View {
                @Environment(\.textSelectionAffinity) var textSelectionAffinity

                var body: some View {
                    Text(
                        textSelectionAffinity == .upstream
                            ? "UPSTREAM" : textSelectionAffinity == .downstream ? "DOWNSTREAM" : "AUTO")
                }
            }

            var value = ""
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let textNode = makeNode(
                Text("LABEL")
                    .textSelectionAffinity(.upstream)
            )
            let fieldNode = makeNode(
                TextField("QUERY", text: binding)
                    .textSelectionAffinity(.downstream)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("TITLE")
                    SecureField("SECRET", text: binding)
                    TextEditor(text: binding)
                        .textSelectionAffinity(.automatic)
                    TextSelectionAffinityReader()
                }
                .textSelectionAffinity(.upstream)
            )

            XCTAssertEqual(textNode.textSelectionAffinity, .upstream)
            XCTAssertEqual(fieldNode.textSelectionAffinity, .downstream)
            XCTAssertEqual(inheritedNode.children[0].textSelectionAffinity, .upstream)
            XCTAssertEqual(inheritedNode.children[1].textSelectionAffinity, .upstream)
            XCTAssertEqual(inheritedNode.children[2].textSelectionAffinity, .automatic)
            XCTAssertEqual(inheritedNode.children[3].text, "UPSTREAM")
        }
    }

    func testTextInputSelectionBindingRetainsAndUpdatesMetadata() async {
        await MainActor.run {
            var fieldValue = "abcd"
            var fieldSelection: TextSelection? = TextSelection(
                insertionPoint: fieldValue.index(fieldValue.startIndex, offsetBy: 2)
            )
            let fieldBinding = Binding(
                get: { fieldValue },
                set: { fieldValue = $0 }
            )
            let fieldSelectionBinding = Binding<TextSelection?>(
                get: { fieldSelection },
                set: { fieldSelection = $0 }
            )
            let fieldNode = makeNode(
                TextField("VALUE", text: fieldBinding, selection: fieldSelectionBinding)
                    .textSelectionAffinity(.downstream)
            )

            XCTAssertEqual(fieldNode.textInputCaretOffset, 2)
            XCTAssertEqual(
                fieldNode.textInputSelection,
                RetainedTextSelection(indices: .insertionPoint(2), affinity: .automatic)
            )

            fieldNode.onKeyDown?(KeyboardEvent(keyCode: 0x58))

            XCTAssertEqual(fieldValue, "abxcd")
            XCTAssertEqual(fieldNode.textInputCaretOffset, 3)
            XCTAssertEqual(
                fieldNode.textInputSelection,
                RetainedTextSelection(indices: .insertionPoint(3), affinity: .downstream)
            )
            XCTAssertEqual(fieldSelection?.affinity, .downstream)
            if case .selection(let range) = fieldSelection?.indices {
                XCTAssertTrue(range.isEmpty)
                XCTAssertEqual(fieldValue.distance(from: fieldValue.startIndex, to: range.lowerBound), 3)
            } else {
                XCTFail("Expected insertion-point selection after retained editing")
            }

            var editorValue = "hello"
            var editorSelection: TextSelection? = TextSelection(
                range: editorValue.index(
                    editorValue.startIndex, offsetBy: 1)..<editorValue.index(editorValue.startIndex, offsetBy: 4)
            )
            let editorBinding = Binding(
                get: { editorValue },
                set: { editorValue = $0 }
            )
            let editorSelectionBinding = Binding<TextSelection?>(
                get: { editorSelection },
                set: { editorSelection = $0 }
            )
            let editorNode = makeNode(
                TextEditor(text: editorBinding, selection: editorSelectionBinding)
            )

            XCTAssertEqual(editorNode.textInputCaretOffset, 4)
            XCTAssertEqual(
                editorNode.textInputSelection,
                RetainedTextSelection(indices: .range(1..<4), affinity: .automatic)
            )

            let firstRange = editorValue.startIndex..<editorValue.index(editorValue.startIndex, offsetBy: 1)
            let secondRange = editorValue.index(editorValue.startIndex, offsetBy: 3)..<editorValue.endIndex
            let multiSelection = TextSelection(ranges: RangeSet([firstRange, secondRange]))
            let multiNode = makeNode(
                TextEditor(text: editorBinding, selection: .constant(multiSelection))
            )

            XCTAssertFalse(multiSelection.isInsertion)
            XCTAssertEqual(multiNode.textInputCaretOffset, 5)
            XCTAssertEqual(
                multiNode.textInputSelection,
                RetainedTextSelection(indices: .ranges([0..<1, 3..<5]), affinity: .automatic)
            )
        }
    }

    func testTextInputSingleRangeSelectionReplacesAndDeletes() async {
        await MainActor.run {
            func insertionOffset(_ selection: TextSelection?, in text: String) -> Int? {
                guard case .selection(let range) = selection?.indices, range.isEmpty else {
                    return nil
                }
                return text.distance(from: text.startIndex, to: range.lowerBound)
            }

            var insertValue = "abcdef"
            var insertSelection: TextSelection? = TextSelection(
                range: insertValue.index(
                    insertValue.startIndex, offsetBy: 1)..<insertValue.index(insertValue.startIndex, offsetBy: 3)
            )
            let insertNode = makeNode(
                TextField(
                    "VALUE",
                    text: Binding(
                        get: { insertValue },
                        set: { insertValue = $0 }
                    ),
                    selection: Binding<TextSelection?>(
                        get: { insertSelection },
                        set: { insertSelection = $0 }
                    )
                )
            )

            insertNode.onKeyDown?(KeyboardEvent(keyCode: 0x58))

            XCTAssertEqual(insertValue, "axdef")
            XCTAssertEqual(insertNode.textInputCaretOffset, 2)
            XCTAssertEqual(insertNode.textInputSelection, RetainedTextSelection(indices: .insertionPoint(2)))
            XCTAssertEqual(insertionOffset(insertSelection, in: insertValue), 2)

            var backspaceValue = "abcdef"
            var backspaceSelection: TextSelection? = TextSelection(
                range: backspaceValue.index(
                    backspaceValue.startIndex, offsetBy: 2)..<backspaceValue.index(
                        backspaceValue.startIndex, offsetBy: 4)
            )
            let backspaceNode = makeNode(
                TextField(
                    "VALUE",
                    text: Binding(
                        get: { backspaceValue },
                        set: { backspaceValue = $0 }
                    ),
                    selection: Binding<TextSelection?>(
                        get: { backspaceSelection },
                        set: { backspaceSelection = $0 }
                    )
                )
            )

            backspaceNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))

            XCTAssertEqual(backspaceValue, "abef")
            XCTAssertEqual(backspaceNode.textInputCaretOffset, 2)
            XCTAssertEqual(backspaceNode.textInputSelection, RetainedTextSelection(indices: .insertionPoint(2)))
            XCTAssertEqual(insertionOffset(backspaceSelection, in: backspaceValue), 2)

            var deleteValue = "abcdef"
            var deleteSelection: TextSelection? = TextSelection(
                range: deleteValue.index(
                    deleteValue.startIndex, offsetBy: 2)..<deleteValue.index(deleteValue.startIndex, offsetBy: 5)
            )
            let deleteNode = makeNode(
                TextEditor(
                    text: Binding(
                        get: { deleteValue },
                        set: { deleteValue = $0 }
                    ),
                    selection: Binding<TextSelection?>(
                        get: { deleteSelection },
                        set: { deleteSelection = $0 }
                    )
                )
            )

            deleteNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.deleteForward.rawValue))

            XCTAssertEqual(deleteValue, "abf")
            XCTAssertEqual(deleteNode.textInputCaretOffset, 2)
            XCTAssertEqual(
                deleteNode.textInputSelection,
                RetainedTextSelection(indices: .insertionPoint(2), affinity: .downstream)
            )
            XCTAssertEqual(insertionOffset(deleteSelection, in: deleteValue), 2)
            XCTAssertEqual(deleteSelection?.affinity, .downstream)
        }
    }

    func testKeyboardTypeModifierRetainsTextInputMetadata() async {
        await MainActor.run {
            var value = ""
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let emailNode = makeNode(
                TextField("EMAIL", text: binding)
                    .keyboardType(.emailAddress)
            )
            let secureNode = makeNode(
                SecureField("PIN", text: binding)
                    .keyboardType(.numberPad)
            )
            let inheritedNode = makeNode(
                VStack {
                    TextField("SEARCH", text: binding)
                    TextEditor(text: binding)
                        .keyboardType(.URL)
                }
                .keyboardType(.webSearch)
            )
            let resetNode = makeNode(
                TextField("DEFAULT", text: binding)
                    .keyboardType(.default)
            )
            let textNode = makeNode(
                Text("LABEL")
                    .keyboardType(.decimalPad)
            )
            let unknownNode = makeNode(
                TextField("CUSTOM", text: binding)
                    .keyboardType(UIKeyboardType(rawValue: 999))
            )

            XCTAssertEqual(emailNode.textInputKeyboardType, .emailAddress)
            XCTAssertEqual(secureNode.textInputKeyboardType, .numberPad)
            XCTAssertEqual(inheritedNode.children[0].textInputKeyboardType, .webSearch)
            XCTAssertEqual(inheritedNode.children[1].textInputKeyboardType, .URL)
            XCTAssertEqual(resetNode.textInputKeyboardType, .default)
            XCTAssertEqual(textNode.textInputKeyboardType, .default)
            XCTAssertEqual(unknownNode.textInputKeyboardType, .default)
            XCTAssertEqual(UIKeyboardType.alphabet.rawValue, UIKeyboardType.asciiCapable.rawValue)
        }
    }

    func testTextInputSuggestionsAndCompletionRetainMetadata() async {
        await MainActor.run {
            struct Venue: Identifiable {
                var id: Int
                var name: String
                var address: String
            }

            var value = ""
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let venues = [
                Venue(id: 1, name: "FILLMORE", address: "1805 GEARY"),
                Venue(id: 2, name: "CATALYST", address: "1011 PACIFIC"),
            ]

            let builderNode = makeNode(
                TextField("LOCATION", text: binding)
                    .textInputSuggestions {
                        Text("FILLMORE")
                            .textInputCompletion("1805 GEARY")
                        Label("CATALYST", systemImage: "mappin")
                            .textInputCompletion("1011 PACIFIC")
                        Section("RECENTS") {
                            Text("RIO")
                                .textInputCompletion("1205 SOQUEL")
                        }
                    }
            )
            let dataNode = makeNode(
                TextField("DATA", text: binding)
                    .textInputSuggestions(venues) { venue in
                        Text(venue.name)
                            .textInputCompletion(venue.address)
                    }
            )
            let idNode = makeNode(
                TextField("ID", text: binding)
                    .textInputSuggestions(venues, id: \.name) { venue in
                        Text(venue.name)
                            .textInputCompletion(venue.address)
                    }
            )
            let completionNode = makeNode(
                Text("CHOICE")
                    .textInputCompletion("chosen value")
            )

            XCTAssertEqual(
                builderNode.textInputSuggestions,
                [
                    RetainedTextInputSuggestion(displayText: "FILLMORE", completion: "1805 GEARY"),
                    RetainedTextInputSuggestion(displayText: "CATALYST", completion: "1011 PACIFIC"),
                    RetainedTextInputSuggestion(displayText: "RIO", completion: "1205 SOQUEL"),
                ]
            )
            XCTAssertEqual(
                dataNode.textInputSuggestions,
                [
                    RetainedTextInputSuggestion(displayText: "FILLMORE", completion: "1805 GEARY"),
                    RetainedTextInputSuggestion(displayText: "CATALYST", completion: "1011 PACIFIC"),
                ]
            )
            XCTAssertEqual(idNode.textInputSuggestions, dataNode.textInputSuggestions)
            XCTAssertEqual(completionNode.textInputCompletion, "chosen value")
        }
    }

    func testWritingToolsBehaviorModifierRetainsTextMetadata() async {
        await MainActor.run {
            struct WritingToolsEnvironmentReader: View {
                @Environment(\.writingToolsBehavior) var writingToolsBehavior

                var body: some View {
                    Text(writingToolsBehavior == .limited ? "LIMITED" : "OTHER")
                }
            }

            var value = ""
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let textNode = makeNode(
                Text("NOTE")
                    .writingToolsBehavior(.complete)
            )
            let fieldNode = makeNode(
                TextField("TITLE", text: binding)
                    .writingToolsBehavior(.disabled)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("SUMMARY")
                    TextEditor(text: binding)
                        .writingToolsBehavior(.automatic)
                    WritingToolsEnvironmentReader()
                }
                .writingToolsBehavior(.limited)
            )

            XCTAssertEqual(textNode.writingToolsBehavior, .complete)
            XCTAssertEqual(fieldNode.writingToolsBehavior, .disabled)
            XCTAssertEqual(inheritedNode.children[0].writingToolsBehavior, .limited)
            XCTAssertEqual(inheritedNode.children[1].writingToolsBehavior, .automatic)
            XCTAssertEqual(inheritedNode.children[2].text, "LIMITED")
        }
    }

    func testWritingToolsAffordanceVisibilityModifierRetainsTextInputMetadata() async {
        await MainActor.run {
            struct WritingToolsAffordanceVisibilityReader: View {
                @Environment(\.writingToolsAffordanceVisibility) var writingToolsAffordanceVisibility

                var body: some View {
                    Text(writingToolsAffordanceVisibility == .hidden ? "HIDDEN" : "OTHER")
                }
            }

            var value = ""
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let visibleNode = makeNode(
                TextField("TITLE", text: binding)
                    .writingToolsAffordanceVisibility(.visible)
            )
            let inheritedNode = makeNode(
                VStack {
                    SecureField("PASSWORD", text: binding)
                    TextEditor(text: binding)
                        .writingToolsAffordanceVisibility(.automatic)
                    WritingToolsAffordanceVisibilityReader()
                }
                .writingToolsAffordanceVisibility(.hidden)
            )
            let textNode = makeNode(
                Text("NOTE")
                    .writingToolsAffordanceVisibility(.hidden)
            )

            XCTAssertEqual(visibleNode.writingToolsAffordanceVisibility, .visible)
            XCTAssertEqual(inheritedNode.children[0].writingToolsAffordanceVisibility, .hidden)
            XCTAssertEqual(inheritedNode.children[1].writingToolsAffordanceVisibility, .automatic)
            XCTAssertEqual(inheritedNode.children[2].text, "HIDDEN")
            XCTAssertEqual(textNode.writingToolsAffordanceVisibility, .automatic)
        }
    }

    func testTextEditorFindAndReplaceModifiersRetainMetadata() async {
        await MainActor.run {
            var value = "Find me"
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let disabledNode = makeNode(
                TextEditor(text: binding)
                    .findDisabled()
                    .replaceDisabled()
            )
            let resetNode = makeNode(
                TextEditor(text: binding)
                    .findDisabled(false)
                    .replaceDisabled(false)
            )
            let inheritedNode = makeNode(
                VStack {
                    TextEditor(text: binding)
                    TextEditor(text: binding)
                        .findDisabled(false)
                        .replaceDisabled(false)
                }
                .findDisabled()
                .replaceDisabled()
            )

            XCTAssertTrue(disabledNode.isFindDisabled)
            XCTAssertTrue(disabledNode.isReplaceDisabled)
            XCTAssertFalse(resetNode.isFindDisabled)
            XCTAssertFalse(resetNode.isReplaceDisabled)
            XCTAssertTrue(inheritedNode.children[0].isFindDisabled)
            XCTAssertTrue(inheritedNode.children[0].isReplaceDisabled)
            XCTAssertFalse(inheritedNode.children[1].isFindDisabled)
            XCTAssertFalse(inheritedNode.children[1].isReplaceDisabled)
        }
    }

    func testTextEditorFindNavigatorModifierRetainsPresentationState() async {
        await MainActor.run {
            var value = "Find me"
            var isPresented = true
            var isResetPresented = false
            let binding = Binding(
                get: { value },
                set: { value = $0 }
            )
            let presentedBinding = Binding(
                get: { isPresented },
                set: { isPresented = $0 }
            )
            let resetBinding = Binding(
                get: { isResetPresented },
                set: { isResetPresented = $0 }
            )
            let presentedNode = makeNode(
                TextEditor(text: binding)
                    .findNavigator(isPresented: presentedBinding)
            )
            let resetNode = makeNode(
                TextEditor(text: binding)
                    .findNavigator(isPresented: resetBinding)
            )
            let inheritedNode = makeNode(
                VStack {
                    TextEditor(text: binding)
                    TextEditor(text: binding)
                        .findNavigator(isPresented: resetBinding)
                }
                .findNavigator(isPresented: presentedBinding)
            )

            XCTAssertTrue(presentedNode.isFindNavigatorPresented)
            XCTAssertFalse(resetNode.isFindNavigatorPresented)
            XCTAssertTrue(inheritedNode.children[0].isFindNavigatorPresented)
            XCTAssertFalse(inheritedNode.children[1].isFindNavigatorPresented)
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

    func testDeprecatedSecureFieldCommitInitializerHooksRetainedEnterKey() async {
        await MainActor.run {
            var commitCount = 0
            let node = makeNode(
                SecureField("PASSWORD", text: .constant("secret")) {
                    commitCount += 1
                }
            )

            XCTAssertEqual(node.children[0].text, "••••••")

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(commitCount, 1)
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

    func testSubmitScopeBlocksOuterSubmitHandlersForScopedTextInputs() async {
        await MainActor.run {
            var outerSubmitCount = 0
            var innerSubmitCount = 0
            var unscopedSubmitCount = 0
            let scopedNode = makeNode(
                VStack {
                    TextField("SCOPED", text: .constant(""))
                        .onSubmit {
                            innerSubmitCount += 1
                        }
                        .submitScope()
                    TextField("UNSCOPED", text: .constant(""))
                }
                .onSubmit {
                    outerSubmitCount += 1
                }
            )
            let unblockedNode = makeNode(
                TextField("OPEN", text: .constant(""))
                    .submitScope(false)
                    .onSubmit {
                        unscopedSubmitCount += 1
                    }
            )

            let scopedField = scopedNode.children[0]
            let unscopedField = scopedNode.children[1]

            XCTAssertTrue(scopedField.isSubmitScopeBoundary)
            XCTAssertFalse(unblockedNode.isSubmitScopeBoundary)

            scopedField.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            unscopedField.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            unblockedNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(innerSubmitCount, 1)
            XCTAssertEqual(outerSubmitCount, 1)
            XCTAssertEqual(unscopedSubmitCount, 1)
        }
    }

    func testSubmitScopeWithTriggersBlocksOnlyMatchingTriggers() async {
        await MainActor.run {
            var textCount = 0
            var searchCount = 0
            let node = makeNode(
                VStack {
                    TextField("TEXT", text: .constant(""))
                        .onSubmit(of: .text) {
                            textCount += 1
                        }
                        .submitScope(.text)
                }
                .onSubmit(of: .text) {
                    textCount += 10
                }
                .onSubmit(of: .search) {
                    searchCount += 10
                }
            )

            let textField = node.children[0]

            XCTAssertTrue(textField.isSubmitScopeBoundary)
            XCTAssertEqual(textField.submitScopeTriggersRawValue, SubmitTriggers.text.rawValue)

            // Outer .text is blocked by the text field's scope, but outer .search passes through.
            // Since outer .search attaches after inner .text, it overwrites the wrapper.
            // This proves .search passed through while .text was blocked.
            textField.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            XCTAssertEqual(textCount, 0)
            XCTAssertEqual(searchCount, 10)
        }
    }

    func testSubmitLabelModifierAcceptsSwiftUIReturnKeyLabels() async {
        await MainActor.run {
            struct SubmitLabelReaderView: View {
                @Environment(\.submitLabel) var submitLabel

                var body: some View {
                    Text(submitLabel == .send ? "SEND" : submitLabel == .next ? "NEXT" : "RETURN")
                }
            }

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
            let readerNode = makeNode(SubmitLabelReaderView().submitLabel(.send))
            let environmentReaderNode = makeNode(
                SubmitLabelReaderView()
                    .environment(\.submitLabel, .next)
            )

            searchNode.onKeyDown?(KeyboardEvent(keyCode: 0x51))

            XCTAssertEqual(value, "q")
            XCTAssertEqual(searchNode.textInputSubmitLabel, .search)
            XCTAssertEqual(continueNode.textInputSubmitLabel, .continue)
            XCTAssertTrue(continueNode.isFocusable)
            XCTAssertEqual(readerNode.text, "SEND")
            XCTAssertEqual(environmentReaderNode.text, "NEXT")
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
            XCTAssertEqual(node.children[0].nodeTag, "search-field-toolbar")
            // A field is a field: the control radius, and the field ring. The
            // accent belonged to the *focus* ring, and drew a permanent
            // tinted outline around a resting toolbar search box.
            XCTAssertEqual(node.children[0].cornerRadius, MacOSControlMetrics.Radius.sm)
            XCTAssertEqual(node.children[0].borderColor, ControlPalette.darkStandard.controlBorder)
            XCTAssertNil(node.children[0].textInputDictationBehavior)
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

    func testSearchDictationBehaviorRetainsSearchFieldMetadata() async {
        await MainActor.run {
            var query = ""
            let binding = Binding(
                get: { query },
                set: { query = $0 }
            )
            let preventedNode = makeNode(
                Text("RESULTS")
                    .searchable(text: binding)
                    .searchDictationBehavior(.preventDictation)
            )
            let inlineNode = makeNode(
                Text("RESULTS")
                    .searchable(text: binding)
                    .searchDictationBehavior(.inline(activation: .onSelect))
            )
            let normalFieldNode = makeNode(
                TextField("QUERY", text: binding)
                    .searchDictationBehavior(.inline(activation: .onLook))
            )

            XCTAssertEqual(preventedNode.children[0].textInputDictationBehavior, .preventDictation)
            XCTAssertEqual(inlineNode.children[0].textInputDictationBehavior, .inline(activation: .onSelect))
            XCTAssertNil(normalFieldNode.textInputDictationBehavior)
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
            XCTAssertEqual(visibleNode.children[0].nodeTag, "search-field-navigation-drawer")
            XCTAssertEqual(visibleNode.children[0].cornerRadius, MacOSControlMetrics.Radius.sm)
            XCTAssertEqual(
                visibleNode.children[0].preferredSize,
                Size(width: 280, height: ControlSize.regular.singleLineTextInputSize.height))
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
                    Text(
                        textFieldStyle == .plain
                            ? "PLAIN"
                            : textFieldStyle == .roundedBorder
                                ? "ROUNDED"
                                : textFieldStyle == .squareBorder
                                    ? "SQUARE"
                                    : "AUTOMATIC"
                    )
                }
            }

            let plainNode = makeNode(
                TextField("NAME", text: .constant(""))
                    .textFieldStyle(PlainTextFieldStyle())
            )
            let roundedNode = makeNode(
                TextField("NAME", text: .constant(""))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            )
            let squareNode = makeNode(
                TextField("NAME", text: .constant(""))
                    .textFieldStyle(SquareBorderTextFieldStyle())
            )
            let defaultNode = makeNode(
                TextField("NAME", text: .constant(""))
                    .textFieldStyle(DefaultTextFieldStyle())
            )
            let inheritedNode = makeNode(
                VStack {
                    TextField("NAME", text: .constant(""))
                    SecureField("SECRET", text: .constant(""))
                }
                .textFieldStyle(.plain)
            )
            let readerNode = makeNode(TextFieldStyleReaderView().textFieldStyle(.squareBorder))

            XCTAssertEqual(plainNode.backgroundColor, .clear)
            XCTAssertEqual(plainNode.borderWidth, 0)
            XCTAssertEqual(plainNode.cornerRadius, 0)
            XCTAssertEqual(roundedNode.borderWidth, 1)
            XCTAssertEqual(roundedNode.cornerRadius, MacOSControlMetrics.Button.regularCornerRadius)
            XCTAssertEqual(squareNode.borderWidth, 1)
            XCTAssertEqual(squareNode.cornerRadius, 0)
            XCTAssertEqual(defaultNode.borderWidth, 1)
            XCTAssertEqual(inheritedNode.children[0].backgroundColor, .clear)
            XCTAssertEqual(inheritedNode.children[1].backgroundColor, .clear)
            XCTAssertEqual(readerNode.text, "SQUARE")
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
            XCTAssertEqual(maskedNode.children[0].text, "••••")

            maskedNode.onKeyDown?(KeyboardEvent(keyCode: 0x31))
            maskedNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))
            maskedNode.onKeyDown?(KeyboardEvent(keyCode: 0x5A, modifiers: [.shift]))

            XCTAssertEqual(value, "openZ")

            let updatedNode = makeNode(SecureField("PASSWORD", text: binding))

            XCTAssertEqual(updatedNode.children[0].text, "•••••")
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
            XCTAssertEqual(node.children.count, 1)
            guard let viewport = node.children.first else {
                XCTFail("The multiline editor must retain its viewport")
                return
            }
            XCTAssertEqual(viewport.scrollAxis, .vertical)
            XCTAssertTrue(viewport.clipsToBounds)
            XCTAssertNil(viewport.text)
            XCTAssertEqual(viewport.children.count, 1)
            guard let content = viewport.children.first else {
                XCTFail("The viewport must retain its text content")
                return
            }
            let fragments = content.children.filter { $0.text != nil }
            XCTAssertEqual(fragments.compactMap(\.text), ["hi"])
            XCTAssertEqual(node.accessibilityValue, "hi")
            XCTAssertNil(viewport.textStyle.maximumNumberOfLines)
            XCTAssertEqual(viewport.textStyle.lineBreakMode, .wrap)
            for fragment in fragments {
                XCTAssertFalse(fragment.isHidden)
                XCTAssertEqual(fragment.textStyle.maximumNumberOfLines, 1)
                XCTAssertEqual(fragment.textStyle.lineBreakMode, .clip)
            }

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x41, modifiers: [.shift]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x42))

            XCTAssertEqual(value, "hi\nAb")

            let updatedNode = makeNode(TextEditor(text: binding))

            XCTAssertEqual(updatedNode.children.count, 1)
            guard let updatedViewport = updatedNode.children.first else {
                XCTFail("The rebuilt multiline editor must retain its viewport")
                return
            }
            XCTAssertEqual(updatedViewport.scrollAxis, .vertical)
            XCTAssertTrue(updatedViewport.clipsToBounds)
            XCTAssertNil(updatedViewport.text)
            XCTAssertEqual(updatedViewport.children.count, 1)
            guard let updatedContent = updatedViewport.children.first else {
                XCTFail("The rebuilt viewport must retain its text content")
                return
            }
            let updatedFragments = updatedContent.children.filter { $0.text != nil }
            XCTAssertEqual(updatedFragments.compactMap(\.text), ["hi", "Ab"])
            XCTAssertEqual(updatedNode.accessibilityValue, "hi\nAb")
            for fragment in updatedFragments {
                XCTAssertFalse(fragment.isHidden)
                XCTAssertEqual(fragment.textStyle.maximumNumberOfLines, 1)
                XCTAssertEqual(fragment.textStyle.lineBreakMode, .clip)
            }
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
            XCTAssertEqual(
                gradientRoundedRectangle.backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
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
            XCTAssertEqual(
                inheritedGradientRectangle.children[0].children[0].backgroundGradient,
                .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
        }
    }

    func testRoundedRectangleCornerSizeInitializerMapsToRetainedRoundedFallback() async {
        await MainActor.run {
            let fillColor = Color(red: 0.2, green: 0.7, blue: 0.6, alpha: 1)
            let strokeColor = Color(red: 0.8, green: 0.4, blue: 0.3, alpha: 1)
            let shape = RoundedRectangle(cornerSize: CGSize(width: 6, height: 14), style: .continuous)

            XCTAssertEqual(shape.cornerSize, CGSize(width: 6, height: 14))
            XCTAssertEqual(shape.style, .continuous)

            let filledNode = makeNode(shape.fill(fillColor))
            XCTAssertEqual(filledNode.backgroundColor, fillColor)
            XCTAssertEqual(filledNode.cornerRadius, 14)

            let strokedNode = makeNode(
                RoundedRectangle(cornerSize: CGSize(width: -2, height: 9), style: .circular)
                    .strokeBorder(strokeColor, lineWidth: 2)
            )
            XCTAssertEqual(strokedNode.backgroundColor, .clear)
            XCTAssertEqual(strokedNode.borderColor, strokeColor)
            XCTAssertEqual(strokedNode.borderWidth, 2)
            XCTAssertEqual(strokedNode.cornerRadius, 9)

            let clippedNode = makeNode(Text("CLIP").clipShape(shape))
            XCTAssertTrue(clippedNode.clipsToBounds)
            XCTAssertEqual(clippedNode.cornerRadius, 14)
        }
    }

    func testShapeStaticFactoriesMapToRetainedBuiltInShapes() async {
        await MainActor.run {
            let fillColor = Color(red: 0.3, green: 0.5, blue: 0.8, alpha: 1)
            let roundedRectNode = makeNode(
                Text("CLIP").clipShape(.rect(cornerRadius: 8))
            )
            let cornerSizeNode = makeNode(
                RoundedRectangle.rect(cornerSize: CGSize(width: 4, height: 11)).fill(fillColor)
            )
            let unevenNode = makeNode(
                UnevenRoundedRectangle.rect(
                    topLeadingRadius: 2,
                    bottomLeadingRadius: 5,
                    bottomTrailingRadius: 12,
                    topTrailingRadius: 6
                )
                .fill(fillColor)
            )
            let capsuleNode = makeNode(Capsule.capsule.fill(fillColor).frame(width: 40, height: 20))
            let circleContentShapeNode = makeNode(Text("HIT").contentShape(.circle))
            let containerRelativeNode = makeNode(ContainerRelativeShape.containerRelative.fill(fillColor))
            let ellipseNode = makeNode(Ellipse.ellipse.strokeBorder(fillColor, lineWidth: 2))
            let rectNode = makeNode(Rectangle.rect.fill(fillColor))

            XCTAssertTrue(roundedRectNode.clipsToBounds)
            XCTAssertEqual(roundedRectNode.cornerRadius, 8)
            XCTAssertEqual(cornerSizeNode.backgroundColor, fillColor)
            XCTAssertEqual(cornerSizeNode.cornerRadius, 11)
            XCTAssertEqual(unevenNode.backgroundColor, fillColor)
            XCTAssertEqual(unevenNode.cornerRadius, 12)

            let retainedCapsuleNode = capsuleNode.children[0]
            retainedCapsuleNode.onLayout?(Rect(x: 0, y: 0, width: 40, height: 20))
            XCTAssertEqual(retainedCapsuleNode.cornerRadius, 10)
            XCTAssertEqual(
                circleContentShapeNode.contentShapes.first,
                RetainedContentShape(kinds: .interaction, style: .ellipse, eoFill: false, mask: false)
            )

            let maskedContentShapeNode = makeNode(Text("MASK").contentShape(.circle, mask: true))
            XCTAssertEqual(
                maskedContentShapeNode.contentShapes.first,
                RetainedContentShape(kinds: .interaction, style: .ellipse, eoFill: false, mask: true)
            )

            containerRelativeNode.onLayout?(Rect(x: 0, y: 0, width: 30, height: 10))
            XCTAssertEqual(containerRelativeNode.backgroundColor, fillColor)
            XCTAssertEqual(containerRelativeNode.cornerRadius, 5)
            ellipseNode.onLayout?(Rect(x: 0, y: 0, width: 24, height: 12))
            XCTAssertEqual(ellipseNode.borderColor, fillColor)
            XCTAssertEqual(ellipseNode.borderWidth, 2)
            XCTAssertEqual(ellipseNode.cornerRadius, 6)
            XCTAssertEqual(rectNode.backgroundColor, fillColor)
            XCTAssertEqual(rectNode.cornerRadius, 0)
        }
    }

    func testUnevenRoundedRectangleMapsToRetainedRoundedFallback() async {
        await MainActor.run {
            let fillColor = Color(red: 0.3, green: 0.7, blue: 0.9, alpha: 1)
            let strokeColor = Color(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)
            let radii = RectangleCornerRadii(
                topLeading: 4,
                bottomLeading: 10,
                bottomTrailing: 16,
                topTrailing: 6
            )
            let filledNode = makeNode(
                UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
                    .fill(fillColor)
            )
            let strokedNode = makeNode(
                UnevenRoundedRectangle(
                    topLeadingRadius: 3,
                    bottomLeadingRadius: 12,
                    bottomTrailingRadius: 5,
                    topTrailingRadius: 9,
                    style: .circular
                )
                .strokeBorder(strokeColor, style: StrokeStyle(lineWidth: 2, dashPattern: [2, 2]))
            )

            XCTAssertEqual(filledNode.backgroundColor, fillColor)
            XCTAssertEqual(filledNode.cornerRadius, 16)
            XCTAssertEqual(strokedNode.backgroundColor, .clear)
            XCTAssertEqual(strokedNode.borderColor, strokeColor)
            XCTAssertEqual(strokedNode.borderWidth, 2)
            XCTAssertEqual(strokedNode.borderStrokeStyle?.dashPattern, [2, 2])
            XCTAssertEqual(strokedNode.cornerRadius, 12)

            let clippedNode = makeNode(Text("CLIP").clipShape(UnevenRoundedRectangle(cornerRadii: radii)))
            XCTAssertTrue(clippedNode.clipsToBounds)
            XCTAssertEqual(clippedNode.cornerRadius, 16)

            let contentShapeNode = makeNode(Text("HIT").contentShape(UnevenRoundedRectangle(cornerRadii: radii)))
            XCTAssertEqual(
                contentShapeNode.contentShapes.first,
                RetainedContentShape(
                    kinds: .interaction,
                    style: .roundedRectangle(16),
                    eoFill: false
                )
            )
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
            XCTAssertEqual(strokeStyle.miterLimit, 3)
            XCTAssertEqual(inheritedStroke.backgroundColor, .clear)
            XCTAssertEqual(inheritedStroke.borderColor, inheritedColor)
            XCTAssertEqual(inheritedStroke.borderWidth, 6)
            XCTAssertEqual(inheritedStroke.borderStrokeStyle, strokeStyle)
            XCTAssertEqual(storedForegroundStroke.backgroundColor, .clear)
            XCTAssertEqual(storedForegroundStroke.borderColor, storedStroke)
            XCTAssertEqual(storedForegroundStroke.borderWidth, 3)
            XCTAssertEqual(storedForegroundStroke.borderStrokeStyle, StrokeStyle(lineWidth: 3, dashPattern: [2]))
            XCTAssertEqual(storedForegroundStroke.cornerRadius, 8)
            XCTAssertEqual(gradientStroke.backgroundColor, .clear)
            XCTAssertEqual(gradientStroke.borderColor, gradient.startColor)
            XCTAssertEqual(gradientStroke.borderGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(gradientStroke.borderWidth, 4)
            XCTAssertEqual(
                gradientStroke.borderStrokeStyle,
                StrokeStyle(lineWidth: 4, dashPattern: [], dashOffset: 0, lineCap: .square))
            XCTAssertEqual(gradientStroke.cornerRadius, 10)
            XCTAssertEqual(gradientStrokeBorder.borderColor, gradient.startColor)
            XCTAssertEqual(gradientStrokeBorder.borderGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(gradientStrokeBorder.borderWidth, 5)
            XCTAssertEqual(gradientStrokeBorder.borderStrokeStyle, StrokeStyle(lineWidth: 5, dashPattern: []))
            XCTAssertEqual(gradientStrokeBorder.cornerRadius, 7)
        }
    }

    func testShapeLineWidthOnlyStrokeOverloadsUseInheritedForegroundStyle() async {
        await MainActor.run {
            let inheritedColor = Color(red: 0.2, green: 0.7, blue: 0.9, alpha: 1)
            let root = renderedNode(
                VStack {
                    Rectangle()
                        .stroke(lineWidth: 4)
                        .frame(width: 24, height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(lineWidth: 3)
                        .frame(width: 26, height: 14)
                    AnyShape(Capsule())
                        .stroke(lineWidth: 2)
                        .frame(width: 28, height: 16)
                    Circle()
                        .inset(by: 2)
                        .strokeBorder(lineWidth: 5)
                        .frame(width: 30, height: 30)
                }
                .foregroundStyle(inheritedColor)
            )

            let rectangle = root.children[0].children[0]
            let roundedRectangle = root.children[1].children[0]
            let anyShape = root.children[2].children[0]
            let insetShape = root.children[3].children[0].children[0]

            XCTAssertEqual(rectangle.backgroundColor, .clear)
            XCTAssertEqual(rectangle.borderColor, inheritedColor)
            XCTAssertEqual(rectangle.borderWidth, 4)
            XCTAssertEqual(rectangle.borderStrokeStyle, StrokeStyle(lineWidth: 4, dashPattern: []))
            XCTAssertEqual(roundedRectangle.borderColor, inheritedColor)
            XCTAssertEqual(roundedRectangle.borderWidth, 3)
            XCTAssertEqual(roundedRectangle.cornerRadius, 6)
            XCTAssertEqual(anyShape.borderColor, inheritedColor)
            XCTAssertEqual(anyShape.borderWidth, 2)
            XCTAssertEqual(insetShape.borderColor, inheritedColor)
            XCTAssertEqual(insetShape.borderWidth, 5)
        }
    }

    func testShapeFillStyleOverloadsForwardToRetainedFillColors() async {
        await MainActor.run {
            let inheritedColor = Color(red: 0.6, green: 0.35, blue: 0.85, alpha: 1)
            let explicitColor = Color(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)
            let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
            let root = renderedNode(
                VStack {
                    Rectangle()
                        .fill(style: FillStyle(eoFill: true, antialiased: false))
                        .frame(width: 18, height: 10)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(explicitColor, style: FillStyle(antialiased: false))
                        .frame(width: 20, height: 12)
                    Circle()
                        .fill(gradient, style: FillStyle(eoFill: true))
                        .frame(width: 14, height: 14)
                    AnyShape(Ellipse())
                        .fill(.placeholder, style: FillStyle(eoFill: true, antialiased: false))
                        .frame(width: 22, height: 12)
                }
                .foregroundStyle(inheritedColor)
            )

            let inheritedFill = root.children[0].children[0]
            let colorFill = root.children[1].children[0]
            let gradientFill = root.children[2].children[0]
            let semanticFill = root.children[3].children[0]

            XCTAssertEqual(inheritedFill.backgroundColor, inheritedColor)
            XCTAssertEqual(colorFill.backgroundColor, explicitColor)
            XCTAssertEqual(colorFill.cornerRadius, 5)
            XCTAssertEqual(gradientFill.backgroundColor, gradient.startColor)
            XCTAssertEqual(gradientFill.backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(semanticFill.backgroundColor, PlaceholderTextShapeStyle().retainedFallbackColor)
            XCTAssertEqual(inheritedFill.clipFillStyle, RetainedClipFillStyle(eoFill: true, antialiased: false))
            XCTAssertEqual(colorFill.clipFillStyle, RetainedClipFillStyle(eoFill: false, antialiased: false))
            XCTAssertEqual(gradientFill.clipFillStyle, RetainedClipFillStyle(eoFill: true, antialiased: true))
            XCTAssertEqual(semanticFill.clipFillStyle, RetainedClipFillStyle(eoFill: true, antialiased: false))
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
            XCTAssertEqual(gradientCircle.backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
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

    func testContainerRelativeShapeMapsToRetainedDynamicRoundedShape() async {
        await MainActor.run {
            let fillColor = Color(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
            let strokeColor = Color(red: 0.9, green: 0.7, blue: 0.2, alpha: 1)
            let shapeNode = makeNode(
                ContainerRelativeShape()
                    .fill(fillColor)
                    .strokeBorder(strokeColor, style: StrokeStyle(lineWidth: 2, dashPattern: [3, 1]))
                    .frame(width: 80, height: 30)
            )

            let retainedShapeNode = shapeNode.children[0]
            XCTAssertEqual(retainedShapeNode.backgroundColor, .clear)
            XCTAssertEqual(retainedShapeNode.borderColor, strokeColor)
            XCTAssertEqual(retainedShapeNode.borderWidth, 2)
            XCTAssertEqual(retainedShapeNode.borderStrokeStyle?.dashPattern, [3, 1])

            retainedShapeNode.onLayout?(Rect(x: 0, y: 0, width: 80, height: 30))
            XCTAssertEqual(retainedShapeNode.cornerRadius, 15)

            let filledNode = makeNode(ContainerRelativeShape().fill(fillColor))
            XCTAssertEqual(filledNode.backgroundColor, fillColor)
            filledNode.onLayout?(Rect(x: 0, y: 0, width: 40, height: 40))
            XCTAssertEqual(filledNode.cornerRadius, 20)

            let clippedNode = makeNode(Text("CLIP").clipShape(ContainerRelativeShape()))
            XCTAssertTrue(clippedNode.clipsToBounds)
            clippedNode.onLayout?(Rect(x: 0, y: 0, width: 60, height: 20))
            XCTAssertEqual(clippedNode.cornerRadius, 10)

            let contentShapeNode = makeNode(Text("HIT").contentShape(ContainerRelativeShape()))
            XCTAssertEqual(
                contentShapeNode.contentShapes.first,
                RetainedContentShape(
                    kinds: .interaction,
                    style: .capsule,
                    eoFill: false
                )
            )
        }
    }

    func testAnyShapeErasesRetainedShapeRenderingAndMetadata() async {
        await MainActor.run {
            let fillColor = Color(red: 0.4, green: 0.7, blue: 0.2, alpha: 1)
            let strokeColor = Color(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)

            let delegatedNode = makeNode(
                AnyShape(RoundedRectangle(cornerRadius: 9).fill(fillColor))
            )
            XCTAssertEqual(delegatedNode.backgroundColor, fillColor)
            XCTAssertEqual(delegatedNode.cornerRadius, 9)

            let filledNode = makeNode(
                AnyShape(RoundedRectangle(cornerRadius: 12))
                    .fill(fillColor)
            )
            XCTAssertEqual(filledNode.backgroundColor, fillColor)
            XCTAssertEqual(filledNode.cornerRadius, 12)

            let strokedNode = makeNode(
                AnyShape(Capsule())
                    .strokeBorder(strokeColor, style: StrokeStyle(lineWidth: 3, dashPattern: [2, 1]))
                    .frame(width: 90, height: 30)
            )
            let retainedStrokeNode = strokedNode.children[0]
            XCTAssertEqual(retainedStrokeNode.backgroundColor, .clear)
            XCTAssertEqual(retainedStrokeNode.borderColor, strokeColor)
            XCTAssertEqual(retainedStrokeNode.borderWidth, 3)
            XCTAssertEqual(retainedStrokeNode.borderStrokeStyle?.dashPattern, [2, 1])
            retainedStrokeNode.onLayout?(Rect(x: 0, y: 0, width: 90, height: 30))
            XCTAssertEqual(retainedStrokeNode.cornerRadius, 15)

            let clippedNode = makeNode(Text("CLIP").clipShape(AnyShape(RoundedRectangle(cornerRadius: 11))))
            XCTAssertTrue(clippedNode.clipsToBounds)
            XCTAssertEqual(clippedNode.cornerRadius, 11)

            let contentShapeNode = makeNode(Text("HIT").contentShape(AnyShape(Circle())))
            XCTAssertEqual(
                contentShapeNode.contentShapes.first,
                RetainedContentShape(
                    kinds: .interaction,
                    style: .ellipse,
                    eoFill: false
                )
            )
        }
    }

    func testInsettableShapeMapsInsetToRetainedPaddingAndShapeFallback() async {
        await MainActor.run {
            let fillColor = Color(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)
            let strokeColor = Color(red: 0.8, green: 0.3, blue: 0.2, alpha: 1)

            let filledNode = makeNode(
                RoundedRectangle(cornerRadius: 12)
                    .inset(by: 4)
                    .fill(fillColor)
            )
            guard case .stack(let filledLayout) = filledNode.layoutMode else {
                return XCTFail("Expected inset shape to wrap retained shape in a padded stack")
            }
            XCTAssertEqual(filledLayout, .vertical(padding: .all(4), alignment: .stretch))
            XCTAssertEqual(filledNode.children[0].backgroundColor, fillColor)
            XCTAssertEqual(filledNode.children[0].cornerRadius, 8)

            let nestedNode = makeNode(
                Rectangle()
                    .inset(by: 2)
                    .inset(by: 3)
                    .fill(fillColor)
            )
            guard case .stack(let nestedLayout) = nestedNode.layoutMode else {
                return XCTFail("Expected nested inset shape to accumulate retained padding")
            }
            XCTAssertEqual(nestedLayout, .vertical(padding: .all(5), alignment: .stretch))
            XCTAssertEqual(nestedNode.children[0].backgroundColor, fillColor)

            let strokedNode = makeNode(
                Capsule()
                    .inset(by: 5)
                    .strokeBorder(strokeColor, style: StrokeStyle(lineWidth: 3, dashPattern: [4, 2]))
            )
            guard case .stack(let strokedLayout) = strokedNode.layoutMode else {
                return XCTFail("Expected stroked inset shape to wrap retained shape in a padded stack")
            }
            let retainedStrokeNode = strokedNode.children[0]
            XCTAssertEqual(strokedLayout, .vertical(padding: .all(5), alignment: .stretch))
            XCTAssertEqual(retainedStrokeNode.backgroundColor, .clear)
            XCTAssertEqual(retainedStrokeNode.borderColor, strokeColor)
            XCTAssertEqual(retainedStrokeNode.borderWidth, 3)
            XCTAssertEqual(retainedStrokeNode.borderStrokeStyle?.dashPattern, [4, 2])
            retainedStrokeNode.onLayout?(Rect(x: 0, y: 0, width: 50, height: 20))
            XCTAssertEqual(retainedStrokeNode.cornerRadius, 10)

            let contentShapeNode = makeNode(
                Text("HIT").contentShape(RoundedRectangle(cornerRadius: 10).inset(by: 3))
            )
            XCTAssertEqual(
                contentShapeNode.contentShapes.first,
                RetainedContentShape(
                    kinds: .interaction,
                    style: .roundedRectangle(7),
                    eoFill: false
                )
            )
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
            // `.rounded` is a UI design, so it resolves through the system UI
            // face at this run's optical size. The face names themselves are
            // `SystemUIFontFaceTests`' business; what this pins is the routing.
            XCTAssertEqual(node.textStyle.fontFamily, SystemUIFontFace.family(forPointSize: 18))
        }
    }

    func testNamedFontStylesMapToRetainedTextSizes() async {
        await MainActor.run {
            let titleNode = makeNode(Text("TITLE").font(.title))
            let title2Node = makeNode(Text("TITLE2").font(.title2))
            let headlineNode = makeNode(Text("HEADLINE").font(.headline))
            let captionNode = makeNode(Text("CAPTION").font(.caption))
            let caption2Node = makeNode(Text("CAPTION2").font(.caption2))

            // The macOS ramp (MacOSControlMetrics.Typography), not iOS.
            XCTAssertEqual(titleNode.textStyle.nativeFontSize, 22)
            XCTAssertEqual(titleNode.textStyle.scale, 2.2)
            XCTAssertEqual(title2Node.textStyle.nativeFontSize, 17)
            XCTAssertEqual(headlineNode.textStyle.nativeFontSize, 13)
            XCTAssertEqual(headlineNode.textStyle.weight, .semibold)
            // `caption` is 11: the smallest string a reader is expected to
            // read. 10 survives as `caption2`, the axis-label role.
            XCTAssertEqual(captionNode.textStyle.nativeFontSize, 11)
            XCTAssertEqual(caption2Node.textStyle.nativeFontSize, 10)
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

            XCTAssertEqual(titleNode.textStyle.nativeFontSize, 22)
            XCTAssertEqual(titleNode.textStyle.weight, .bold)
            XCTAssertEqual(titleNode.textStyle.fontFamily, "Cascadia Mono")
            XCTAssertEqual(headlineNode.textStyle.nativeFontSize, 13)
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
            XCTAssertEqual(inheritedNode.children[1].textStyle.nativeFontSize, Font.body.size)
            XCTAssertEqual(inheritedNode.children[1].textStyle.weight, .regular)
            XCTAssertEqual(optionalNode.textStyle.nativeFontSize, 16)
            XCTAssertEqual(optionalNode.textStyle.weight, .semibold)
            XCTAssertEqual(environmentNode.textStyle.nativeFontSize, 18)
            XCTAssertEqual(environmentNode.textStyle.fontFamily, "Cascadia Mono")
            XCTAssertEqual(readerNode.text, "FONT")
        }
    }

    @MainActor
    private static func assertNativeFontSize(
        _ node: ViewNode, _ expectedSize: Double, file: StaticString = #filePath, line: UInt = #line
    ) {
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

    func testScaledMetricReadsDynamicTypeScaleFromViewContext() async {
        await MainActor.run {
            struct ScaledMetricReaderView: View {
                @ScaledMetric var padding = 10.0
                @ScaledMetric(relativeTo: .caption) var captionSpacing = 4.0

                var body: some View {
                    Text(String(format: "%.1f %.1f", padding, captionSpacing))
                }
            }

            let defaultNode = makeNode(ScaledMetricReaderView())
            let scaledNode = makeNode(
                ScaledMetricReaderView()
                    .dynamicTypeSize(.xxLarge)
            )

            XCTAssertEqual(defaultNode.text, "10.0 4.0")
            XCTAssertEqual(scaledNode.text, "12.4 5.0")
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
            XCTAssertEqual(textNode.textStyle.fontFamily, SystemUIFontFace.family(forPointSize: 14))
        }
    }

    func testFontWidthMapsToRetainedTextMetadata() async {
        await MainActor.run {
            struct FontWidthReaderView: View {
                @Environment(\.fontWidth) var fontWidth

                var body: some View {
                    Text(fontWidth == .expanded ? "EXPANDED" : fontWidth == nil ? "NONE" : "OTHER")
                }
            }

            let fontNode = makeNode(
                Text("COMPRESSED")
                    .font(.system(size: 18, weight: .semibold).width(.compressed))
            )
            let textNode = makeNode(
                Text("CONDENSED")
                    .fontWidth(.condensed)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                    Text("RESET")
                        .fontWidth(nil)
                }
                .fontWidth(.expanded)
            )
            let combinedNode = makeNode(
                Text("LEFT").fontWidth(.condensed)
                    + Text("RIGHT").fontWidth(.expanded)
            )
            let fieldNode = makeNode(
                TextField("NAME", text: .constant("VALUE"))
                    .fontWidth(.compressed)
            )
            let environmentNode = makeNode(
                Text("ENVIRONMENT")
                    .environment(\.fontWidth, Font.Width.condensed)
            )
            let readerNode = makeNode(
                FontWidthReaderView()
                    .fontWidth(.expanded)
            )

            XCTAssertEqual(fontNode.textStyle.fontWidth, .compressed)
            XCTAssertEqual(fontNode.textStyle.nativeFontSize, 18)
            XCTAssertEqual(fontNode.textStyle.weight, .semibold)
            XCTAssertEqual(textNode.textStyle.fontWidth, .condensed)
            XCTAssertEqual(inheritedNode.children[0].textStyle.fontWidth, .expanded)
            XCTAssertEqual(inheritedNode.children[1].textStyle.fontWidth, .standard)
            XCTAssertEqual(combinedNode.textStyle.fontWidth, .condensed)
            XCTAssertEqual(fieldNode.children[0].textStyle.fontWidth, .compressed)
            XCTAssertEqual(environmentNode.textStyle.fontWidth, .condensed)
            XCTAssertEqual(readerNode.text, "EXPANDED")
        }
    }

    func testFontFeatureConveniencesMapToRetainedTextMetadata() async {
        await MainActor.run {
            let boldNode = makeNode(Text("BOLD").font(.system(size: 16).bold()))
            let regularNode = makeNode(Text("REGULAR").font(.system(size: 16, weight: .bold).bold(false)))
            let italicNode = makeNode(Text("ITALIC").font(.system(size: 16).italic()))
            let nonItalicNode = makeNode(Text("PLAIN").font(.system(size: 16).italic(false)).italic(false))
            let digitsNode = makeNode(Text("123").font(.system(size: 16).monospacedDigit()))
            let smallCapsNode = makeNode(Text("Caps").font(.system(size: 16).smallCaps()))
            let lowercaseSmallCapsNode = makeNode(Text("Caps").font(.system(size: 16).lowercaseSmallCaps()))
            let uppercaseSmallCapsNode = makeNode(Text("Caps").font(.system(size: 16).uppercaseSmallCaps()))
            let disabledSmallCapsNode = makeNode(
                Text("Caps").font(.system(size: 16).smallCaps().smallCaps(false))
            )
            let inheritedInputNode = makeNode(
                TextField("CODE", text: .constant("abc123"))
                    .font(.system(size: 16).italic().monospacedDigit().smallCaps())
            )

            XCTAssertEqual(boldNode.textStyle.weight, .bold)
            XCTAssertEqual(regularNode.textStyle.weight, .regular)
            XCTAssertTrue(italicNode.textStyle.isItalic)
            XCTAssertFalse(nonItalicNode.textStyle.isItalic)
            XCTAssertTrue(digitsNode.textStyle.monospacedDigits)
            XCTAssertTrue(smallCapsNode.textStyle.lowercaseSmallCaps)
            XCTAssertTrue(smallCapsNode.textStyle.uppercaseSmallCaps)
            XCTAssertTrue(lowercaseSmallCapsNode.textStyle.lowercaseSmallCaps)
            XCTAssertFalse(lowercaseSmallCapsNode.textStyle.uppercaseSmallCaps)
            XCTAssertFalse(uppercaseSmallCapsNode.textStyle.lowercaseSmallCaps)
            XCTAssertTrue(uppercaseSmallCapsNode.textStyle.uppercaseSmallCaps)
            XCTAssertFalse(disabledSmallCapsNode.textStyle.lowercaseSmallCaps)
            XCTAssertFalse(disabledSmallCapsNode.textStyle.uppercaseSmallCaps)
            XCTAssertTrue(inheritedInputNode.children[0].textStyle.isItalic)
            XCTAssertTrue(inheritedInputNode.children[0].textStyle.monospacedDigits)
            XCTAssertTrue(inheritedInputNode.children[0].textStyle.lowercaseSmallCaps)
            XCTAssertTrue(inheritedInputNode.children[0].textStyle.uppercaseSmallCaps)
        }
    }

    func testSerifFontDesignMapsToRetainedFontFamily() async {
        await MainActor.run {
            let directNode = makeNode(
                Text("SERIF")
                    .font(.system(size: 18, weight: .regular, design: .serif))
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                    Text("DEFAULT")
                        .fontDesign(.default)
                }
                .font(.system(size: 16, weight: .bold))
                .fontDesign(.serif)
            )
            let styleNode = makeNode(
                Text("TITLE")
                    .font(.system(.title, design: .serif, weight: .semibold))
            )

            XCTAssertEqual(directNode.textStyle.fontFamily, "Georgia")
            XCTAssertEqual(directNode.textStyle.nativeFontSize, 18)
            XCTAssertEqual(inheritedNode.children[0].textStyle.fontFamily, "Georgia")
            XCTAssertEqual(inheritedNode.children[0].textStyle.nativeFontSize, 16)
            XCTAssertEqual(inheritedNode.children[0].textStyle.weight, .bold)
            XCTAssertEqual(
                inheritedNode.children[1].textStyle.fontFamily, SystemUIFontFace.family(forPointSize: 16))
            XCTAssertEqual(styleNode.textStyle.fontFamily, "Georgia")
            XCTAssertEqual(styleNode.textStyle.weight, .semibold)
        }
    }

    func testCustomFontConstructorsMapFamilyAndDynamicScaling() async {
        await MainActor.run {
            let customNode = makeNode(
                Text("CUSTOM")
                    .font(.custom("Aptos", size: 18))
                    .dynamicTypeSize(.xxLarge)
            )
            let fixedNode = makeNode(
                Text("FIXED")
                    .font(.custom("Aptos", fixedSize: 18))
                    .dynamicTypeSize(.xxLarge)
            )
            let relativeNode = makeNode(
                Text("RELATIVE")
                    .font(.custom("Georgia", size: 12, relativeTo: .caption))
            )
            let relativeHeadlineNode = makeNode(
                Text("RELATIVE HEADLINE")
                    .font(.custom("Aptos", size: 15, relativeTo: .headline))
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                }
                .font(.custom("Cascadia Code", fixedSize: 16))
                .dynamicTypeSize(.accessibility1)
            )

            XCTAssertEqual(customNode.textStyle.fontFamily, "Aptos")
            XCTAssertEqual(customNode.textStyle.nativeFontSize, 18 * DynamicTypeSize.xxLarge.retainedFontScale)
            XCTAssertEqual(fixedNode.textStyle.fontFamily, "Aptos")
            XCTAssertEqual(fixedNode.textStyle.nativeFontSize, 18)
            XCTAssertEqual(relativeNode.textStyle.fontFamily, "Georgia")
            XCTAssertEqual(relativeNode.textStyle.nativeFontSize, 12)
            XCTAssertEqual(relativeHeadlineNode.textStyle.fontFamily, "Aptos")
            XCTAssertEqual(relativeHeadlineNode.textStyle.nativeFontSize, 15)
            // The relative size is the caller's; only the *style* is inherited.
            XCTAssertEqual(relativeHeadlineNode.textStyle.weight, .semibold)
            // `relativeTo:` inherits the *style* (weight, leading mode), not
            // the size — and leading is now proportional, so a 15pt relative
            // headline leads for 15pt, not for headline's 13.
            XCTAssertEqual(
                relativeHeadlineNode.textStyle.lineSpacing,
                Font.custom("Aptos", size: 15, relativeTo: .headline).resolvedLineSpacing)
            XCTAssertEqual(inheritedNode.children[0].textStyle.fontFamily, "Cascadia Code")
            XCTAssertEqual(inheritedNode.children[0].textStyle.nativeFontSize, 16)
        }
    }

    func testTextScaleModifiersMapToRetainedTextSizing() async {
        await MainActor.run {
            var fieldValue = "VALUE"
            let fieldBinding = Binding<String>(
                get: { fieldValue },
                set: { fieldValue = $0 }
            )
            let baseFont = Font.system(size: 20)
            let expectedSecondarySize = 20 * Text.Scale.secondary.retainedMultiplier

            let directNode = makeNode(
                Text("SECONDARY")
                    .font(baseFont)
                    .textScale(.secondary)
            )
            let disabledNode = makeNode(
                Text("DISABLED")
                    .font(baseFont)
                    .textScale(.secondary, isEnabled: false)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                        .font(baseFont)
                    Text("RESET")
                        .font(baseFont)
                        .textScale(.default)
                    TextField("FIELD", text: fieldBinding)
                        .font(baseFont)
                }
                .textScale(.secondary)
            )

            XCTAssertEqual(directNode.textStyle.nativeFontSize, expectedSecondarySize)
            XCTAssertEqual(directNode.textStyle.scale, expectedSecondarySize / 10)
            XCTAssertEqual(disabledNode.textStyle.nativeFontSize, 20)
            XCTAssertEqual(inheritedNode.children[0].textStyle.nativeFontSize, expectedSecondarySize)
            XCTAssertEqual(inheritedNode.children[1].textStyle.nativeFontSize, 20)
            XCTAssertEqual(inheritedNode.children[2].children[0].textStyle.nativeFontSize, expectedSecondarySize)
        }
    }

    func testTextRendererCompatibilityShimAcceptsCustomRenderer() async {
        struct ProbeTextAttribute: TextAttribute {}

        struct ProbeTextRenderer: TextRenderer {
            func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
                _ = layout
                _ = ctx
            }
        }

        await MainActor.run {
            let renderer = ProbeTextRenderer()
            let attribute = ProbeTextAttribute()
            var context = GraphicsContext()

            renderer.draw(layout: Text.Layout(), in: &context)

            let measuredSize = renderer.sizeThatFits(
                proposal: ProposedViewSize(width: 80, height: 24),
                text: TextProxy()
            )
            let node = makeNode(
                Text("RENDERED")
                    .textRenderer(renderer)
            )
            let baselineNode = makeNode(Text("RENDERED"))

            XCTAssertEqual(renderer.displayPadding, EdgeInsets())
            XCTAssertEqual(measuredSize, CGSize(width: 80, height: 24))
            XCTAssertEqual(node.text, "RENDERED")
            XCTAssertEqual(node.textStyle.nativeFontSize, baselineNode.textStyle.nativeFontSize)
            _ = attribute
        }
    }

    func testFontLeadingMapsToRetainedLineSpacing() async {
        await MainActor.run {
            let tightNode = makeNode(
                Text("TIGHT")
                    .font(.system(size: 18).leading(.tight))
            )
            let looseNode = makeNode(
                Text("LOOSE")
                    .font(.custom("Aptos", size: 18).leading(.loose))
            )
            let weightedNode = makeNode(
                Text("BOLD")
                    .font(Font.custom("Aptos", size: 18).leading(.loose).weight(.bold))
            )
            let explicitLineSpacingNode = makeNode(
                Text("EXPLICIT")
                    .font(.system(size: 18).leading(.loose))
                    .lineSpacing(3)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                    Text("RESET")
                        .font(.system(size: 18).leading(.standard))
                }
                .font(.system(size: 18).leading(.tight))
            )

            // Leading is a fraction of the point size, not an absolute
            // pixel count: 18pt tight/standard/loose are 18 x 0.08 / 0.22 / 0.40.
            XCTAssertEqual(tightNode.textStyle.lineSpacing, 18 * 0.08, accuracy: 0.001)
            XCTAssertEqual(looseNode.textStyle.lineSpacing, 18 * 0.40, accuracy: 0.001)
            XCTAssertEqual(weightedNode.textStyle.lineSpacing, 18 * 0.40, accuracy: 0.001)
            XCTAssertEqual(weightedNode.textStyle.weight, .bold)
            XCTAssertEqual(explicitLineSpacingNode.textStyle.lineSpacing, 3)
            XCTAssertEqual(inheritedNode.children[0].textStyle.lineSpacing, 18 * 0.08, accuracy: 0.001)
            XCTAssertEqual(inheritedNode.children[1].textStyle.lineSpacing, 18 * 0.22, accuracy: 0.001)
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
            let resetExplicitNode = makeNode(
                Text("RESET")
                    .fontWeight(.bold)
                    .fontWeight(nil)
            )
            let inheritedResetNode = makeNode(
                VStack {
                    Text("INHERITED")
                        .fontWeight(nil)
                }
                .fontWeight(.semibold)
            )

            XCTAssertEqual(boldNode.textStyle.weight, .bold)
            XCTAssertEqual(heavyNode.textStyle.weight, .bold)
            XCTAssertEqual(resetExplicitNode.textStyle.weight, .regular)
            XCTAssertEqual(inheritedResetNode.children[0].textStyle.weight, .semibold)
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
                    Text("EF")
                        .tracking(7)
                }
                .lineSpacing(5)
                .kerning(2)
            )
            let baselineNode = makeNode(
                VStack {
                    Text("RAISED")
                    Text("LOWERED")
                        .baselineOffset(-3)
                }
                .baselineOffset(6)
            )

            XCTAssertEqual(spacedNode.textStyle.lineSpacing, 6)
            XCTAssertEqual(spacedNode.textStyle.letterSpacing, 4)
            XCTAssertEqual(trackingNode.textStyle.letterSpacing, 3)
            XCTAssertEqual(inheritedNode.children[0].textStyle.lineSpacing, 5)
            XCTAssertEqual(inheritedNode.children[0].textStyle.letterSpacing, 2)
            XCTAssertEqual(inheritedNode.children[1].textStyle.lineSpacing, 8)
            XCTAssertEqual(inheritedNode.children[1].textStyle.letterSpacing, 2)
            XCTAssertEqual(inheritedNode.children[2].textStyle.letterSpacing, 7)
            XCTAssertEqual(baselineNode.children[0].transform, Transform2D.translation(x: 0, y: -6))
            XCTAssertEqual(baselineNode.children[1].transform, Transform2D.translation(x: 0, y: 3))

            let defaultMultilineHeight = makeNode(Text("A\nB")).intrinsicContentSize().height
            let spacedHeight = spacedNode.intrinsicContentSize().height
            XCTAssertGreaterThan(spacedHeight, defaultMultilineHeight)
        }
    }

    func testMinimumScaleFactorBridgesToRetainedTextStyleAndEnvironment() async {
        await MainActor.run {
            let scaledNode = makeNode(
                Text("SCALE")
                    .minimumScaleFactor(0.5)
            )
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                    Text("EXPLICIT")
                        .minimumScaleFactor(0.25)
                }
                .minimumScaleFactor(0.75)
            )
            let clampedLowNode = makeNode(Text("LOW").minimumScaleFactor(-0.25))
            let clampedHighNode = makeNode(Text("HIGH").minimumScaleFactor(1.25))

            XCTAssertEqual(scaledNode.textStyle.minimumScaleFactor, 0.5)
            XCTAssertEqual(inheritedNode.children[0].textStyle.minimumScaleFactor, 0.75)
            XCTAssertEqual(inheritedNode.children[1].textStyle.minimumScaleFactor, 0.25)
            XCTAssertEqual(clampedLowNode.textStyle.minimumScaleFactor, 0)
            XCTAssertEqual(clampedHighNode.textStyle.minimumScaleFactor, 1)
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
            XCTAssertEqual(textNode.textStyle.minimumNumberOfLines, 2)
            XCTAssertTrue(textNode.textStyle.reservesLineLimitSpace)
            XCTAssertEqual(inheritedNode.children[0].textStyle.maximumNumberOfLines, 3)
            XCTAssertEqual(inheritedNode.children[0].textStyle.minimumNumberOfLines, 3)
            XCTAssertTrue(inheritedNode.children[0].textStyle.reservesLineLimitSpace)
            XCTAssertEqual(inheritedNode.children[1].textStyle.maximumNumberOfLines, 1)
            XCTAssertNil(inheritedNode.children[1].textStyle.minimumNumberOfLines)
            XCTAssertFalse(inheritedNode.children[1].textStyle.reservesLineLimitSpace)
        }
    }

    func testLineLimitRangeOverloadsMapToRetainedMinimumAndMaximumLines() async {
        await MainActor.run {
            let maximumNode = makeNode(Text("MAX").lineLimit(...3))
            let minimumNode = makeNode(Text("MIN").lineLimit(2...))
            let boundedNode = makeNode(Text("BOUNDED").lineLimit(2...4))
            let inheritedNode = makeNode(
                VStack {
                    Text("INHERITED")
                    Text("RESET")
                        .lineLimit(nil)
                    Text("MAX")
                        .lineLimit(...1)
                }
                .lineLimit(2...)
            )

            XCTAssertEqual(maximumNode.textStyle.maximumNumberOfLines, 3)
            XCTAssertNil(maximumNode.textStyle.minimumNumberOfLines)
            XCTAssertEqual(minimumNode.textStyle.maximumNumberOfLines, nil)
            XCTAssertEqual(minimumNode.textStyle.minimumNumberOfLines, 2)
            XCTAssertEqual(boundedNode.textStyle.maximumNumberOfLines, 4)
            XCTAssertEqual(boundedNode.textStyle.minimumNumberOfLines, 2)
            XCTAssertEqual(inheritedNode.children[0].textStyle.maximumNumberOfLines, nil)
            XCTAssertEqual(inheritedNode.children[0].textStyle.minimumNumberOfLines, 2)
            XCTAssertEqual(inheritedNode.children[1].textStyle.maximumNumberOfLines, nil)
            XCTAssertEqual(inheritedNode.children[1].textStyle.minimumNumberOfLines, nil)
            XCTAssertEqual(inheritedNode.children[2].textStyle.maximumNumberOfLines, 1)
            XCTAssertEqual(inheritedNode.children[2].textStyle.minimumNumberOfLines, nil)
        }
    }

    func testTextEnvironmentValuesBridgeRetainedTextStyle() async {
        await MainActor.run {
            struct TextEnvironmentReaderView: View {
                @Environment(\.multilineTextAlignment) var alignment
                @Environment(\.lineLimit) var lineLimit
                @Environment(\.truncationMode) var truncationMode
                @Environment(\.minimumScaleFactor) var minimumScaleFactor
                @Environment(\.allowsTightening) var allowsTightening
                @Environment(\.textCase) var textCase
                @Environment(\.legibilityWeight) var legibilityWeight

                var body: some View {
                    Text(
                        alignment == .trailing
                            && lineLimit == 2
                            && truncationMode == .middle
                            && minimumScaleFactor == 0.5
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
                    .environment(\.minimumScaleFactor, 0.5)
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
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .textCase(.uppercase)
                    .legibilityWeight(.bold)
            )

            XCTAssertEqual(environmentNode.text, "MIXED")
            XCTAssertEqual(environmentNode.textStyle.alignment, .trailing)
            XCTAssertEqual(environmentNode.textStyle.maximumNumberOfLines, 2)
            XCTAssertEqual(environmentNode.textStyle.lineBreakMode, .truncateMiddle)
            XCTAssertEqual(environmentNode.textStyle.minimumScaleFactor, 0.5)
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
                    .strikethrough(color: .red)
            )
            let disabledNode = makeNode(
                Text("PLAIN")
                    .underline(false)
                    .strikethrough(false, color: .red)
            )

            XCTAssertTrue(decoratedNode.textStyle.underline)
            XCTAssertEqual(decoratedNode.textStyle.underlineColor, .blue)
            XCTAssertTrue(decoratedNode.textStyle.strikethrough)
            XCTAssertEqual(decoratedNode.textStyle.strikethroughColor, .red)
            XCTAssertFalse(disabledNode.textStyle.underline)
            XCTAssertNil(disabledNode.textStyle.underlineColor)
            XCTAssertFalse(disabledNode.textStyle.strikethrough)
            XCTAssertNil(disabledNode.textStyle.strikethroughColor)
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
            XCTAssertEqual(node.children[0].textStyle.fontFamily, SystemUIFontFace.family(forPointSize: 18))

            XCTAssertEqual(node.children[1].textStyle.color, inheritedColor)
            // `.font(nil)` clears the ambient font to the system default.
            XCTAssertEqual(node.children[1].textStyle.nativeFontSize, Font.body.size)
            XCTAssertEqual(node.children[1].textStyle.weight, .regular)
            XCTAssertEqual(
                node.children[1].textStyle.fontFamily, SystemUIFontFace.family(forPointSize: Font.body.size))

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
            let prominentSecondaryNode = makeNode(
                Text("PROMINENT")
                    .foregroundStyle(.secondary)
                    .environment(\.backgroundProminence, .increased)
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
            // `.increased` background prominence promotes secondary to
            // primary and rebases the ladder on the selection's own content
            // colour: over a filled selection, content stops being secondary
            // *and* stops taking the appearance's base.
            XCTAssertEqual(
                prominentSecondaryNode.textStyle.color,
                ControlPalette.darkStandard.selectedContentLabel)
            XCTAssertEqual(readerNode.text, "INCREASED")
            XCTAssertEqual(gradientNode.textStyle.color, inDarkAppearance(gradient.startColor))
        }
    }

    func testShapeStyleAndAnyShapeStyleBridgeToRetainedForegroundStyle() async {
        await MainActor.run {
            func retainedStyle<S: ShapeStyle>(_ style: S) -> ForegroundStyle {
                style.retainedForegroundStyle
            }

            let storedColor = Color(red: 0.2, green: 0.6, blue: 0.4, alpha: 1)
            let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
            let erasedSecondary = AnyShapeStyle(HierarchicalShapeStyle.secondary)
            let erasedGradient = AnyShapeStyle(gradient)

            XCTAssertEqual(retainedStyle(storedColor), .color(storedColor))
            XCTAssertEqual(retainedStyle(gradient), .linearGradient(gradient))
            XCTAssertEqual(retainedStyle(erasedSecondary), .color(.secondary))
            XCTAssertEqual(ForegroundStyle(storedColor), .color(storedColor))
            XCTAssertEqual(ForegroundStyle(gradient), .linearGradient(gradient))
            XCTAssertEqual(ForegroundStyle(erasedSecondary), .color(.secondary))

            let textNode = makeNode(Text("STYLE").foregroundStyle(erasedSecondary))
            let inheritedGradientNode = makeNode(
                VStack {
                    Text("GRADIENT")
                }
                .foregroundStyle(erasedGradient)
            )
            let filledNode = makeNode(Rectangle().fill(erasedSecondary))
            let strokedNode = makeNode(Capsule().strokeBorder(erasedGradient, lineWidth: 2))

            XCTAssertEqual(textNode.textStyle.color, .secondary)
            XCTAssertEqual(
                inheritedGradientNode.children[0].textStyle.color, inDarkAppearance(gradient.startColor))
            XCTAssertEqual(filledNode.backgroundColor, .secondary)
            XCTAssertEqual(strokedNode.borderColor, gradient.startColor)
            XCTAssertEqual(strokedNode.borderGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(strokedNode.borderWidth, 2)
        }
    }

    func testHierarchicalShapeStylesMapToRetainedSemanticFallbacks() async {
        await MainActor.run {
            XCTAssertEqual(HierarchicalShapeStyle.primary.retainedFallbackColor, .primary)
            XCTAssertEqual(HierarchicalShapeStyle.secondary.retainedFallbackColor, .secondary)
            // The rungs *are* the semantic label colours, so a
            // `.foregroundStyle(.tertiary)` survives as something the
            // appearance resolver can still recognise. They used to be three
            // opaque blue-slate literals unrelated to `.primary`/`.secondary`.
            XCTAssertEqual(HierarchicalShapeStyle.tertiary.retainedFallbackColor, .tertiary)
            XCTAssertEqual(HierarchicalShapeStyle.quaternary.retainedFallbackColor, .quaternary)
            XCTAssertEqual(HierarchicalShapeStyle.quinary.retainedFallbackColor, .quinary)
            XCTAssertEqual(
                ForegroundStyle(HierarchicalShapeStyle.tertiary),
                .color(HierarchicalShapeStyle.tertiary.retainedFallbackColor))

            let tertiaryTextNode = makeNode(Text("TERTIARY").foregroundStyle(.tertiary))
            let quaternaryBackgroundNode = makeNode(Text("BACKGROUND").background(.quaternary))
            let quinaryOverlayNode = renderedNode(
                Text("OVERLAY")
                    .frame(width: 80, height: 32)
                    .overlay(.quinary, alignment: .center)
            )
            let filledShapeNode = makeNode(Rectangle().fill(.tertiary))
            let strokedShapeNode = makeNode(Capsule().strokeBorder(.quaternary, lineWidth: 2))
            let erasedStyle = AnyShapeStyle(HierarchicalShapeStyle.quinary)

            XCTAssertEqual(tertiaryTextNode.textStyle.color, HierarchicalShapeStyle.tertiary.retainedFallbackColor)
            // A `.quaternary` *background* is a bar, not a shade: it resolves
            // to the page tone in both appearances and lets the hairline above
            // it carry the edge (docs/MacOSDesignParity.md). The label
            // resolution of the rung is untouched.
            XCTAssertEqual(
                quaternaryBackgroundNode.backgroundColor, ControlPalette.darkStandard.windowBackground)
            XCTAssertEqual(firstText(in: quaternaryBackgroundNode.children[0]), "BACKGROUND")
            XCTAssertEqual(
                quinaryOverlayNode.children[1].backgroundColor, HierarchicalShapeStyle.quinary.retainedFallbackColor)
            XCTAssertEqual(quinaryOverlayNode.children[1].frame, Rect(x: 0, y: 0, width: 80, height: 32))
            XCTAssertEqual(filledShapeNode.backgroundColor, HierarchicalShapeStyle.tertiary.retainedFallbackColor)
            XCTAssertEqual(strokedShapeNode.borderColor, HierarchicalShapeStyle.quaternary.retainedFallbackColor)
            XCTAssertEqual(strokedShapeNode.borderWidth, 2)
            XCTAssertEqual(
                erasedStyle.retainedForegroundStyle, .color(HierarchicalShapeStyle.quinary.retainedFallbackColor))
        }
    }

    func testGenericShapeStyleOverloadsMapToRetainedForegroundStyle() async {
        struct TestShapeStyle: ShapeStyle {
            let retainedForegroundStyle: ForegroundStyle
        }

        await MainActor.run {
            let color = Color(red: 0.2, green: 0.7, blue: 0.5, alpha: 1)
            let gradient = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
            let colorStyle = TestShapeStyle(retainedForegroundStyle: .color(color))
            let gradientStyle = TestShapeStyle(retainedForegroundStyle: .linearGradient(gradient))

            let textNode = makeNode(Text("STYLE").foregroundStyle(colorStyle))
            let labelNode = makeNode(Label("LABEL", systemImage: "star").foregroundStyle(colorStyle))
            let inheritedNode = makeNode(
                VStack {
                    Text("GRADIENT")
                }
                .foregroundStyle(gradientStyle, colorStyle)
            )
            let backgroundNode = makeNode(Text("BACKGROUND").background(gradientStyle))
            let overlayNode = renderedNode(
                Text("OVERLAY")
                    .frame(width: 80, height: 32)
                    .overlay(colorStyle, alignment: .bottomTrailing)
            )
            let borderNode = makeNode(Text("BORDER").border(gradientStyle, width: 4, cornerRadius: 6))
            let filledNode = makeNode(Rectangle().fill(colorStyle))
            let strokedNode = makeNode(RoundedRectangle(cornerRadius: 8).stroke(gradientStyle, lineWidth: 3))
            let strokeStyleNode = makeNode(
                Capsule().strokeBorder(colorStyle, style: StrokeStyle(lineWidth: 5, dash: [2]))
            )
            let anyShapeNode = makeNode(AnyShape(Circle()).fill(gradientStyle))
            let insetShapeNode = makeNode(Circle().inset(by: 2).strokeBorder(colorStyle, lineWidth: 2))

            XCTAssertEqual(textNode.textStyle.color, color)
            XCTAssertEqual(labelNode.children[0].textStyle.color, color)
            XCTAssertEqual(labelNode.children[1].textStyle.color, color)
            XCTAssertEqual(
                inheritedNode.children[0].textStyle.color, inDarkAppearance(gradient.startColor))
            XCTAssertEqual(backgroundNode.backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(overlayNode.children[1].backgroundColor, color)
            XCTAssertEqual(overlayNode.children[1].frame, Rect(x: 0, y: 0, width: 80, height: 32))
            XCTAssertEqual(borderNode.borderColor, gradient.startColor)
            XCTAssertEqual(borderNode.borderGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(borderNode.borderWidth, 4)
            XCTAssertEqual(borderNode.cornerRadius, 6)
            XCTAssertEqual(filledNode.backgroundColor, color)
            XCTAssertEqual(strokedNode.borderColor, gradient.startColor)
            XCTAssertEqual(strokedNode.borderGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(strokedNode.borderWidth, 3)
            XCTAssertEqual(strokeStyleNode.borderColor, color)
            XCTAssertEqual(strokeStyleNode.borderWidth, 5)
            XCTAssertEqual(anyShapeNode.backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(insetShapeNode.children[0].borderColor, color)
            XCTAssertEqual(insetShapeNode.children[0].borderWidth, 2)
        }
    }

    func testShapeStyleOpacityAppliesToRetainedColorAndGradientFills() async {
        await MainActor.run {
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.8),
                    Color(red: 0.8, green: 0.2, blue: 0.4, alpha: 0.4),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            let textNode = makeNode(
                Text("SECONDARY")
                    .foregroundStyle(HierarchicalShapeStyle.secondary.opacity(0.25))
            )
            let backgroundNode = makeNode(
                Text("GRADIENT")
                    .background(AnyView(gradient).opacity(0.5))
            )
            let overlayNode = renderedNode(
                Text("CLAMPED")
                    .frame(width: 70, height: 24)
                    .overlay(LinkShapeStyle().opacity(2))
            )
            let fillNode = makeNode(Rectangle().fill(FillShapeStyle().opacity(-1)))

            // `.secondary.opacity(0.25)` multiplies the rung's own alpha.
            XCTAssertEqual(
                textNode.textStyle.color, Color.secondary.retainedWithMultipliedOpacity(0.25))
            XCTAssertEqual(
                backgroundNode.backgroundGradient?.startColor, Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.4))
            XCTAssertEqual(
                backgroundNode.backgroundGradient?.endColor, Color(red: 0.8, green: 0.2, blue: 0.4, alpha: 0.2))
            XCTAssertEqual(overlayNode.children[1].backgroundColor, LinkShapeStyle().retainedFallbackColor)
            XCTAssertEqual(fillNode.backgroundColor, Color(red: 1, green: 1, blue: 1, alpha: 0))
        }
    }

    func testMaterialShapeStyleDegradesToRetainedTranslucentFill() async {
        await MainActor.run {
            XCTAssertEqual(Material.ultraThin.retainedFallbackColor, Color(red: 1, green: 1, blue: 1, alpha: 0.18))
            XCTAssertEqual(Material.thin.retainedFallbackColor, Color(red: 1, green: 1, blue: 1, alpha: 0.28))
            XCTAssertEqual(Material.regular.retainedFallbackColor, Color(red: 1, green: 1, blue: 1, alpha: 0.40))
            XCTAssertEqual(Material.thick.retainedFallbackColor, Color(red: 1, green: 1, blue: 1, alpha: 0.58))
            XCTAssertEqual(Material.ultraThick.retainedFallbackColor, Color(red: 1, green: 1, blue: 1, alpha: 0.72))
            XCTAssertEqual(Material.bar.retainedFallbackColor, Color(red: 1, green: 1, blue: 1, alpha: 0.64))
            // Material's foreground style now carries its backdrop blur
            // radius alongside the fallback tint. Solid-color comparison
            // here was the pre-blur behaviour; with the blur path wired,
            // Material returns `.materialFill(tint:blurRadius:)`.
            XCTAssertEqual(
                ForegroundStyle(Material.regular),
                .materialFill(
                    tint: Material.regular.retainedFallbackColor,
                    blurRadius: Material.regular.retainedBlurRadius)
            )

            let backgroundNode = makeNode(Text("MATERIAL").background(.regularMaterial))
            let overlayNode = renderedNode(
                Text("BAR")
                    .frame(width: 72, height: 28)
                    .overlay(.bar, alignment: .topLeading)
            )
            let filledShapeNode = makeNode(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
            let strokedShapeNode = makeNode(Capsule().strokeBorder(.ultraThickMaterial, lineWidth: 3))
            let foregroundNode = makeNode(Text("FOREGROUND").foregroundStyle(.thickMaterial))

            // `.background(_:)` resolves a material's tint for the appearance
            // it lands in, the way it already resolved the label ladder and
            // the system colour table. `retainedFallbackColor` is the *light*
            // value; on the near-black page a white 0.64 bar was the
            // brightest object in the app, painted over the page it belongs
            // to.
            XCTAssertEqual(
                backgroundNode.backgroundColor, Material.regular.retainedTint(for: .dark))
            XCTAssertEqual(
                Material.regular.retainedTint(for: .light), Material.regular.retainedFallbackColor)
            XCTAssertEqual(firstText(in: backgroundNode.children[0]), "MATERIAL")
            XCTAssertEqual(overlayNode.children[1].backgroundColor, Material.bar.retainedFallbackColor)
            XCTAssertEqual(overlayNode.children[1].frame, Rect(x: 0, y: 0, width: 72, height: 28))
            XCTAssertEqual(filledShapeNode.backgroundColor, Material.thin.retainedFallbackColor)
            XCTAssertEqual(strokedShapeNode.borderColor, Material.ultraThick.retainedFallbackColor)
            XCTAssertEqual(strokedShapeNode.borderWidth, 3)
            XCTAssertEqual(foregroundNode.textStyle.color, Material.thick.retainedFallbackColor)
        }
    }

    func testBackgroundStyleSemanticStyleAndModifierFeedDefaultBackgrounds() async {
        await MainActor.run {
            let defaultColor = BackgroundStyle.background.retainedFallbackColor
            let customColor = Color(red: 0.24, green: 0.34, blue: 0.46, alpha: 0.92)
            let gradient = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
            let contextualBackground: BackgroundStyle = .background
            let defaultNode = makeNode(
                Text("DEFAULT")
                    .background()
            )
            let ignoredSafeAreaNode = makeNode(
                Text("EDGES")
                    .background(ignoresSafeAreaEdges: .horizontal)
                    .backgroundStyle(customColor)
            )
            let shapedNode = renderedNode(
                Text("SHAPED")
                    .frame(width: 84, height: 30)
                    .background(
                        in: RoundedRectangle(cornerRadius: 7), fillStyle: FillStyle(eoFill: true, antialiased: false)
                    )
                    .backgroundStyle(gradient)
            )

            XCTAssertEqual(BackgroundStyle().retainedFallbackColor, defaultColor)
            XCTAssertEqual(contextualBackground.retainedForegroundStyle, .color(defaultColor))
            XCTAssertEqual(defaultNode.backgroundColor, defaultColor)
            XCTAssertEqual(firstText(in: defaultNode.children[0]), "DEFAULT")
            XCTAssertEqual(ignoredSafeAreaNode.backgroundColor, customColor)
            XCTAssertEqual(firstText(in: ignoredSafeAreaNode.children[0]), "EDGES")
            XCTAssertEqual(
                shapedNode.children[0].backgroundGradient,
                .linear(SwiftWindowsGraphics.LinearGradient(inDarkAppearance(gradient))))
            XCTAssertEqual(shapedNode.children[0].cornerRadius, 7)
            XCTAssertTrue(shapedNode.children[0].clipsToBounds)
            XCTAssertEqual(
                shapedNode.children[0].clipFillStyle, RetainedClipFillStyle(eoFill: true, antialiased: false))
            XCTAssertEqual(shapedNode.children[0].frame, Rect(x: 0, y: 0, width: 84, height: 30))
            XCTAssertEqual(firstText(in: shapedNode.children[1]), "SHAPED")
        }
    }

    func testSemanticShapeStylesMapToRetainedFallbackColors() async {
        await MainActor.run {
            let foregroundNode = makeNode(Text("FOREGROUND").foregroundStyle(.foreground))
            let tintNode = makeNode(Text("TINT").foregroundStyle(.tint))
            let placeholderNode = makeNode(Text("PLACEHOLDER").foregroundStyle(.placeholder))
            let linkNode = makeNode(Text("LINK").foregroundStyle(.link))
            let separatorNode = makeNode(Text("SEPARATOR").background(.separator))
            let selectionNode = renderedNode(
                Text("SELECTION")
                    .frame(width: 72, height: 24)
                    .overlay(.selection)
            )
            let fillNode = makeNode(Rectangle().fill(.fill))
            let windowBackgroundNode = makeNode(Text("WINDOW").background(.windowBackground))

            XCTAssertEqual(ForegroundStyle.foreground, .color(.primary))
            XCTAssertEqual(
                SelectionShapeStyle().retainedFallbackColor, Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 0.42))
            XCTAssertEqual(
                SeparatorShapeStyle().retainedFallbackColor,
                Color(red: 0.736, green: 0.736, blue: 0.736, alpha: 0.36))
            XCTAssertEqual(TintShapeStyle().retainedFallbackColor, ViewBuildContext.defaultTint)
            XCTAssertEqual(
                PlaceholderTextShapeStyle().retainedFallbackColor,
                Color(red: 0.736, green: 0.736, blue: 0.736, alpha: 0.62))
            XCTAssertEqual(LinkShapeStyle().retainedFallbackColor, Color(red: 0.34, green: 0.70, blue: 1.0, alpha: 1))
            XCTAssertEqual(FillShapeStyle().retainedFallbackColor, Color(red: 1, green: 1, blue: 1, alpha: 0.12))
            XCTAssertEqual(
                WindowBackgroundShapeStyle().retainedFallbackColor,
                Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 1))
            XCTAssertEqual(foregroundNode.textStyle.color, .primary)
            XCTAssertEqual(tintNode.textStyle.color, inDarkAppearance(ViewBuildContext.defaultTint))
            XCTAssertEqual(placeholderNode.textStyle.color, PlaceholderTextShapeStyle().retainedFallbackColor)
            XCTAssertEqual(linkNode.textStyle.color, LinkShapeStyle().retainedFallbackColor)
            XCTAssertEqual(separatorNode.backgroundColor, SeparatorShapeStyle().retainedFallbackColor)
            XCTAssertEqual(selectionNode.children[1].backgroundColor, SelectionShapeStyle().retainedFallbackColor)
            XCTAssertEqual(fillNode.backgroundColor, FillShapeStyle().retainedFallbackColor)
            XCTAssertEqual(windowBackgroundNode.backgroundColor, WindowBackgroundShapeStyle().retainedFallbackColor)
        }
    }

    func testShapedBackgroundAndOverlayStyleOverloadsFillBaseLayout() async {
        await MainActor.run {
            let color = Color(red: 0.2, green: 0.6, blue: 0.8, alpha: 0.9)
            let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
            let backgroundNode = renderedNode(
                Text("BACKGROUND")
                    .frame(width: 90, height: 36)
                    .background(
                        color, in: RoundedRectangle(cornerRadius: 9),
                        fillStyle: FillStyle(eoFill: true, antialiased: false))
            )
            let materialNode = renderedNode(
                Text("MATERIAL")
                    .frame(width: 80, height: 32)
                    .background(.regularMaterial, in: Capsule())
            )
            let overlayNode = renderedNode(
                Text("OVERLAY")
                    .frame(width: 72, height: 28)
                    .overlay(gradient, in: Circle(), fillStyle: FillStyle(antialiased: false))
            )

            XCTAssertEqual(backgroundNode.children.count, 2)
            XCTAssertEqual(backgroundNode.children[0].backgroundColor, color)
            XCTAssertEqual(backgroundNode.children[0].cornerRadius, 9)
            XCTAssertTrue(backgroundNode.children[0].clipsToBounds)
            XCTAssertEqual(
                backgroundNode.children[0].clipFillStyle, RetainedClipFillStyle(eoFill: true, antialiased: false))
            XCTAssertEqual(backgroundNode.children[0].frame, Rect(x: 0, y: 0, width: 90, height: 36))
            XCTAssertEqual(firstText(in: backgroundNode.children[1]), "BACKGROUND")

            XCTAssertEqual(materialNode.children[0].backgroundColor, Material.regular.retainedFallbackColor)
            XCTAssertEqual(materialNode.children[0].cornerRadius, 16)
            XCTAssertEqual(materialNode.children[0].frame, Rect(x: 0, y: 0, width: 80, height: 32))
            XCTAssertEqual(firstText(in: materialNode.children[1]), "MATERIAL")

            XCTAssertEqual(overlayNode.children.count, 2)
            XCTAssertEqual(firstText(in: overlayNode.children[0]), "OVERLAY")
            XCTAssertEqual(
                overlayNode.children[1].backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(overlayNode.children[1].cornerRadius, 14)
            XCTAssertTrue(overlayNode.children[1].clipsToBounds)
            XCTAssertEqual(
                overlayNode.children[1].clipFillStyle, RetainedClipFillStyle(eoFill: false, antialiased: false))
            XCTAssertEqual(overlayNode.children[1].frame, Rect(x: 0, y: 0, width: 72, height: 28))
        }
    }

    func testCustomViewModifierMapsThroughRetainedComponentPipeline() async {
        await MainActor.run {
            let node = makeNode(
                Text("ALERT")
                    .modifier(EmphasisModifier())
            )

            XCTAssertEqual(node.text, "ALERT")
            XCTAssertEqual(node.textStyle.color, inDarkAppearance(.red))
            XCTAssertEqual(node.textStyle.weight, .bold)
        }
    }

    func testEquatableViewRendersContent() async {
        await MainActor.run {
            struct EquatableRow: View, Equatable {
                var title: String

                var body: some View {
                    Text(title)
                }
            }

            let first = EquatableView(content: EquatableRow(title: "ROW"))
            let directNode = makeNode(first)
            let node = makeNode(EquatableRow(title: "ROW").equatable())

            XCTAssertEqual(directNode.text, "ROW")
            XCTAssertEqual(node.text, "ROW")
        }
    }

    func testOptionalViewRendersWrappedContentOrEmptyView() async {
        await MainActor.run {
            let present: Text? = Text("OPTIONAL")
            let absent: Text? = nil

            let presentNode = makeNode(present)
            let absentNode = makeNode(absent)

            XCTAssertEqual(presentNode.text, "OPTIONAL")
            XCTAssertTrue(allTexts(in: absentNode).isEmpty)
            XCTAssertEqual(absentNode.intrinsicContentSize(), .zero)
        }
    }

    func testOptionalViewPreservesWrappedMetadataWhenPresent() async {
        await MainActor.run {
            let tagged = Text("OPTION").tag("selected")
            let present = Optional(tagged)
            let absent: Text? = nil

            XCTAssertEqual(
                (present as any TaggedViewMetadata).anySelectionTag,
                AnyHashable("selected")
            )
            XCTAssertNil((absent as any TaggedViewMetadata).anySelectionTag)
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
            XCTAssertEqual(
                gradientNode.children[0].backgroundColor, inDarkAppearance(primaryGradient.startColor))
            XCTAssertEqual(
                gradientNode.children[0].backgroundGradient,
                .linear(SwiftWindowsGraphics.LinearGradient(inDarkAppearance(primaryGradient))))
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

    func testLabelNamedImageInitializersComposeBitmapIconContent() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-label-image-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let stringNode = makeNode(Label("PHOTO", image: url.path))
            let protocolTitle: Substring = "TOOLS"[...]
            let protocolNode = makeNode(Label(protocolTitle, image: url.path))
            let keyNode = makeNode(Label(LocalizedStringKey("ALBUM"), image: url.path))

            XCTAssertEqual(stringNode.children.count, 2)
            XCTAssertEqual(stringNode.children[0].bitmapSurface?.width, 2)
            XCTAssertEqual(stringNode.children[0].bitmapSurface?.height, 1)
            XCTAssertEqual(stringNode.children[1].text, "PHOTO")
            XCTAssertEqual(protocolNode.children[1].text, "TOOLS")
            XCTAssertEqual(keyNode.children[1].text, "ALBUM")
        }
    }

    func testLabelStyleModifierSelectsRetainedLabelContent() async {
        await MainActor.run {
            let iconOnlyNode = makeNode(Label("SETTINGS", systemImage: "gear").labelStyle(.iconOnly))
            let titleOnlyNode = makeNode(Label("SETTINGS", systemImage: "gear").labelStyle(.titleOnly))
            let concreteIconOnlyNode = makeNode(Label("TOOLS", systemImage: "wrench").labelStyle(IconOnlyLabelStyle()))
            let concreteTitleOnlyNode = makeNode(
                Label("PROFILE", systemImage: "person").labelStyle(TitleOnlyLabelStyle()))
            let defaultNode = makeNode(Label("HOME", systemImage: "house").labelStyle(DefaultLabelStyle()))
            let inheritedNode = makeNode(
                VStack {
                    Label("SETTINGS", systemImage: "gear")
                    Label("PROFILE", systemImage: "person")
                        .labelStyle(TitleAndIconLabelStyle())
                }
                .labelStyle(.titleOnly)
            )

            XCTAssertFalse(allTexts(in: iconOnlyNode).contains("SETTINGS"))
            XCTAssertEqual(titleOnlyNode.text, "SETTINGS")
            XCTAssertFalse(allTexts(in: concreteIconOnlyNode).contains("TOOLS"))
            XCTAssertEqual(concreteTitleOnlyNode.text, "PROFILE")
            XCTAssertEqual(defaultNode.children.count, 2)
            XCTAssertEqual(inheritedNode.children[0].text, "SETTINGS")
            XCTAssertEqual(inheritedNode.children[1].children.count, 2)
            XCTAssertEqual(inheritedNode.children[1].children[1].text, "PROFILE")
        }
    }

    func testListItemTintStoresMetadataAndTintsRetainedLabels() async {
        await MainActor.run {
            let fixedTint = Color(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
            let preferredTint = Color(red: 0.9, green: 0.5, blue: 0.1, alpha: 1)
            let inheritedTint = Color(red: 0.3, green: 0.8, blue: 0.4, alpha: 1)
            // `.monochrome` is the stack's own neutral, no longer blue-cast.
            let monochromeTint = Color(red: 0.896, green: 0.896, blue: 0.896, alpha: 0.78)
            let listNode = makeNode(
                List {
                    Label("FIXED", systemImage: "star")
                        .listItemTint(fixedTint)
                    Label("PREFERRED", systemImage: "gear")
                        .listItemTint(.preferred(preferredTint))
                    Label("MONO", systemImage: "person")
                        .listItemTint(.monochrome)
                    Label("INHERITED", systemImage: "flag")
                    Label("RESET", systemImage: "xmark")
                        .listItemTint(nil as Color?)
                }
                .listItemTint(inheritedTint)
            )

            XCTAssertEqual(
                listNode.listItemTint,
                RetainedListItemTint(color: inheritedTint, kind: .fixed)
            )
            XCTAssertEqual(
                listRows(of: listNode)[0].listItemTint,
                RetainedListItemTint(color: fixedTint, kind: .fixed)
            )
            XCTAssertEqual(listRows(of: listNode)[0].children[0].textStyle.color, fixedTint)
            XCTAssertEqual(listRows(of: listNode)[0].children[1].textStyle.color, fixedTint)

            XCTAssertEqual(
                listRows(of: listNode)[1].listItemTint,
                RetainedListItemTint(color: preferredTint, kind: .preferred)
            )
            XCTAssertEqual(listRows(of: listNode)[1].children[0].textStyle.color, preferredTint)

            XCTAssertEqual(
                listRows(of: listNode)[2].listItemTint,
                RetainedListItemTint(color: monochromeTint, kind: .monochrome)
            )
            XCTAssertEqual(listRows(of: listNode)[2].children[0].textStyle.color, monochromeTint)

            XCTAssertNil(listRows(of: listNode)[3].listItemTint)
            XCTAssertEqual(listRows(of: listNode)[3].children[0].textStyle.color, inheritedTint)

            XCTAssertNil(listRows(of: listNode)[4].listItemTint)
            XCTAssertEqual(listRows(of: listNode)[4].children[0].textStyle.color, inheritedTint)
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
            // A symbol's image box is `symbolBoxRatio` x the point size:
            // SF Symbols draw to the font's full ascender-to-descender box.
            let box = 20 * MacOSControlMetrics.Typography.symbolBoxRatio
            XCTAssertEqual(fillNode.preferredSize, Size(width: box, height: box))
            XCTAssertEqual(wideFitNode.preferredSize, Size(width: box, height: box / 2))
            XCTAssertEqual(scaledToFillNode.preferredSize, Size(width: box, height: box))
        }
    }

    func testGenericAspectRatioMapsToRetainedPreferredSizeWrapper() async {
        await MainActor.run {
            let fitNode = makeNode(
                Text("FIT")
                    .frame(width: 100, height: 50)
                    .aspectRatio(1, contentMode: .fit)
            )
            let fillNode = makeNode(
                Text("FILL")
                    .frame(width: 100, height: 50)
                    .aspectRatio(1, contentMode: .fill)
            )
            let scaledToFitNode = makeNode(
                Text("SCALE")
                    .frame(width: 100, height: 50)
                    .scaledToFit()
            )

            XCTAssertEqual(fitNode.preferredSize, Size(width: 50, height: 50))
            XCTAssertEqual(fillNode.preferredSize, Size(width: 100, height: 100))
            XCTAssertEqual(scaledToFitNode.preferredSize, Size(width: 100, height: 50))
            XCTAssertEqual(fitNode.children.count, 1)
            XCTAssertEqual(fitNode.children[0].preferredSize, Size(width: 100, height: 50))
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

    func testImageResizableRetainsModeAndCapInsetsMetadata() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-image-resizable-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let capInsets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
            let plainNode = makeNode(Image(systemName: "gearshape"))
            let tiledSymbolNode = makeNode(
                Image(systemName: "gearshape")
                    .resizable(capInsets: capInsets, resizingMode: .tile)
            )
            let stretchBitmapNode = makeNode(Image(url.path).resizable())

            XCTAssertNil(plainNode.imageResizingMode)
            XCTAssertNil(plainNode.imageCapInsets)
            XCTAssertEqual(tiledSymbolNode.imageResizingMode, .tile)
            XCTAssertEqual(tiledSymbolNode.imageCapInsets, capInsets)
            XCTAssertEqual(stretchBitmapNode.imageResizingMode, .stretch)
            XCTAssertEqual(stretchBitmapNode.imageCapInsets, .zero)
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
            let variableBitmapNode = makeNode(Image(url.path, variableValue: 0.25))
            let labeledVariableBitmapNode = makeNode(
                Image(url.path, variableValue: 0.5, label: Text("VARIABLE PHOTO"))
            )
            let decorativeVariableBitmapNode = makeNode(Image(decorative: url.path, variableValue: 0.75))
            let variableSymbolNode = makeNode(
                Image(systemName: "gearshape", variableValue: 0.42)
                    .foregroundColor(.red)
            )
            let labeledSymbolNode = makeNode(Image(systemName: "gearshape", label: Text("SETTINGS")))
            let labeledVariableSymbolNode = makeNode(
                Image(systemName: "gearshape", variableValue: 0.84, label: Text("VARIABLE SETTINGS"))
            )

            XCTAssertEqual(labeledNode.bitmapSurface?.width, 2)
            XCTAssertEqual(labeledNode.bitmapSurface?.height, 1)
            XCTAssertEqual(decorativeNode.bitmapSurface?.width, 2)
            XCTAssertEqual(decorativeNode.bitmapSurface?.height, 1)
            XCTAssertEqual(variableBitmapNode.symbolVariableValue, 0.25)
            XCTAssertEqual(labeledVariableBitmapNode.symbolVariableValue, 0.5)
            XCTAssertEqual(labeledVariableBitmapNode.accessibilityLabel, "VARIABLE PHOTO")
            XCTAssertEqual(decorativeVariableBitmapNode.symbolVariableValue, 0.75)
            XCTAssertTrue(decorativeVariableBitmapNode.isAccessibilityHidden)
            XCTAssertEqual(variableSymbolNode.text, "\u{E713}")
            XCTAssertEqual(variableSymbolNode.textStyle.color, inDarkAppearance(.red))
            XCTAssertEqual(variableSymbolNode.symbolVariableValue, 0.42)
            XCTAssertEqual(labeledSymbolNode.text, "\u{E713}")
            XCTAssertEqual(labeledSymbolNode.accessibilityLabel, "SETTINGS")
            XCTAssertEqual(labeledVariableSymbolNode.symbolVariableValue, 0.84)
            XCTAssertEqual(labeledVariableSymbolNode.accessibilityLabel, "VARIABLE SETTINGS")
        }
    }

    func testImageResourceInitializersBridgeGeneratedAssetResources() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-image-resource-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let resource = ImageResource(name: url.path, bundle: .main)
            let matchingResource = ImageResource(name: url.path, bundle: .main)
            let imageNode = makeNode(Image(resource))
            let labelNode = makeNode(Label(LocalizedStringKey("ALBUM"), image: resource))

            var didRunButton = false
            let buttonTitle: Substring = "EXPORT"[...]
            let buttonNode = makeNode(
                Button(buttonTitle, image: resource, role: .destructive) {
                    didRunButton = true
                })

            var didRunMenuPrimary = false
            let menuNode = makeNode(
                Menu(
                    LocalizedStringKey("MORE"), image: resource,
                    content: {
                        Button("PICK") {}
                    },
                    primaryAction: {
                        didRunMenuPrimary = true
                    }))

            var didRunControl = false
            let controlTitle: Substring = "TOOLS"[...]
            let controlNode = makeNode(
                ControlGroup(controlTitle, image: resource) {
                    Button("RESET") {
                        didRunControl = true
                    }
                })

            let unavailableNode = makeNode(
                ContentUnavailableView(LocalizedStringKey("OFFLINE"), image: resource, description: Text("Try again"))
            )

            XCTAssertEqual(resource, matchingResource)
            XCTAssertEqual(imageNode.bitmapSurface?.width, 2)
            XCTAssertEqual(imageNode.bitmapSurface?.height, 1)
            XCTAssertEqual(labelNode.children[0].bitmapSurface?.width, 2)
            XCTAssertTrue(allTexts(in: labelNode).contains("ALBUM"))
            XCTAssertTrue(allTexts(in: buttonNode).contains("EXPORT"))
            // A non-prominent destructive button keeps the standard bezel;
            // its role reads in the label.
            XCTAssertEqual(buttonNode.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            XCTAssertTrue(
                allTextColors(in: buttonNode).contains { $0.red > 0.8 && $0.green < 0.4 })
            XCTAssertTrue(allTexts(in: menuNode).contains("MORE"))
            XCTAssertTrue(allTexts(in: controlNode).contains("TOOLS"))
            XCTAssertTrue(allTexts(in: unavailableNode).contains("OFFLINE"))
            XCTAssertTrue(allTexts(in: unavailableNode).contains("Try again"))

            buttonNode.onActivate?()
            menuNode.children[0].onActivate?()
            controlNode.children[1].onActivate?()

            XCTAssertTrue(didRunButton)
            XCTAssertTrue(didRunMenuPrimary)
            XCTAssertTrue(didRunControl)
        }
    }

    func testImageRenderingModeModifierStoresRetainedImageMetadata() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-image-rendering-mode-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let defaultNode = makeNode(Image(systemName: "gear"))
            let templateNode = makeNode(Image(systemName: "gear").renderingMode(.template))
            let originalBitmapNode = makeNode(Image(url.path).renderingMode(.original))
            let templateBitmapNode = makeNode(
                Image(url.path)
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
                    .renderingMode(.template)
            )
            let resetNode = makeNode(
                Image(systemName: "gear")
                    .renderingMode(.template)
                    .renderingMode(nil)
            )

            XCTAssertNil(defaultNode.imageRenderingMode)
            XCTAssertEqual(templateNode.imageRenderingMode, .template)
            XCTAssertEqual(originalBitmapNode.imageRenderingMode, .original)
            XCTAssertEqual(templateBitmapNode.imageRenderingMode, .template)
            XCTAssertEqual(templateBitmapNode.bitmapSurface?.pixels[0], 153)
            XCTAssertEqual(templateBitmapNode.bitmapSurface?.pixels[1], 102)
            XCTAssertEqual(templateBitmapNode.bitmapSurface?.pixels[2], 51)
            XCTAssertEqual(templateBitmapNode.bitmapSurface?.pixels[3], 255)
            XCTAssertNil(resetNode.imageRenderingMode)
        }
    }

    func testImageInterpolationAndAntialiasedModifiersStoreRetainedImageMetadata() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-image-interpolation-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let defaultNode = makeNode(Image(systemName: "gear"))
            let highNode = makeNode(
                Image(systemName: "gear")
                    .interpolation(.high)
                    .antialiased(false)
            )
            let noneBitmapNode = makeNode(
                Image(url.path)
                    .interpolation(.none)
                    .antialiased(true)
            )

            XCTAssertEqual(defaultNode.imageInterpolation, .medium)
            XCTAssertNil(defaultNode.imageAntialiased)
            XCTAssertEqual(highNode.imageInterpolation, .high)
            XCTAssertEqual(highNode.imageAntialiased, false)
            XCTAssertEqual(noneBitmapNode.imageInterpolation, .none)
            XCTAssertEqual(noneBitmapNode.imageAntialiased, true)
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

            // An `Image` inherits the ambient font rather than pinning a
            // fixed 19.4px box, so its bitmap-fallback scale is body''s.
            let base = Font.body.resolvedScale
            XCTAssertEqual(defaultNode.textStyle.scale, base, accuracy: 0.0001)
            XCTAssertEqual(smallNode.textStyle.scale, base * 0.82, accuracy: 0.0001)
            XCTAssertEqual(largeNode.children[0].textStyle.scale, base * 1.25, accuracy: 0.0001)
            XCTAssertEqual(largeNode.children[1].children[0].textStyle.scale, base * 1.25, accuracy: 0.0001)
            XCTAssertEqual(environmentNode.textStyle.scale, base * 0.82, accuracy: 0.0001)
            XCTAssertEqual(readerNode.text, "LARGE")
        }
    }

    func testSymbolRenderingModePropagatesThroughEnvironmentAndRetainedImageMetadata() async {
        await MainActor.run {
            struct SymbolRenderingModeReaderView: View {
                @Environment(\.symbolRenderingMode) var symbolRenderingMode

                var body: some View {
                    Text(
                        symbolRenderingMode == .palette
                            ? "PALETTE"
                            : symbolRenderingMode == .hierarchical
                                ? "HIERARCHICAL"
                                : symbolRenderingMode == .multicolor
                                    ? "MULTICOLOR"
                                    : symbolRenderingMode == .monochrome
                                        ? "MONOCHROME"
                                        : "NONE"
                    )
                }
            }

            let defaultNode = makeNode(Image(systemName: "gear"))
            let paletteNode = makeNode(Image(systemName: "gear").symbolRenderingMode(.palette))
            let multicolorNode = makeNode(Image(systemName: "gear").symbolRenderingMode(.multicolor))
            let inheritedNode = makeNode(
                VStack {
                    Image(systemName: "gear")
                    Label("SETTINGS", systemImage: "gear")
                }
                .symbolRenderingMode(.hierarchical)
            )
            let resetNode = makeNode(
                VStack {
                    Image(systemName: "gear")
                        .symbolRenderingMode(nil)
                }
                .symbolRenderingMode(.multicolor)
            )
            let readerNode = makeNode(SymbolRenderingModeReaderView().symbolRenderingMode(.monochrome))
            let resetReaderNode = makeNode(
                VStack {
                    SymbolRenderingModeReaderView()
                        .symbolRenderingMode(nil)
                }
                .symbolRenderingMode(.palette)
            )

            XCTAssertNil(defaultNode.symbolRenderingMode)
            XCTAssertEqual(paletteNode.symbolRenderingMode, .palette)
            XCTAssertEqual(paletteNode.textStyle.color, ViewBuildContext.defaultTint)
            XCTAssertEqual(multicolorNode.textStyle.color, Color(red: 0.30, green: 0.74, blue: 0.92, alpha: 1.0))
            XCTAssertEqual(inheritedNode.children[0].symbolRenderingMode, .hierarchical)
            XCTAssertEqual(inheritedNode.children[1].children[0].symbolRenderingMode, .hierarchical)
            XCTAssertEqual(inheritedNode.children[0].textStyle.color, Color.white.opacity(0.72))
            XCTAssertEqual(inheritedNode.children[1].children[0].textStyle.color, Color.white.opacity(0.72))
            XCTAssertNil(resetNode.children[0].symbolRenderingMode)
            XCTAssertEqual(resetNode.children[0].textStyle.color, .primary)
            XCTAssertEqual(readerNode.text, "MONOCHROME")
            XCTAssertEqual(resetReaderNode.children[0].text, "NONE")
        }
    }

    func testSymbolVariantPropagatesThroughEnvironmentAndRetainedImageMetadata() async {
        await MainActor.run {
            struct SymbolVariantReaderView: View {
                @Environment(\.symbolVariants) var symbolVariants

                var body: some View {
                    Text(
                        symbolVariants.contains([.fill, .slash])
                            ? "FILL_SLASH"
                            : symbolVariants.contains(.circle)
                                ? "CIRCLE"
                                : symbolVariants.isEmpty
                                    ? "NONE"
                                    : "OTHER"
                    )
                }
            }

            let defaultNode = makeNode(Image(systemName: "gear"))
            let fillNode = makeNode(Image(systemName: "gear").symbolVariant(.fill))
            let combinedNode = makeNode(Image(systemName: "gear").symbolVariant([.fill, .slash]))
            let inheritedNode = makeNode(
                VStack {
                    Image(systemName: "gear")
                    Label("SETTINGS", systemImage: "gear")
                }
                .symbolVariant(.circle)
            )
            let resetNode = makeNode(
                VStack {
                    Image(systemName: "gear")
                        .symbolVariant(.none)
                }
                .symbolVariant(.fill)
            )
            let readerNode = makeNode(SymbolVariantReaderView().symbolVariant([.fill, .slash]))
            let resetReaderNode = makeNode(
                VStack {
                    SymbolVariantReaderView()
                        .symbolVariant(.none)
                }
                .symbolVariant(.circle)
            )

            XCTAssertEqual(defaultNode.symbolVariants, .none)
            XCTAssertEqual(fillNode.symbolVariants, .fill)
            XCTAssertEqual(combinedNode.symbolVariants, [.fill, .slash])
            XCTAssertEqual(inheritedNode.children[0].symbolVariants, .circle)
            XCTAssertEqual(inheritedNode.children[1].children[0].symbolVariants, .circle)
            XCTAssertEqual(resetNode.children[0].symbolVariants, .none)
            XCTAssertEqual(defaultNode.text, "\u{E713}")
            XCTAssertEqual(fillNode.textStyle.weight, .bold)
            XCTAssertEqual(combinedNode.nodeTag, "symbol-variant")
            XCTAssertEqual(combinedNode.children[0].text, "\u{E713}")
            XCTAssertEqual(combinedNode.children[0].textStyle.weight, .bold)
            XCTAssertEqual(combinedNode.children[1].nodeTag, "symbol-variant-slash")
            XCTAssertEqual(inheritedNode.children[0].nodeTag, "symbol-variant")
            XCTAssertGreaterThan(inheritedNode.children[0].borderWidth, 0)
            XCTAssertEqual(
                inheritedNode.children[0].cornerRadius,
                0.5
                    * min(
                        inheritedNode.children[0].preferredSize?.width ?? 0,
                        inheritedNode.children[0].preferredSize?.height ?? 0
                    ))
            XCTAssertEqual(readerNode.text, "FILL_SLASH")
            XCTAssertEqual(resetReaderNode.children[0].text, "NONE")
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

    func testContainerRelativeFrameUsesBuildContextCanvasSize() async {
        await MainActor.run {
            let fullNode = makeNode(
                Text("FULL")
                    .containerRelativeFrame([.horizontal, .vertical], alignment: .bottomTrailing),
                size: Size(width: 320, height: 180)
            )
            let transformedNode = makeNode(
                Text("HALF")
                    .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                        axis == .horizontal ? length * 0.5 : length - 20
                    },
                size: Size(width: 200, height: 100)
            )
            let countedNode = makeNode(
                Text("COUNT")
                    .containerRelativeFrame([.horizontal, .vertical], count: 3, span: 2, spacing: 12),
                size: Size(width: 300, height: 120)
            )

            XCTAssertEqual(fullNode.preferredSize, Size(width: 320, height: 180))
            XCTAssertNil(fullNode.children[0].preferredSize)
            guard case .stack(let fullLayout) = fullNode.layoutMode else {
                return XCTFail("Expected containerRelativeFrame to wrap content in a stack layout")
            }
            XCTAssertEqual(fullLayout, .vertical(padding: .zero, alignment: .trailing, mainAlignment: .end))

            XCTAssertEqual(transformedNode.preferredSize, Size(width: 100, height: 80))
            XCTAssertNil(transformedNode.children[0].preferredSize)
            XCTAssertEqual(countedNode.preferredSize, Size(width: 196, height: 76))
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

            // A padding wrapper centres its single child on the main axis.
            // `.start` and `.center` are identical whenever the wrapper is
            // content-sized, and differ in the one case that matters:
            // `.padding(.horizontal, 12).frame(height: 28)`, where a stated
            // height stretches the wrapper and the label has to stay in the
            // middle of the box rather than climbing to the top of it.
            XCTAssertEqual(
                allPaddingLayout,
                .vertical(padding: .all(16), alignment: .stretch, mainAlignment: .center))
            XCTAssertEqual(
                horizontalPaddingLayout,
                .vertical(
                    padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16),
                    alignment: .stretch,
                    mainAlignment: .center
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

    func testIgnoringSafeAreaCompatibilityModifiersPassThroughView() async {
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

    func testSafeAreaPaddingMapsToRetainedPaddingLayout() async {
        await MainActor.run {
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

            guard case .stack(let defaultPaddingLayout) = defaultPaddingNode.layoutMode else {
                return XCTFail("Expected safeAreaPadding to wrap content in a stack layout")
            }
            guard case .stack(let edgePaddingLayout) = edgePaddingNode.layoutMode else {
                return XCTFail("Expected edge safeAreaPadding to wrap content in a stack layout")
            }
            guard case .stack(let optionalPaddingLayout) = optionalPaddingNode.layoutMode else {
                return XCTFail("Expected optional safeAreaPadding to wrap content in a stack layout")
            }
            guard case .stack(let insetPaddingLayout) = insetPaddingNode.layoutMode else {
                return XCTFail("Expected inset safeAreaPadding to wrap content in a stack layout")
            }

            XCTAssertEqual(
                defaultPaddingLayout,
                .vertical(padding: .all(16), alignment: .stretch, mainAlignment: .center))
            XCTAssertEqual(
                edgePaddingLayout,
                .vertical(
                    padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12),
                    alignment: .stretch,
                    mainAlignment: .center
                )
            )
            XCTAssertEqual(
                optionalPaddingLayout,
                .vertical(
                    padding: EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0),
                    alignment: .stretch,
                    mainAlignment: .center
                )
            )
            XCTAssertEqual(
                insetPaddingLayout,
                .vertical(
                    padding: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
                    alignment: .stretch,
                    mainAlignment: .center
                )
            )
        }
    }

    func testSafeAreaInsetComposesEdgeContentAroundBase() async {
        await MainActor.run {
            let topNode = makeNode(
                Text("BASE")
                    .safeAreaInset(edge: .top, alignment: .leading, spacing: 6) {
                        Text("TOP")
                    }
            )
            let trailingNode = makeNode(
                Text("BASE")
                    .safeAreaInset(edge: .trailing, alignment: .bottom, spacing: 4) {
                        Text("TRAILING")
                    }
            )
            let rtlLeadingNode = makeNode(
                Text("BASE")
                    .safeAreaInset(edge: .leading, alignment: .top) {
                        Text("LEADING")
                    }
                    .environment(\.layoutDirection, .rightToLeft)
            )

            guard case .stack(let topLayout) = topNode.layoutMode else {
                return XCTFail("Expected vertical safeAreaInset to wrap content in a stack layout")
            }
            guard case .stack(let trailingLayout) = trailingNode.layoutMode else {
                return XCTFail("Expected horizontal safeAreaInset to wrap content in a stack layout")
            }
            guard case .stack(let rtlLeadingLayout) = rtlLeadingNode.layoutMode else {
                return XCTFail("Expected RTL horizontal safeAreaInset to wrap content in a stack layout")
            }

            XCTAssertEqual(topLayout, .vertical(spacing: 6, alignment: .leading))
            XCTAssertEqual(topNode.children.map(\.text), ["TOP", "BASE"])

            XCTAssertEqual(trailingLayout, .horizontal(spacing: 4, alignment: .trailing))
            XCTAssertEqual(trailingNode.children.map(\.text), ["BASE", "TRAILING"])

            XCTAssertEqual(rtlLeadingLayout, .horizontal(spacing: 0, alignment: .leading))
            XCTAssertEqual(rtlLeadingNode.children.map(\.text), ["BASE", "LEADING"])
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
            XCTAssertEqual(
                gradientNode.children[1].backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(gradientNode.children[1].frame, Rect(x: 0, y: 0, width: 90, height: 36))
            XCTAssertEqual(storedColorNode.children[1].backgroundColor, color)
            XCTAssertEqual(storedColorNode.children[1].frame, Rect(x: 0, y: 0, width: 70, height: 24))
            XCTAssertEqual(
                storedGradientNode.children[1].backgroundGradient,
                .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(storedGradientNode.children[1].frame, Rect(x: 0, y: 0, width: 96, height: 40))
            XCTAssertEqual(nilNode.text, "PLAIN")
        }
    }

    func testOverlayStyleAlignmentOverloadsFillBaseLayout() async {
        await MainActor.run {
            let color = Color(red: 0.7, green: 0.2, blue: 0.4, alpha: 0.8)
            let optionalColor: Color? = Color(red: 0.2, green: 0.7, blue: 0.5, alpha: 0.6)
            let nilColor: Color? = nil
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.4, blue: 0.9, alpha: 1),
                    Color(red: 0.8, green: 0.3, blue: 0.6, alpha: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            let colorNode = renderedNode(
                Text("BASE")
                    .frame(width: 80, height: 32)
                    .overlay(color, alignment: .topTrailing)
            )
            let optionalNode = renderedNode(
                Text("OPTIONAL")
                    .frame(width: 72, height: 28)
                    .overlay(optionalColor, alignment: .bottomLeading)
            )
            let gradientNode = renderedNode(
                Text("GRADIENT")
                    .frame(width: 90, height: 36)
                    .overlay(gradient, alignment: .bottomTrailing)
            )
            let storedStyleNode = renderedNode(
                Text("STORED")
                    .frame(width: 70, height: 24)
                    .overlay(ForegroundStyle.color(color), alignment: .leading)
            )
            let nilNode = makeNode(
                Text("PLAIN")
                    .overlay(nilColor, alignment: .topLeading)
            )

            XCTAssertEqual(colorNode.children[1].backgroundColor, color)
            XCTAssertEqual(colorNode.children[1].frame, Rect(x: 0, y: 0, width: 80, height: 32))
            XCTAssertEqual(optionalNode.children[1].backgroundColor, optionalColor)
            XCTAssertEqual(optionalNode.children[1].frame, Rect(x: 0, y: 0, width: 72, height: 28))
            XCTAssertEqual(
                gradientNode.children[1].backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(gradientNode.children[1].frame, Rect(x: 0, y: 0, width: 90, height: 36))
            XCTAssertEqual(storedStyleNode.children[1].backgroundColor, color)
            XCTAssertEqual(storedStyleNode.children[1].frame, Rect(x: 0, y: 0, width: 70, height: 24))
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

    func testContainerBackgroundMapsToRetainedBackgroundLayer() async {
        await MainActor.run {
            let color = Color(red: 0.18, green: 0.28, blue: 0.44, alpha: 1)
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.2, blue: 0.8, alpha: 1),
                    Color(red: 0.8, green: 0.2, blue: 0.5, alpha: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            let colorNode = makeNode(
                Text("CONTAINER")
                    .containerBackground(color, for: .navigation)
            )
            let gradientNode = makeNode(
                Text("GRADIENT")
                    .containerBackground(gradient, for: .window)
            )
            let builderNode = renderedNode(
                Text("BASE")
                    .frame(width: 80, height: 32)
                    .containerBackground(for: .tabView, alignment: .bottomTrailing) {
                        Text("BG")
                            .frame(width: 16, height: 8)
                    }
            )

            XCTAssertEqual(ContainerBackgroundPlacement.navigation.description, "navigation")
            XCTAssertEqual(ContainerBackgroundPlacement.navigationSplitView.description, "navigationSplitView")
            XCTAssertEqual(ContainerBackgroundPlacement.widget.description, "widget")
            XCTAssertEqual(ContainerBackgroundPlacement.subscriptionStoreHeader.description, "subscriptionStoreHeader")
            XCTAssertEqual(colorNode.backgroundColor, color)
            XCTAssertEqual(firstText(in: colorNode.children[0]), "CONTAINER")
            XCTAssertEqual(gradientNode.backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(firstText(in: gradientNode.children[0]), "GRADIENT")
            XCTAssertEqual(builderNode.preferredSize, Size(width: 80, height: 32))
            XCTAssertEqual(builderNode.children[0].frame, Rect(x: 64, y: 24, width: 16, height: 8))
            XCTAssertEqual(builderNode.children[1].frame, Rect(x: 0, y: 0, width: 80, height: 32))
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
            XCTAssertEqual(gradientNode.backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(firstText(in: gradientNode.children[0]), "GRADIENT")
            XCTAssertEqual(storedColorNode.backgroundColor, storedColor)
            XCTAssertEqual(firstText(in: storedColorNode.children[0]), "STORED")
            XCTAssertEqual(
                storedGradientNode.backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(firstText(in: storedGradientNode.children[0]), "STORED GRADIENT")
            XCTAssertEqual(nilNode.text, "PLAIN")
        }
    }

    func testBackgroundStyleAlignmentOverloadsFillBaseLayout() async {
        await MainActor.run {
            let color = Color(red: 0.3, green: 0.6, blue: 0.8, alpha: 0.85)
            let optionalColor: Color? = Color(red: 0.8, green: 0.4, blue: 0.2, alpha: 0.65)
            let nilColor: Color? = nil
            let gradient = LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.7, blue: 0.5, alpha: 1),
                    Color(red: 0.6, green: 0.2, blue: 0.9, alpha: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            let colorNode = makeNode(
                Text("COLOR")
                    .background(color, alignment: .bottomTrailing)
            )
            let optionalNode = makeNode(
                Text("OPTIONAL")
                    .background(optionalColor, alignment: .topLeading)
            )
            let gradientNode = makeNode(
                Text("GRADIENT")
                    .background(gradient, alignment: .trailing)
            )
            let storedStyleNode = makeNode(
                Text("STORED")
                    .background(ForegroundStyle.color(color), alignment: .bottom)
            )
            let nilNode = makeNode(
                Text("PLAIN")
                    .background(nilColor, alignment: .leading)
            )

            XCTAssertEqual(colorNode.backgroundColor, color)
            XCTAssertEqual(firstText(in: colorNode.children[0]), "COLOR")
            XCTAssertEqual(optionalNode.backgroundColor, optionalColor)
            XCTAssertEqual(firstText(in: optionalNode.children[0]), "OPTIONAL")
            XCTAssertEqual(gradientNode.backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(firstText(in: gradientNode.children[0]), "GRADIENT")
            XCTAssertEqual(storedStyleNode.backgroundColor, color)
            XCTAssertEqual(firstText(in: storedStyleNode.children[0]), "STORED")
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
            XCTAssertEqual(child.textStyle.fontFamily, SystemUIFontFace.family(forPointSize: 18))
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

            // Lazy stacks place children exactly like eager ones and differ
            // only in whether an out-of-viewport child's subtree is laid out
            // recursively, so the layout value is the same and the mode is
            // the virtualizing variant.
            guard case .lazyStack(let verticalLayout) = lazyVStack.layoutMode else {
                return XCTFail("Expected LazyVStack to use the virtualizing retained stack layout")
            }
            guard case .lazyStack(let horizontalLayout) = lazyHStack.layoutMode else {
                return XCTFail("Expected LazyHStack to use the virtualizing retained stack layout")
            }
            XCTAssertTrue(lazyVStack.layoutMode.virtualizesChildren)
            XCTAssertTrue(lazyHStack.layoutMode.virtualizesChildren)

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

    func testLazyStackPinnedViewsDeferSectionHeaderAndFooterPainting() async {
        await MainActor.run {
            let headerPinnedNode = makeNode(
                LazyVStack(pinnedViews: [.sectionHeaders]) {
                    Section {
                        Text("ROW")
                    } header: {
                        Text("HEADER")
                    } footer: {
                        Text("FOOTER")
                    }
                }
            )
            let footerPinnedNode = makeNode(
                LazyHStack(pinnedViews: [.sectionFooters]) {
                    Section {
                        Text("ROW")
                    } header: {
                        Text("HEADER")
                    } footer: {
                        Text("FOOTER")
                    }
                }
            )

            let headerSection = headerPinnedNode.children[0]
            let footerSection = footerPinnedNode.children[0]

            XCTAssertEqual(headerSection.sectionHeaderChildCount, 1)
            XCTAssertEqual(headerSection.sectionFooterChildCount, 1)
            XCTAssertTrue(headerSection.children[0].paintsInDeferredPhase)
            XCTAssertFalse(headerSection.children[1].paintsInDeferredPhase)
            XCTAssertFalse(headerSection.children[2].paintsInDeferredPhase)

            XCTAssertFalse(footerSection.children[0].paintsInDeferredPhase)
            XCTAssertFalse(footerSection.children[1].paintsInDeferredPhase)
            XCTAssertTrue(footerSection.children[2].paintsInDeferredPhase)
        }
    }

    func testGridAndGridRowUseRetainedSharedTrackModes() async {
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

            guard case .grid(let gridLayout) = node.layoutMode else {
                return XCTFail("Expected Grid to use retained shared track layout")
            }
            guard case .gridRow(let firstRowLayout) = node.children[0].layoutMode else {
                return XCTFail("Expected the first GridRow to participate in shared tracks")
            }
            guard case .gridRow(let secondRowLayout) = node.children[1].layoutMode else {
                return XCTFail("Expected the second GridRow to participate in shared tracks")
            }

            XCTAssertEqual(
                gridLayout,
                RetainedGridLayout(horizontalSpacing: 12, verticalSpacing: 9, horizontalAlignment: .leading))
            XCTAssertEqual(firstRowLayout, RetainedGridRowLayout(alignment: .trailing, standaloneSpacing: 12))
            XCTAssertEqual(secondRowLayout, RetainedGridRowLayout(standaloneSpacing: 12))
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

    func testGridCellColumnsStoresSpanWithoutChangingLayoutPriority() async {
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

            XCTAssertEqual(node.children[0].gridCellColumns, 3)
            XCTAssertEqual(node.children[1].gridCellColumns, 2)
            XCTAssertEqual(node.children[2].gridCellColumns, 1)
            XCTAssertEqual(node.children[0].layoutPriority, 0)
            XCTAssertEqual(node.children[1].layoutPriority, 5)
            XCTAssertEqual(node.children[2].layoutPriority, 0)
        }
    }

    func testAlignmentGuideStoresRetainedMetadata() async {
        await MainActor.run {
            let dimensions = ViewDimensions(width: 40, height: 20)
            XCTAssertEqual(dimensions[HorizontalAlignment.leading], 0)
            XCTAssertEqual(dimensions[HorizontalAlignment.center], 20)
            XCTAssertEqual(dimensions[HorizontalAlignment.trailing], 40)
            XCTAssertEqual(dimensions[VerticalAlignment.top], 0)
            XCTAssertEqual(dimensions[VerticalAlignment.center], 10)
            XCTAssertEqual(dimensions[VerticalAlignment.bottom], 20)
            XCTAssertEqual(dimensions[VerticalAlignment.firstTextBaseline], 16)
            XCTAssertEqual(dimensions[VerticalAlignment.lastTextBaseline], 16)
            XCTAssertEqual(dimensions[HorizontalAlignment(OneThirdHorizontalAlignmentID.self)], 40.0 / 3.0)
            XCTAssertEqual(dimensions[VerticalAlignment(ThreeQuarterVerticalAlignmentID.self)], 15)
            XCTAssertEqual(dimensions[explicit: HorizontalAlignment.trailing], 40)
            XCTAssertEqual(dimensions[explicit: VerticalAlignment.bottom], 20)
            XCTAssertEqual(dimensions[explicit: VerticalAlignment.firstTextBaseline], 16)
            XCTAssertEqual(dimensions[explicit: HorizontalAlignment(OneThirdHorizontalAlignmentID.self)], 40.0 / 3.0)
            XCTAssertEqual(dimensions[explicit: VerticalAlignment(ThreeQuarterVerticalAlignmentID.self)], 15)

            let node = makeNode(
                Text("GUIDE")
                    .frame(width: 40, height: 20)
                    .alignmentGuide(.leading) { dimensions in
                        dimensions[HorizontalAlignment.trailing] - 5
                    }
                    .alignmentGuide(.bottom) { dimensions in
                        dimensions[VerticalAlignment.bottom] + 3
                    }
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[VerticalAlignment.firstTextBaseline] + 2
                    }
                    .alignmentGuide(HorizontalAlignment(OneThirdHorizontalAlignmentID.self)) { dimensions in
                        dimensions[HorizontalAlignment(OneThirdHorizontalAlignmentID.self)] + 4
                    }
                    .alignmentGuide(VerticalAlignment(ThreeQuarterVerticalAlignmentID.self)) { dimensions in
                        dimensions[VerticalAlignment(ThreeQuarterVerticalAlignmentID.self)] + 1
                    }
                    .alignmentGuide(.leading) { _ in
                        11
                    }
            )

            XCTAssertEqual(
                node.alignmentGuides,
                [
                    RetainedAlignmentGuide(axis: .vertical, guide: "bottom", value: 23),
                    RetainedAlignmentGuide(axis: .vertical, guide: "firstTextBaseline", value: 18),
                    RetainedAlignmentGuide(
                        axis: .horizontal,
                        guide: "custom:\(String(reflecting: OneThirdHorizontalAlignmentID.self))",
                        value: 40.0 / 3.0 + 4
                    ),
                    RetainedAlignmentGuide(
                        axis: .vertical,
                        guide: "custom:\(String(reflecting: ThreeQuarterVerticalAlignmentID.self))",
                        value: 16
                    ),
                    RetainedAlignmentGuide(axis: .horizontal, guide: "leading", value: 11),
                ]
            )
        }
    }

    func testLayoutValueStoresRetainedMetadata() async {
        await MainActor.run {
            let node = makeNode(
                Text("LAYOUT")
                    .layoutValue(key: TestLayoutRoleKey.self, value: "featured")
                    .layoutValue(key: TestLayoutCountKey.self, value: 3)
            )

            XCTAssertEqual(node.retainedLayoutValues[ObjectIdentifier(TestLayoutRoleKey.self)] as? String, "featured")
            XCTAssertEqual(node.retainedLayoutValues[ObjectIdentifier(TestLayoutCountKey.self)] as? Int, 3)
        }
    }

    func testContainerValueStoresRetainedMetadata() async {
        await MainActor.run {
            let defaults = ContainerValues()
            XCTAssertEqual(defaults.testContainerRole, "regular")
            XCTAssertEqual(defaults.testContainerCount, 0)

            let node = makeNode(
                Text("CONTAINER")
                    .containerValue(\.testContainerRole, "featured")
                    .containerValue(\.testContainerCount, 7)
            )

            let values = node.retainedContainerValues[ObjectIdentifier(ContainerValues.self)] as? ContainerValues
            XCTAssertEqual(values?.testContainerRole, "featured")
            XCTAssertEqual(values?.testContainerCount, 7)

            let taggedNode = makeNode(Text("TAGGED").tag("selected"))
            let taggedValues =
                taggedNode.retainedContainerValues[ObjectIdentifier(ContainerValues.self)] as? ContainerValues
            XCTAssertEqual(taggedValues?.tag(for: String.self), "selected")
            XCTAssertEqual(taggedValues?.hasTag("selected"), true)
            XCTAssertEqual(taggedValues?.hasTag("other"), false)
            XCTAssertNil(taggedValues?.tag(for: Int.self))
        }
    }

    func testGridCellModifiersStoreRetainedMetadata() async {
        await MainActor.run {
            let node = makeNode(
                GridRow {
                    Text("ANCHOR")
                        .gridCellAnchor(.bottomTrailing)
                    Text("UNSIZED")
                        .gridCellUnsizedAxes(.horizontal)
                    Text("COLUMN")
                        .gridColumnAlignment(.trailing)
                    Text("BOTH")
                        .gridCellAnchor(.topLeading)
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                        .gridColumnAlignment(.leading)
                }
            )

            XCTAssertEqual(node.children[0].gridCellAnchor, Point(x: 1, y: 1))
            XCTAssertEqual(node.children[0].gridCellUnsizedAxes, [])
            XCTAssertNil(node.children[0].gridColumnAlignment)

            XCTAssertNil(node.children[1].gridCellAnchor)
            XCTAssertEqual(node.children[1].gridCellUnsizedAxes, .horizontal)
            XCTAssertNil(node.children[1].gridColumnAlignment)

            XCTAssertNil(node.children[2].gridCellAnchor)
            XCTAssertEqual(node.children[2].gridCellUnsizedAxes, [])
            XCTAssertEqual(node.children[2].gridColumnAlignment, .trailing)

            XCTAssertEqual(node.children[3].gridCellAnchor, Point(x: 0, y: 0))
            XCTAssertEqual(node.children[3].gridCellUnsizedAxes, .all)
            XCTAssertEqual(node.children[3].gridColumnAlignment, .leading)
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
            let customVStackNode = makeNode(
                VStack(alignment: HorizontalAlignment(OneThirdHorizontalAlignmentID.self), spacing: nil) {
                    Text("ONE")
                    Text("TWO")
                }
            )
            let customHStackNode = makeNode(
                HStack(alignment: VerticalAlignment(ThreeQuarterVerticalAlignmentID.self), spacing: nil) {
                    Text("ONE")
                    Text("TWO")
                }
            )
            let firstBaselineHStackNode = makeNode(
                HStack(alignment: .firstTextBaseline, spacing: nil) {
                    Text("ONE")
                    Text("TWO")
                }
            )
            let lastBaselineHStackNode = makeNode(
                HStack(alignment: .lastTextBaseline, spacing: nil) {
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
            guard case .stack(let customVStackLayout) = customVStackNode.layoutMode else {
                return XCTFail("Expected vertical stack layout")
            }
            guard case .stack(let customHStackLayout) = customHStackNode.layoutMode else {
                return XCTFail("Expected horizontal stack layout")
            }
            guard case .stack(let firstBaselineHStackLayout) = firstBaselineHStackNode.layoutMode else {
                return XCTFail("Expected horizontal stack layout")
            }
            guard case .stack(let lastBaselineHStackLayout) = lastBaselineHStackNode.layoutMode else {
                return XCTFail("Expected horizontal stack layout")
            }

            // `spacing: nil` means "use the platform default", which is
            // macOS's 8pt (MacOSControlMetrics.Layout.defaultStackSpacing),
            // not zero. `spacing: 0` is still an explicit choice.
            let defaultSpacing = MacOSControlMetrics.Layout.defaultStackSpacing
            XCTAssertEqual(vStackLayout, .vertical(spacing: defaultSpacing, alignment: .trailing))
            XCTAssertEqual(hStackLayout, .horizontal(spacing: defaultSpacing, alignment: .trailing))
            XCTAssertEqual(
                customVStackLayout,
                .vertical(
                    spacing: defaultSpacing,
                    alignment: .customHorizontal("custom:\(String(reflecting: OneThirdHorizontalAlignmentID.self))"))
            )
            XCTAssertEqual(
                customHStackLayout,
                .horizontal(
                    spacing: defaultSpacing,
                    alignment: .customVertical("custom:\(String(reflecting: ThreeQuarterVerticalAlignmentID.self))"))
            )
            XCTAssertEqual(
                firstBaselineHStackLayout,
                .horizontal(spacing: defaultSpacing, alignment: .firstTextBaseline)
            )
            XCTAssertEqual(
                lastBaselineHStackLayout,
                .horizontal(spacing: defaultSpacing, alignment: .lastTextBaseline)
            )
        }
    }

    func testLayoutAdaptersMapToRetainedStackNodes() async {
        await MainActor.run {
            let verticalProperties = VStackLayout.layoutProperties
            let horizontalProperties = HStackLayout.layoutProperties
            let zProperties = ZStackLayout.layoutProperties
            let spacingA = ViewSpacing(horizontal: 3, vertical: 8)
            let spacingB = ViewSpacing(horizontal: 5, vertical: 2)
            let hStackLayout = HStackLayout(alignment: .bottom, spacing: 6)
            let vStackLayout = VStackLayout(alignment: .trailing, spacing: 7)
            let zStackLayout = ZStackLayout(alignment: .bottomTrailing)
            let anyLayout = AnyLayout(hStackLayout)

            let hStackNode = makeNode(
                hStackLayout.callAsFunction {
                    Text("A")
                    Text("B")
                }
            )
            let vStackNode = makeNode(
                vStackLayout.callAsFunction {
                    Text("A")
                    Text("B")
                }
            )
            let zStackNode = makeNode(
                zStackLayout.callAsFunction {
                    Text("A")
                    Text("B")
                }
            )
            let anyLayoutNode = makeNode(
                anyLayout.callAsFunction {
                    Text("A")
                    Text("B")
                }
            )

            guard case .stack(let hStack) = hStackNode.layoutMode else {
                return XCTFail("Expected HStackLayout to use retained horizontal stack layout")
            }
            guard case .stack(let vStack) = vStackNode.layoutMode else {
                return XCTFail("Expected VStackLayout to use retained vertical stack layout")
            }
            guard case .stack(let anyStack) = anyLayoutNode.layoutMode else {
                return XCTFail("Expected AnyLayout(HStackLayout) to use retained horizontal stack layout")
            }
            guard case .absolute = zStackNode.layoutMode else {
                return XCTFail("Expected ZStackLayout to use retained absolute layout")
            }

            XCTAssertEqual(verticalProperties.stackOrientation, .vertical)
            XCTAssertEqual(horizontalProperties.stackOrientation, .horizontal)
            XCTAssertNil(zProperties.stackOrientation)
            XCTAssertEqual(spacingA.distance(to: spacingB, along: .horizontal), 5)
            XCTAssertEqual(spacingA.distance(to: spacingB, along: .vertical), 8)
            XCTAssertEqual(hStack, .horizontal(spacing: 6, alignment: .trailing))
            XCTAssertEqual(vStack, .vertical(spacing: 7, alignment: .trailing))
            XCTAssertEqual(anyStack, .horizontal(spacing: 6, alignment: .trailing))
            XCTAssertEqual(zStackNode.children.count, 2)
        }
    }

    func testSpacerMinLengthAppliesOnlyAlongStackAxis() async {
        await MainActor.run {
            let verticalStack = makeNode(
                VStack {
                    Spacer(minLength: 12)
                }
            )
            let horizontalStack = makeNode(
                HStack {
                    Spacer(minLength: 18)
                }
            )
            let rootSpacer = makeNode(Spacer(minLength: 9))

            XCTAssertEqual(verticalStack.children[0].preferredSize, Size(width: 0, height: 12))
            XCTAssertEqual(horizontalStack.children[0].preferredSize, Size(width: 18, height: 0))
            XCTAssertEqual(rootSpacer.preferredSize, Size(width: 9, height: 9))
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
            // A separator has thickness on one axis and no extent of its own
            // on the other: it fills whatever the container proposes across
            // (the old 16pt stub made it an orphan tick in a wide card).
            XCTAssertEqual(horizontalDivider.preferredSize, Size(width: 0, height: 1))
            XCTAssertEqual(horizontalDivider.layoutFillAxes, .horizontalOnly)
            XCTAssertEqual(horizontalDivider.backgroundColor, ControlPalette.darkStandard.separator)
            XCTAssertFalse(horizontalDivider.isHitTestVisible)

            let horizontalStack = makeNode(
                HStack {
                    Text("LEADING")
                    Divider()
                    Text("TRAILING")
                }
            )
            let verticalDivider = horizontalStack.children[1]
            XCTAssertEqual(verticalDivider.preferredSize, Size(width: 1, height: 0))
            XCTAssertEqual(verticalDivider.layoutFillAxes, .verticalOnly)
            XCTAssertEqual(verticalDivider.backgroundColor, ControlPalette.darkStandard.separator)
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

            // macOS only fills a destructive button when the app also asks
            // for prominence; otherwise the bezel is standard and the role
            // is carried by a red label.
            XCTAssertEqual(destructiveNode.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            XCTAssertTrue(
                allTextColors(in: destructiveNode).contains { $0.red > 0.8 && $0.green < 0.4 },
                "destructive role tints the label")
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

            XCTAssertEqual(node.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            XCTAssertTrue(
                allTextColors(in: node).contains { $0.red > 0.8 && $0.green < 0.4 },
                "destructive role tints the label")
            XCTAssertTrue(allTexts(in: node).contains(SymbolIcon.document.rawValue))
            XCTAssertTrue(allTexts(in: node).contains("EXPORT"))

            node.onActivate?()
            XCTAssertTrue(didRunAction)
        }
    }

    func testButtonNamedImageInitializersBuildBitmapLabelContentAndRoleSurface() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-button-image-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            var didRunStringAction = false
            var didRunProtocolAction = false
            var didRunKeyAction = false
            let stringNode = makeNode(
                Button("PHOTO", image: url.path) {
                    didRunStringAction = true
                })
            let protocolTitle: Substring = "TOOLS"[...]
            let protocolNode = makeNode(
                Button(protocolTitle, image: url.path, role: .destructive) {
                    didRunProtocolAction = true
                })
            let keyNode = makeNode(
                Button(LocalizedStringKey("ALBUM"), image: url.path, role: .cancel) {
                    didRunKeyAction = true
                })

            XCTAssertTrue(allTexts(in: stringNode).contains("PHOTO"))
            XCTAssertEqual(firstBitmapNode(in: stringNode)?.bitmapSurface?.width, 2)
            XCTAssertEqual(firstBitmapNode(in: stringNode)?.bitmapSurface?.height, 1)
            XCTAssertTrue(allTexts(in: protocolNode).contains("TOOLS"))
            XCTAssertEqual(protocolNode.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            XCTAssertTrue(allTexts(in: keyNode).contains("ALBUM"))
            XCTAssertEqual(keyNode.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)

            stringNode.onActivate?()
            protocolNode.onActivate?()
            keyNode.onActivate?()

            XCTAssertTrue(didRunStringAction)
            XCTAssertTrue(didRunProtocolAction)
            XCTAssertTrue(didRunKeyAction)
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

    func testRenameActionEnvironmentAndRenameButtonRunRetainedAction() async {
        await MainActor.run {
            struct RenameReaderView: View {
                @Environment(\.rename) var rename

                var body: some View {
                    Text(rename == nil ? "NO RENAME" : "CAN RENAME")
                }
            }

            var renameCount = 0
            var didInvalidate = false
            let node = makeNode(
                VStack {
                    RenameReaderView()
                    RenameButton()
                }
                .renameAction {
                    renameCount += 1
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(node.children[0].text, "CAN RENAME")
            XCTAssertTrue(allTexts(in: node.children[1]).contains("Rename"))
            XCTAssertTrue(node.children[1].isFocusable)

            node.children[1].onActivate?()

            XCTAssertEqual(renameCount, 1)
            XCTAssertTrue(didInvalidate)

            let defaultNode = makeNode(
                VStack {
                    RenameReaderView()
                    RenameButton()
                }
            )

            XCTAssertEqual(defaultNode.children[0].text, "NO RENAME")
            XCTAssertFalse(defaultNode.children[1].isFocusable)
            XCTAssertNil(defaultNode.children[1].onActivate)
        }
    }

    func testSettingsLinkUsesOpenSettingsEnvironmentAction() async {
        await MainActor.run {
            struct OpenSettingsReaderView: View {
                @Environment(\.openSettings) var openSettings

                var body: some View {
                    Button("OPEN SETTINGS") {
                        openSettings()
                    }
                }
            }

            var openCount = 0
            var didInvalidate = false
            let node = makeNode(
                VStack {
                    SettingsLink()
                    SettingsLink {
                        Label("Preferences", systemImage: "gearshape")
                    }
                    OpenSettingsReaderView()
                }
                .environment(
                    \.openSettings,
                    OpenSettingsAction {
                        openCount += 1
                    }),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(allTexts(in: node.children[0]).contains("Settings"))
            XCTAssertTrue(allTexts(in: node.children[1]).contains("Preferences"))
            XCTAssertTrue(allTexts(in: node.children[2]).contains("OPEN SETTINGS"))

            node.children[0].onActivate?()
            node.children[1].onActivate?()
            node.children[2].onActivate?()

            XCTAssertEqual(openCount, 3)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testRequestReviewEnvironmentActionCanBeReadAndOverridden() async {
        await MainActor.run {
            struct RequestReviewReaderView: View {
                @Environment(\.requestReview) var requestReview

                var body: some View {
                    Button("REQUEST REVIEW") {
                        requestReview()
                    }
                }
            }

            var requestCount = 0
            var didInvalidate = false
            let node = makeNode(
                RequestReviewReaderView()
                    .environment(
                        \.requestReview,
                        RequestReviewAction {
                            requestCount += 1
                        }),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(allTexts(in: node).contains("REQUEST REVIEW"))

            node.onActivate?()

            XCTAssertEqual(requestCount, 1)
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
                        .buttonStyle(BorderedProminentButtonStyle())
                    Button("LINK") {}
                        .buttonStyle(LinkButtonStyle())
                    Button("CARD") {}
                        .buttonStyle(CardButtonStyle())
                    Button("ACCESSORY") {}
                        .buttonStyle(AccessoryBarButtonStyle())
                    Button("BORDERED") {}
                        .buttonStyle(BorderedButtonStyle(tint: customColor))
                    Button("CUSTOM") {}
                        .buttonSurface(customStyle)
                }
                .buttonStyle(BorderlessButtonStyle())
                .tint(customColor)
            )

            let inheritedButton = node.children[0]
            let overriddenButton = node.children[1]
            let linkButton = node.children[2]
            let cardButton = node.children[3]
            let accessoryButton = node.children[4]
            let borderedButton = node.children[5]
            let customButton = node.children[6]

            XCTAssertEqual(inheritedButton.backgroundColor, .clear)
            XCTAssertEqual(inheritedButton.borderColor, .clear)
            // A resting accent surface is the full accent, and its ring is
            // the neutral control border — never a tinted one.
            XCTAssertEqual(overriddenButton.backgroundColor, ControlPalette.opaque(customColor))
            XCTAssertEqual(overriddenButton.borderColor, ControlPalette.darkStandard.controlBorder)
            XCTAssertEqual(linkButton.backgroundColor, .clear)
            XCTAssertEqual(linkButton.borderColor, .clear)
            XCTAssertEqual(cardButton.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            XCTAssertEqual(accessoryButton.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            XCTAssertEqual(borderedButton.backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            XCTAssertEqual(customButton.backgroundColor, customColor)
        }
    }

    func testButtonBorderShapeBridgesThroughEnvironmentAndUpdatesButtonChrome() async {
        await MainActor.run {
            struct ButtonBorderShapeReaderView: View {
                @Environment(\.buttonBorderShape) var buttonBorderShape

                var body: some View {
                    Text(
                        buttonBorderShape == .capsule
                            ? "CAPSULE" : buttonBorderShape == .roundedRectangle(radius: 6) ? "ROUNDED" : "AUTOMATIC")
                }
            }

            let defaultNode = makeNode(ButtonBorderShapeReaderView())
            let modifierNode = makeNode(
                ButtonBorderShapeReaderView()
                    .buttonBorderShape(.capsule)
            )
            let environmentNode = makeNode(
                ButtonBorderShapeReaderView()
                    .environment(\.buttonBorderShape, .roundedRectangle(radius: 6))
            )
            let roundedButtonNode = makeNode(
                Button("SAVE") {}
                    .buttonBorderShape(.roundedRectangle(radius: 6))
            )
            let inheritedRoundedButtonNode = makeNode(
                VStack {
                    Button("SAVE") {}
                }
                .buttonBorderShape(.roundedRectangle(radius: 4))
            )
            .children[0]
            let capsuleButtonNode = makeNode(
                Button("PILL") {}
                    .buttonBorderShape(.capsule)
            )

            capsuleButtonNode.onLayout?(Rect(x: 0, y: 0, width: 120, height: 30))

            XCTAssertEqual(defaultNode.text, "AUTOMATIC")
            XCTAssertEqual(modifierNode.text, "CAPSULE")
            XCTAssertEqual(environmentNode.text, "ROUNDED")
            XCTAssertEqual(roundedButtonNode.cornerRadius, 6)
            XCTAssertEqual(inheritedRoundedButtonNode.cornerRadius, 4)
            XCTAssertEqual(capsuleButtonNode.cornerRadius, 15)
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

    func testScrollViewAxisSetInitializerControlsAxisAndIndicators() async {
        await MainActor.run {
            let hiddenHorizontalNode = makeNode(
                ScrollView(.horizontal, showsIndicators: false) {
                    Text("A")
                }
            )
            let visibleVerticalNode = makeNode(
                ScrollView(Axis.Set.vertical, showsIndicators: true) {
                    Text("A")
                }
            )
            let allAxesNode = makeNode(
                ScrollView(.all) {
                    Text("A")
                }
            )

            XCTAssertEqual(hiddenHorizontalNode.scrollAxis, .horizontal)
            XCTAssertFalse(hiddenHorizontalNode.showsScrollIndicator)
            XCTAssertEqual(visibleVerticalNode.scrollAxis, .vertical)
            XCTAssertTrue(visibleVerticalNode.showsScrollIndicator)
            XCTAssertEqual(allAxesNode.scrollAxis, .vertical)
            XCTAssertTrue(allAxesNode.showsScrollIndicator)
        }
    }

    func testScrollViewShowsIndicatorsInitializerRespectsScrollIndicatorModifier() async {
        await MainActor.run {
            let hiddenByModifierNode = makeNode(
                ScrollView(Axis.Set.vertical, showsIndicators: true) {
                    Text("A")
                }
                .scrollIndicators(.hidden)
            )
            let hiddenByInitializerNode = makeNode(
                ScrollView(Axis.Set.vertical, showsIndicators: false) {
                    Text("A")
                }
                .scrollIndicators(.visible)
            )

            XCTAssertFalse(hiddenByModifierNode.showsScrollIndicator)
            XCTAssertFalse(hiddenByInitializerNode.showsScrollIndicator)
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

            XCTAssertEqual(scrollViewNode.scrollAxis, .vertical)
            XCTAssertFalse(scrollViewNode.isScrollInputEnabled)
            XCTAssertFalse(scrollViewNode.showsScrollIndicator)
            XCTAssertTrue(scrollViewNode.clipsToBounds)
            XCTAssertEqual(scrollViewNode.children[0].text, "ROW")

            XCTAssertEqual(listNode.scrollAxis, .vertical)
            XCTAssertFalse(listNode.isScrollInputEnabled)
            XCTAssertFalse(listNode.showsScrollIndicator)
            XCTAssertEqual(listRows(of: listNode).count, 2)

            XCTAssertEqual(sectionNode.scrollAxis, .vertical)
            XCTAssertFalse(sectionNode.isScrollInputEnabled)
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

    func testScrollBounceBehaviorPropagatesToRetainedScrollContainers() async {
        await MainActor.run {
            struct BounceEnvironmentReader: View {
                @Environment(\.horizontalScrollBounceBehavior) var horizontal
                @Environment(\.verticalScrollBounceBehavior) var vertical

                var body: some View {
                    Text(horizontal == .always && vertical == .basedOnSize ? "CUSTOM" : "DEFAULT")
                }
            }

            let defaultVerticalAxesNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .scrollBounceBehavior(.basedOnSize)
            )
            let horizontalOnlyNode = makeNode(
                ScrollView(.horizontal) {
                    Text("ROW")
                }
                .scrollBounceBehavior(.always, axes: .horizontal)
            )
            let listNode = makeNode(
                List {
                    Text("ONE")
                }
                .scrollBounceBehavior(.never)
            )
            let sectionNode = makeNode(
                Section("GROUP", style: SectionStyle(scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .scrollBounceBehavior(.basedOnSize)
            )
            let readerNode = makeNode(
                BounceEnvironmentReader()
                    .scrollBounceBehavior(.always, axes: .horizontal)
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            )

            XCTAssertEqual(defaultVerticalAxesNode.horizontalScrollBounceBehavior, "automatic")
            XCTAssertEqual(defaultVerticalAxesNode.verticalScrollBounceBehavior, "basedOnSize")
            XCTAssertEqual(horizontalOnlyNode.horizontalScrollBounceBehavior, "always")
            XCTAssertEqual(horizontalOnlyNode.verticalScrollBounceBehavior, "automatic")
            XCTAssertEqual(listNode.horizontalScrollBounceBehavior, "automatic")
            XCTAssertEqual(listNode.verticalScrollBounceBehavior, "never")
            XCTAssertEqual(sectionNode.verticalScrollBounceBehavior, "basedOnSize")
            XCTAssertEqual(readerNode.text, "CUSTOM")
        }
    }

    func testScrollTargetBehaviorAndLayoutRetainMetadata() async {
        await MainActor.run {
            struct CustomTargetBehavior: ScrollTargetBehavior {
                func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
                    target.anchor = .bottom
                }

                var retainedScrollTargetBehaviorDescription: String {
                    "customTarget"
                }
            }

            let pagingNode = makeNode(
                ScrollView {
                    VStack {
                        Text("ROW")
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
            )
            let viewAlignedNode = makeNode(
                ScrollView(.horizontal) {
                    HStack {
                        Text("A")
                        Text("B")
                    }
                    .scrollTargetLayout(isEnabled: false)
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            )
            let anchoredListNode = makeNode(
                List {
                    Text("ONE")
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never, anchor: .center))
            )
            let customSectionNode = makeNode(
                Section("GROUP", style: SectionStyle(scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .scrollTargetBehavior(CustomTargetBehavior())
            )

            XCTAssertEqual(pagingNode.scrollTargetBehavior, "paging")
            XCTAssertEqual(pagingNode.children.first?.isScrollTargetLayout, true)
            XCTAssertEqual(viewAlignedNode.scrollTargetBehavior, "viewAligned(limitBehavior:always,anchor:nil)")
            XCTAssertEqual(viewAlignedNode.children.first?.isScrollTargetLayout, false)
            XCTAssertEqual(anchoredListNode.scrollTargetBehavior, "viewAligned(limitBehavior:never,anchor:0.5,0.5)")
            XCTAssertEqual(customSectionNode.scrollTargetBehavior, "customTarget")
        }
    }

    func testScrollInputBehaviorPropagatesToRetainedScrollContainers() async {
        await MainActor.run {
            let scrollViewNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .scrollInputBehavior(.disabled, for: .handGestureShortcut)
                .scrollInputBehavior(.enabled, for: .look(axes: .horizontal))
            )
            let listNode = makeNode(
                List {
                    Text("ONE")
                }
                .scrollInputBehavior(.disabled, for: .look)
            )
            let sectionNode = makeNode(
                Section("GROUP", style: SectionStyle(scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .scrollInputBehavior(.enabled, for: .look(axes: .vertical))
            )
            let disabledScrollNode = makeNode(
                ScrollView {
                    Text("LOCKED")
                }
                .scrollInputBehavior(.enabled, for: .handGestureShortcut)
                .scrollDisabled()
            )

            XCTAssertEqual(
                scrollViewNode.scrollInputBehaviors,
                ["handGestureShortcut": "disabled", "look(horizontal)": "enabled"]
            )
            XCTAssertEqual(listNode.scrollInputBehaviors, ["look": "disabled"])
            XCTAssertEqual(sectionNode.scrollInputBehaviors, ["look(vertical)": "enabled"])
            XCTAssertEqual(disabledScrollNode.scrollInputBehaviors, ["handGestureShortcut": "enabled"])
            XCTAssertEqual(disabledScrollNode.scrollAxis, .vertical)
            XCTAssertFalse(disabledScrollNode.isScrollInputEnabled)
        }
    }

    func testScrollIndicatorsFlashMetadataPropagatesToRetainedScrollContainers() async {
        await MainActor.run {
            let scrollViewNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .scrollIndicatorsFlash(onAppear: true)
                .scrollIndicatorsFlash(trigger: 4)
            )
            let listNode = makeNode(
                List {
                    Text("ONE")
                }
                .scrollIndicatorsFlash(onAppear: false)
                .scrollIndicatorsFlash(trigger: "refresh")
            )
            let sectionNode = makeNode(
                Section("GROUP", style: SectionStyle(scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .scrollIndicatorsFlash(onAppear: true)
            )

            XCTAssertTrue(scrollViewNode.scrollIndicatorsFlashOnAppear)
            XCTAssertEqual(scrollViewNode.scrollIndicatorsFlashTrigger, "Int:4")
            XCTAssertFalse(listNode.scrollIndicatorsFlashOnAppear)
            XCTAssertEqual(listNode.scrollIndicatorsFlashTrigger, "String:refresh")
            XCTAssertTrue(sectionNode.scrollIndicatorsFlashOnAppear)
            XCTAssertNil(sectionNode.scrollIndicatorsFlashTrigger)
        }
    }

    func testScrollTransitionStoresRetainedMetadataAndVisualEffectShape() async {
        await MainActor.run {
            let symmetricNode = makeNode(
                Text("ROW")
                    .scrollTransition(.interactive(timingCurve: .easeInOut), axis: .vertical) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.4)
                            .scaleEffect(phase.isIdentity ? 1 : 0.9)
                    }
            )
            let asymmetricNode = makeNode(
                Text("ROW")
                    .scrollTransition(
                        topLeading: .identity,
                        bottomTrailing: .animated(.easeOut(duration: 0.2)).threshold(.visible(0.4)),
                        axis: .horizontal
                    ) { content, phase in
                        content.offset(x: phase.value * 12)
                    }
            )
            let blurredNode = makeNode(
                Text("ROW")
                    .scrollTransition(.interactive, axis: .vertical) { content, _ in
                        content.blur(radius: 2, opaque: true)
                    }
            )
            let rotatedNode = makeNode(
                Text("ROW")
                    .scrollTransition(.identity, axis: .horizontal) { content, _ in
                        content.rotationEffect(.degrees(90), anchor: .topLeading)
                    }
            )
            let colorEffectNode = makeNode(
                Text("ROW")
                    .scrollTransition(.identity, axis: .vertical) { content, _ in
                        content
                            .brightness(0.1)
                            .contrast(1.2)
                            .colorInvert()
                            .colorMultiply(Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.8))
                            .saturation(0.6)
                            .grayscale(0.3)
                            .hueRotation(.degrees(45))
                            .luminanceToAlpha()
                            .blendMode(.screen)
                            .blendMode(.plusLighter)
                    }
            )
            let depthEffectNode = makeNode(
                Text("ROW")
                    .scrollTransition(.identity, axis: .vertical) { content, _ in
                        content
                            .scaleEffect(0.5, anchor: .front)
                            .scaleEffect(x: 2, y: 3, z: 4, anchor: .back)
                            .offset(z: 8)
                    }
            )
            let transformEffectNode = makeNode(
                Text("ROW")
                    .scrollTransition(.identity, axis: .vertical) { content, _ in
                        content
                            .rotation3DEffect(
                                .degrees(45),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: .top,
                                anchorZ: 4,
                                perspective: 0.25
                            )
                            .rotation3DEffect(.degrees(30), axis: .z, anchor: .back)
                            .perspectiveRotationEffect(
                                .degrees(15),
                                axis: (x: 1, y: 0, z: 0),
                                anchor: .front,
                                perspective: 0.75
                            )
                            .transformEffect(CGAffineTransform(translationX: 2, y: 3))
                            .transformEffect(ProjectionTransform(CGAffineTransform(scaleX: 4, y: 5)))
                    }
            )

            XCTAssertEqual(
                symmetricNode.scrollTransition,
                "symmetric,configuration:interactive,timingCurve:easeInOut,axis:vertical,identityEffect:identity.opacity(1.0).scaleEffect(x:1.0,y:1.0,anchor:0.5,0.5)"
            )
            XCTAssertEqual(
                asymmetricNode.scrollTransition,
                "asymmetric,topLeading:identity,bottomTrailing:animated,animation:easeOut:0.2,threshold:visible(0.4),axis:horizontal,identityEffect:identity.offset(x:0.0,y:0.0)"
            )
            XCTAssertEqual(
                blurredNode.scrollTransition,
                "symmetric,configuration:interactive,timingCurve:linear,axis:vertical,identityEffect:identity.blur(radius:2.0,opaque:true)"
            )
            XCTAssertEqual(
                rotatedNode.scrollTransition,
                "symmetric,configuration:identity,axis:horizontal,identityEffect:identity.rotationEffect(angle:1.5707963267948966,anchor:0.0,0.0)"
            )
            XCTAssertEqual(
                colorEffectNode.scrollTransition,
                "symmetric,configuration:identity,axis:vertical,identityEffect:identity.brightness(0.1).contrast(1.2).colorInvert.colorMultiply(red:0.25,green:0.5,blue:0.75,alpha:0.8).saturation(0.6).grayscale(0.3).hueRotation(0.7853981633974483).luminanceToAlpha.blendMode(screen).blendMode(plusLighter)"
            )
            XCTAssertEqual(
                depthEffectNode.scrollTransition,
                "symmetric,configuration:identity,axis:vertical,identityEffect:identity.scaleEffect3D(x:0.5,y:0.5,z:0.5,anchor:0.5,0.5,0.0).scaleEffect3D(x:2.0,y:3.0,z:4.0,anchor:0.5,0.5,1.0).offset(z:8.0)"
            )
            XCTAssertEqual(
                transformEffectNode.scrollTransition,
                "symmetric,configuration:identity,axis:vertical,identityEffect:identity.rotation3DEffect(angle:0.7853981633974483,axis:0.0,1.0,0.0,anchor:0.5,0.0,anchorZ:4.0,perspective:0.25).rotation3DEffect(angle:0.5235987755982988,axis:0.0,0.0,1.0,anchor3D:0.5,0.5,1.0).perspectiveRotationEffect(angle:0.2617993877991494,axis:1.0,0.0,0.0,anchor:0.5,0.5,0.0,perspective:0.75).transformEffect(a:1.0,b:0.0,c:0.0,d:1.0,tx:2.0,ty:3.0).transformEffect(m11:4.0,m12:0.0,m13:0.0,m21:0.0,m22:5.0,m23:0.0,m31:0.0,m32:0.0,m33:1.0)"
            )
            XCTAssertTrue(ScrollTransitionPhase.identity.isIdentity)
            XCTAssertEqual(ScrollTransitionPhase.topLeading.value, -1)
            XCTAssertEqual(ScrollTransitionPhase.bottomTrailing.value, 1)
        }
    }

    func testVisualEffectModifierStoresRetainedMetadataAndGeometry() async {
        await MainActor.run {
            var observedSize: Size?
            let node = makeNode(
                Text("CARD")
                    .visualEffect { content, geometry in
                        observedSize = geometry.size
                        return
                            content
                            .opacity(0.7)
                            .blendMode(.screen)
                            .colorEffect(ShaderLibrary.default.tint(.float(0.2)))
                            .distortionEffect(
                                ShaderLibrary.default.wave(.float2(1.0, 2.0)),
                                maxSampleOffset: CGSize(width: 4, height: 5)
                            )
                            .layerEffect(
                                Shader("layer"),
                                maxSampleOffset: CGSize(width: 1, height: 2),
                                isEnabled: false
                            )
                            .offset(x: geometry.size.width / 10, y: geometry.size.height / 20)
                    },
                size: Size(width: 320, height: 240)
            )

            XCTAssertEqual(observedSize, Size(width: 320, height: 240))
            XCTAssertEqual(
                node.visualEffects,
                [
                    "identity.opacity(0.7).blendMode(screen).colorEffect(shader:default.tint(float:0.2),enabled:true).distortionEffect(shader:default.wave(float2:1.0,2.0),maxSampleOffset:4.0,5.0,enabled:true).layerEffect(shader:layer,maxSampleOffset:1.0,2.0,enabled:false).offset(x:32.0,y:12.0)"
                ]
            )
        }
    }

    func testVisualEffect3DModifierStoresRetainedMetadataAndGeometry() async {
        await MainActor.run {
            var observedSize: Size3D?
            var observedFrame: Rect3D?
            var observedTransform: AffineTransform3D?
            let rotation = Rotation3D(angle: .degrees(30), axis: .z)
            let transform = AffineTransform3D(
                translation: Size3D(width: 1, height: 2, depth: 3),
                scale: Size3D(width: 2, height: 3, depth: 4),
                rotation: rotation
            )
            let node = makeNode(
                Text("CARD")
                    .visualEffect3D { content, geometry in
                        observedSize = geometry.size
                        observedFrame = geometry.frame(in: .local)
                        observedTransform = geometry.transform(in: .global)
                        return
                            content
                            .rotation3DEffect(rotation, anchor: .back)
                            .transform3DEffect(transform)
                    },
                size: Size(width: 320, height: 240)
            )

            XCTAssertEqual(observedSize, Size3D(width: 320, height: 240, depth: 0))
            XCTAssertEqual(
                observedFrame,
                Rect3D(origin: .zero, size: Size3D(width: 320, height: 240, depth: 0))
            )
            XCTAssertEqual(observedTransform, .identity)
            XCTAssertEqual(
                node.visualEffects,
                [
                    "identity.rotation3DEffect(angle:0.5235987755982988,axis:0.0,0.0,1.0,anchor3D:0.5,0.5,1.0).transform3DEffect(translation:1.0,2.0,3.0,scale:2.0,3.0,4.0,rotation:angle:0.5235987755982988,axis:0.0,0.0,1.0)"
                ]
            )
        }
    }

    func testVisualEffectModifierAppliesStructuredEffectsToNode() async {
        await MainActor.run {
            let node = makeNode(
                Text("CARD")
                    .visualEffect { content, _ in
                        content
                            .brightness(0.25)
                            .contrast(0.5)
                            .saturation(-0.3)
                            .grayscale(0.75)
                            .hueRotation(.degrees(45))
                            .colorInvert()
                            .colorMultiply(.red)
                            .luminanceToAlpha()
                            .blur(radius: 4, opaque: true)
                            .opacity(0.8)
                            .scaleEffect(x: 2, y: 3)
                            .offset(x: 10, y: 20)
                            .rotationEffect(.degrees(90))
                            .blendMode(.screen)
                    },
                size: Size(width: 320, height: 240)
            )

            XCTAssertEqual(
                node.colorEffects,
                [
                    .brightness(0.25),
                    .contrast(0.5),
                    .saturation(-0.3),
                    .grayscale(0.75),
                    .hueRotation(Double.pi / 4),
                    .colorInvert,
                    .colorMultiply(.red),
                    .luminanceToAlpha,
                ])
            // `.blur()` is the CONTENT blur; `blurRadius` stays reserved for
            // the backdrop effect a Material background asks for.
            XCTAssertEqual(node.contentBlurRadius, 4)
            XCTAssertTrue(node.contentBlurOpaque)
            XCTAssertEqual(node.blurRadius, 0)
            XCTAssertEqual(node.opacity, 0.8)
            XCTAssertEqual(node.blendMode, .screen)
            XCTAssertFalse(node.transform.isIdentity)
        }
    }

    func testScrollPositionMetadataPropagatesToRetainedScrollContainers() async {
        await MainActor.run {
            var position = ScrollPosition(id: "item-2", anchor: .bottom)
            var selectedID: Int? = 7
            var nilID: String?
            let positionBinding = Binding<ScrollPosition>(
                get: { position },
                set: { position = $0 }
            )
            let idBinding = Binding<Int?>(
                get: { selectedID },
                set: { selectedID = $0 }
            )
            let nilIDBinding = Binding<String?>(
                get: { nilID },
                set: { nilID = $0 }
            )

            let scrollViewNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .scrollPosition(positionBinding, anchor: .top)
            )
            let listNode = makeNode(
                List {
                    Text("ONE")
                }
                .scrollPosition(id: idBinding, anchor: .center)
            )
            let sectionNode = makeNode(
                Section("GROUP", style: SectionStyle(scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .scrollPosition(id: nilIDBinding)
            )

            XCTAssertEqual(
                scrollViewNode.scrollPosition,
                "position,idType:String,id:item-2,anchor:0.5,1.0,bindingAnchor:0.5,0.0"
            )
            XCTAssertEqual(listNode.scrollPosition, "idBinding,idType:Int,id:7,anchor:0.5,0.5")
            XCTAssertEqual(sectionNode.scrollPosition, "idBinding,idType:String,id:nil")
            XCTAssertEqual(position.viewID(type: String.self), "item-2")

            position.scrollTo(edge: .bottom)
            XCTAssertEqual(position.edge, .bottom)
            position.scrollTo(point: CGPoint(x: 12, y: 34))
            XCTAssertEqual(position.point, CGPoint(x: 12, y: 34))
            XCTAssertEqual(position.x, 12)
            XCTAssertEqual(position.y, 34)
            position.scrollTo(id: 99, anchor: .center)
            XCTAssertEqual(position.viewID(type: Int.self), 99)
            XCTAssertNil(position.viewID(type: String.self))
        }
    }

    func testScrollObservationModifiersStoreRetainedCallbackMetadata() async {
        await MainActor.run {
            var geometryChanges: [(Double, Double)] = []
            var phaseChanges: [(ScrollPhase, ScrollPhase)] = []
            var phaseContextChanges: [(ScrollPhase, CGVector?)] = []
            var visibilityChanges: [Bool] = []
            var visibleIDs: [[String]] = []

            let node = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .onScrollGeometryChange(for: Double.self) { geometry in
                    geometry.contentOffset.y
                } action: { oldValue, newValue in
                    geometryChanges.append((oldValue, newValue))
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    phaseChanges.append((oldPhase, newPhase))
                }
                .onScrollPhaseChange { _, newPhase, context in
                    phaseContextChanges.append((newPhase, context.velocity))
                }
                .onScrollVisibilityChange { isVisible in
                    visibilityChanges.append(isVisible)
                }
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.25) { ids in
                    visibleIDs.append(ids)
                }
            )

            XCTAssertEqual(
                node.scrollObservations,
                [
                    "geometry:type:Double",
                    "phase",
                    "phase:context",
                    "visibility:threshold:0.5",
                    "targetVisibility:idType:String,threshold:0.25",
                ]
            )
            XCTAssertTrue(geometryChanges.isEmpty)
            XCTAssertTrue(phaseChanges.isEmpty)
            XCTAssertTrue(phaseContextChanges.isEmpty)
            XCTAssertTrue(visibilityChanges.isEmpty)
            XCTAssertTrue(visibleIDs.isEmpty)

            let geometry = ScrollGeometry(
                contentOffset: CGPoint(x: 4, y: 8),
                contentSize: CGSize(width: 200, height: 400),
                contentInsets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
                containerSize: CGSize(width: 80, height: 100)
            )
            XCTAssertEqual(geometry.bounds, CGRect(x: 4, y: 8, width: 80, height: 100))
            XCTAssertEqual(geometry.visibleRect, CGRect(x: 6, y: 9, width: 74, height: 96))
            XCTAssertFalse(ScrollPhase.idle.isScrolling)
            XCTAssertFalse(ScrollPhase.tracking.isScrolling)
            XCTAssertTrue(ScrollPhase.interacting.isScrolling)
            XCTAssertTrue(ScrollPhase.decelerating.isScrolling)
            XCTAssertTrue(ScrollPhase.animating.isScrolling)

            let context = ScrollPhaseChangeContext(geometry: geometry, velocity: CGVector(dx: 1, dy: -2))
            XCTAssertEqual(context.velocity, CGVector(dx: 1, dy: -2))
        }
    }

    func testScrollViewReaderProvidesProxyAndRetainsRequests() async {
        await MainActor.run {
            var capturedProxy: ScrollViewProxy?
            let reader = ScrollViewReader { proxy in
                capturedProxy = proxy
                proxy.scrollTo("top")
                proxy.scrollTo("bottom", anchor: .bottom)
                ScrollView {
                    Text("TOP").id("top")
                    Text("BOTTOM").id("bottom")
                }
            }
            let node = makeNode(reader)

            XCTAssertNotNil(capturedProxy)
            XCTAssertEqual(
                node.scrollProxyRequests,
                [
                    "idType:String,id:top",
                    "idType:String,id:bottom,anchor:0.5,1.0",
                ]
            )
            XCTAssertEqual(capturedProxy?.retainedRequests, node.scrollProxyRequests)
            XCTAssertEqual(capturedProxy?.retainedIdentifier, node.scrollReaderID)

            capturedProxy?.scrollTo(42, anchor: .center)
            XCTAssertEqual(
                capturedProxy?.retainedRequests.last,
                "idType:Int,id:42,anchor:0.5,0.5"
            )
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
            let scrollBackground = Color(red: 0.233, green: 0.233, blue: 0.233, alpha: 0.92)
            let scrollStyle = ScrollViewStyle(backgroundColor: scrollBackground)
            let sectionGradient = LinearGradient(
                colors: [.red, .blue],
                startPoint: .top,
                endPoint: .bottom
            )
            let sectionStyle = SectionStyle(
                backgroundColor: scrollBackground,
                backgroundGradient: .linear(SwiftWindowsGraphics.LinearGradient(sectionGradient)),
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

    func testContentMarginsMapToRetainedScrollContentPadding() async {
        await MainActor.run {
            let baseInsets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
            let placements: Set<ContentMarginPlacement> = [.automatic, .scrollContent, .scrollIndicators]

            let scrollNode = makeNode(
                ScrollView(.vertical, style: ScrollViewStyle(padding: baseInsets, alignment: .trailing)) {
                    Text("ROW")
                }
                .contentMargins(.horizontal, 12)
                .contentMargins(.top, 6, for: .scrollContent)
                .contentMargins(.bottom, 24, for: .scrollIndicators)
            )
            let listNode = makeNode(
                List {
                    Text("ONE")
                }
                .contentMargins(10)
            )
            let scrollingSectionNode = makeNode(
                Section("GROUP", style: SectionStyle(padding: baseInsets, scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .contentMargins(.vertical, 9)
            )
            let insetScrollNode = makeNode(
                ScrollView(.vertical, style: ScrollViewStyle(padding: baseInsets, alignment: .leading)) {
                    Text("ROW")
                }
                .contentMargins(.horizontal, EdgeInsets(top: 30, leading: 14, bottom: 32, trailing: 18))
                .contentMargins(
                    .vertical,
                    EdgeInsets(top: 7, leading: 40, bottom: 11, trailing: 42),
                    for: .scrollIndicators
                )
            )
            let plainSectionNode = makeNode(
                Section("GROUP", style: SectionStyle(padding: baseInsets)) {
                    Text("ITEM")
                }
                .contentMargins(9)
            )

            guard case .stack(let scrollLayout) = scrollNode.layoutMode,
                case .stack(let listLayout) = listNode.layoutMode,
                case .stack(let scrollingSectionLayout) = scrollingSectionNode.layoutMode,
                case .stack(let insetScrollLayout) = insetScrollNode.layoutMode,
                case .stack(let plainSectionLayout) = plainSectionNode.layoutMode
            else {
                return XCTFail("Expected retained stack layouts for content margin assertions")
            }

            XCTAssertEqual(placements.count, 3)
            XCTAssertEqual(
                scrollLayout,
                .vertical(
                    spacing: 0,
                    padding: EdgeInsets(top: 6, leading: 12, bottom: 3, trailing: 12),
                    alignment: .trailing
                )
            )
            XCTAssertEqual(
                listLayout,
                .vertical(
                    spacing: 0,
                    padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
                    alignment: .stretch
                )
            )
            XCTAssertEqual(
                scrollingSectionLayout,
                .vertical(
                    spacing: 16,
                    padding: EdgeInsets(top: 9, leading: 2, bottom: 9, trailing: 4),
                    alignment: .leading
                )
            )
            XCTAssertEqual(
                insetScrollLayout,
                .vertical(
                    spacing: 0,
                    padding: EdgeInsets(top: 1, leading: 14, bottom: 3, trailing: 18),
                    alignment: .leading
                )
            )
            XCTAssertEqual(
                plainSectionLayout,
                .vertical(spacing: 16, padding: baseInsets, alignment: .leading)
            )
            // Edges `contentMargins` does not name fall back to the overlay
            // scroller's own inset (`MacOSControlMetrics.Scroller.overlayInset`,
            // 4), not the 6pt gutter the old always-visible bar reserved.
            XCTAssertEqual(
                scrollNode.scrollIndicatorInsets,
                EdgeInsets(top: 4, leading: 12, bottom: 24, trailing: 12)
            )
            XCTAssertEqual(
                listNode.scrollIndicatorInsets,
                EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
            )
            XCTAssertEqual(
                scrollingSectionNode.scrollIndicatorInsets,
                EdgeInsets(top: 9, leading: 4, bottom: 9, trailing: 4)
            )
            XCTAssertEqual(
                insetScrollNode.scrollIndicatorInsets,
                EdgeInsets(top: 7, leading: 14, bottom: 11, trailing: 18)
            )
        }
    }

    func testDefaultScrollAnchorMapsToRetainedScrollAnchors() async {
        await MainActor.run {
            let roles: Set<ScrollAnchorRole> = [.initialOffset, .sizeChanges, .alignment]
            let defaultNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .defaultScrollAnchor(.bottom)
            )
            let roleNode = makeNode(
                ScrollView {
                    Text("ROW")
                }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.top, for: .initialOffset)
                .defaultScrollAnchor(nil, for: .sizeChanges)
                .defaultScrollAnchor(.center, for: .alignment)
            )
            let horizontalNode = makeNode(
                ScrollView(.horizontal) {
                    Text("ROW")
                }
                .defaultScrollAnchor(.bottomTrailing, for: .alignment)
            )
            let listNode = makeNode(
                List {
                    Text("ROW")
                }
                .defaultScrollAnchor(.bottom, for: .alignment)
            )
            let scrollingSectionNode = makeNode(
                Section("GROUP", style: SectionStyle(scrollAxis: .vertical)) {
                    Text("ITEM")
                }
                .defaultScrollAnchor(.center, for: .alignment)
            )

            XCTAssertEqual(roles.count, 3)
            XCTAssertEqual(defaultNode.initialScrollAnchor, RetainedScrollAnchor(x: 0.5, y: 1))
            XCTAssertEqual(defaultNode.scrollSizeChangeAnchor, RetainedScrollAnchor(x: 0.5, y: 1))
            XCTAssertEqual(roleNode.initialScrollAnchor, RetainedScrollAnchor(x: 0.5, y: 0))
            XCTAssertNil(roleNode.scrollSizeChangeAnchor)
            XCTAssertEqual(roleNode.scrollAxis, .vertical)

            guard case .stack(let defaultLayout) = defaultNode.layoutMode,
                case .stack(let roleLayout) = roleNode.layoutMode,
                case .stack(let horizontalLayout) = horizontalNode.layoutMode,
                case .stack(let listLayout) = listNode.layoutMode,
                case .stack(let sectionLayout) = scrollingSectionNode.layoutMode
            else {
                return XCTFail("Expected retained stack layouts for default scroll anchor assertions")
            }

            XCTAssertEqual(defaultLayout, .vertical(alignment: .center, mainAlignment: .end))
            XCTAssertEqual(roleLayout, .vertical(alignment: .center, mainAlignment: .center))
            XCTAssertEqual(horizontalLayout, .horizontal(alignment: .trailing, mainAlignment: .end))
            XCTAssertEqual(
                listLayout,
                .vertical(
                    padding: EdgeInsets(
                        top: 0, leading: MacOSControlMetrics.List.contentInset, bottom: 0,
                        trailing: MacOSControlMetrics.List.contentInset), alignment: .stretch, mainAlignment: .end)
            )
            XCTAssertEqual(sectionLayout.mainAlignment, .center)
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
            XCTAssertEqual(
                stackLayout,
                .vertical(
                    spacing: 0,
                    padding: EdgeInsets(
                        top: 0, leading: MacOSControlMetrics.List.contentInset, bottom: 0,
                        trailing: MacOSControlMetrics.List.contentInset), alignment: .stretch)
            )
            XCTAssertEqual(listRows(of: node).count, 2)
            XCTAssertEqual(listRows(of: node)[0].text, "ONE")
            XCTAssertEqual(listRows(of: node)[1].text, "TWO")
        }
    }

    func testListRowBackgroundMapsToRetainedRowBackgrounds() async {
        await MainActor.run {
            let rowColor = Color(red: 0.27, green: 0.27, blue: 0.27, alpha: 0.90)
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

            XCTAssertEqual(listRows(of: listNode)[0].backgroundColor, rowColor)
            XCTAssertEqual(listRows(of: listNode)[0].children[0].text, "ONE")
            XCTAssertEqual(
                listRows(of: listNode)[1].backgroundGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(listRows(of: listNode)[1].children[0].text, "TWO")
            XCTAssertEqual(listRows(of: listNode)[2].text, "THREE")
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

            guard case .stack(let explicitLayout) = listRows(of: listNode)[0].layoutMode else {
                return XCTFail("Expected listRowInsets to wrap the row in a retained stack panel")
            }
            guard case .stack(let horizontalLayout) = listRows(of: listNode)[1].layoutMode else {
                return XCTFail("Expected listRowInsets edge overload to wrap the row in a retained stack panel")
            }

            XCTAssertEqual(explicitLayout, .vertical(padding: explicitInsets, alignment: .stretch))
            XCTAssertEqual(listRows(of: listNode)[0].children[0].text, "ONE")
            XCTAssertEqual(
                horizontalLayout,
                .vertical(padding: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10), alignment: .stretch)
            )
            XCTAssertEqual(listRows(of: listNode)[1].children[0].text, "TWO")
            XCTAssertEqual(listRows(of: listNode)[2].text, "THREE")
        }
    }

    func testListSectionMarginsMapToRetainedSectionPadding() async {
        await MainActor.run {
            let listNode = makeNode(
                List {
                    Section("HORIZONTAL") {
                        Text("ONE")
                    }
                    .listSectionMargins(.horizontal, 10)

                    Section("DEFAULT") {
                        Text("TWO")
                    }
                    .listSectionMargins(.vertical, nil)

                    Section("PLAIN") {
                        Text("THREE")
                    }
                }
            )

            guard case .stack(let horizontalLayout) = listRows(of: listNode)[0].layoutMode else {
                return XCTFail("Expected horizontal listSectionMargins to wrap the section in a retained stack panel")
            }
            guard case .stack(let defaultLayout) = listRows(of: listNode)[1].layoutMode else {
                return XCTFail("Expected default listSectionMargins to wrap the section in a retained stack panel")
            }

            XCTAssertEqual(
                horizontalLayout,
                .vertical(padding: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10), alignment: .stretch)
            )
            XCTAssertTrue(allTexts(in: listRows(of: listNode)[0]).contains("HORIZONTAL"))
            XCTAssertEqual(
                defaultLayout,
                .vertical(padding: EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0), alignment: .stretch)
            )
            XCTAssertTrue(allTexts(in: listRows(of: listNode)[1]).contains("DEFAULT"))
            XCTAssertTrue(allTexts(in: listRows(of: listNode)[2]).contains("PLAIN"))
        }
    }

    func testListRowSeparatorModifierStoresMetadataAndVisibleDividers() async {
        await MainActor.run {
            let listNode = makeNode(
                List {
                    Text("HIDDEN")
                        .listRowSeparator(.hidden)
                    Text("TOP")
                        .listRowSeparator(.visible, edges: .top)
                    Text("BOTTOM")
                        .listRowSeparator(.visible, edges: .bottom)
                    Text("BOTH")
                        .listRowSeparator(.visible)
                }
            )

            XCTAssertEqual(
                listRows(of: listNode)[0].listRowSeparator,
                RetainedListRowSeparator(visibility: .hidden, edges: .all)
            )
            XCTAssertEqual(listRows(of: listNode)[0].text, "HIDDEN")

            XCTAssertEqual(
                listRows(of: listNode)[1].listRowSeparator,
                RetainedListRowSeparator(visibility: .visible, edges: .top)
            )
            XCTAssertEqual(listRows(of: listNode)[1].children.count, 2)
            XCTAssertEqual(listRows(of: listNode)[1].children[0].preferredSize, Size(width: 0, height: 1))
            XCTAssertEqual(listRows(of: listNode)[1].children[1].text, "TOP")

            XCTAssertEqual(
                listRows(of: listNode)[2].listRowSeparator,
                RetainedListRowSeparator(visibility: .visible, edges: .bottom)
            )
            XCTAssertEqual(listRows(of: listNode)[2].children.count, 2)
            XCTAssertEqual(listRows(of: listNode)[2].children[0].text, "BOTTOM")
            XCTAssertEqual(listRows(of: listNode)[2].children[1].preferredSize, Size(width: 0, height: 1))

            XCTAssertEqual(
                listRows(of: listNode)[3].listRowSeparator,
                RetainedListRowSeparator(visibility: .visible, edges: .all)
            )
            XCTAssertEqual(listRows(of: listNode)[3].children.count, 3)
            XCTAssertEqual(listRows(of: listNode)[3].children[1].text, "BOTH")
        }
    }

    func testListRowSeparatorTintStoresMetadataAndColorsVisibleDividers() async {
        await MainActor.run {
            let topTint = Color(red: 1, green: 0.2, blue: 0.1, alpha: 1)
            let bottomTint = Color(red: 0.1, green: 0.7, blue: 1, alpha: 1)
            let defaultSeparatorTint = ControlPalette.darkStandard.separator
            let listNode = makeNode(
                List {
                    Text("BEFORE")
                        .listRowSeparatorTint(topTint, edges: .top)
                        .listRowSeparator(.visible)
                    Text("AFTER")
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(bottomTint, edges: .bottom)
                    Text("RESET")
                        .listRowSeparatorTint(nil, edges: .top)
                    Text("CLEAR")
                        .listRowSeparatorTint(topTint, edges: .top)
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(nil, edges: .top)
                }
            )

            XCTAssertEqual(
                listRows(of: listNode)[0].listRowSeparatorTint,
                RetainedListSeparatorTint(color: topTint, edges: .top)
            )
            XCTAssertEqual(listRows(of: listNode)[0].children[0].backgroundColor, topTint)
            XCTAssertNotEqual(listRows(of: listNode)[0].children[2].backgroundColor, topTint)

            XCTAssertEqual(
                listRows(of: listNode)[1].listRowSeparatorTint,
                RetainedListSeparatorTint(color: bottomTint, edges: .bottom)
            )
            XCTAssertNotEqual(listRows(of: listNode)[1].children[0].backgroundColor, bottomTint)
            XCTAssertEqual(listRows(of: listNode)[1].children[2].backgroundColor, bottomTint)

            XCTAssertEqual(
                listRows(of: listNode)[2].listRowSeparatorTint,
                RetainedListSeparatorTint(color: nil, edges: .top)
            )
            XCTAssertEqual(listRows(of: listNode)[2].text, "RESET")

            XCTAssertEqual(
                listRows(of: listNode)[3].listRowSeparatorTint,
                RetainedListSeparatorTint(color: nil, edges: .top)
            )
            XCTAssertEqual(listRows(of: listNode)[3].children[0].backgroundColor, defaultSeparatorTint)
        }
    }

    func testListSectionSeparatorsStoreMetadataAndVisibleDividers() async {
        await MainActor.run {
            let listNode = makeNode(
                List {
                    Section("HIDDEN") {
                        Text("ONE")
                    }
                    .listSectionSeparator(.hidden)
                    Section("TOP") {
                        Text("TWO")
                    }
                    .listSectionSeparator(.visible, edges: .top)
                    Section("BOTTOM") {
                        Text("THREE")
                    }
                    .listSectionSeparator(.visible, edges: .bottom)
                    Section("BOTH") {
                        Text("FOUR")
                    }
                    .listSectionSeparator(.visible)
                }
            )

            XCTAssertEqual(
                listRows(of: listNode)[0].listSectionSeparator,
                RetainedListSectionSeparator(visibility: .hidden, edges: .all)
            )
            XCTAssertTrue(allTexts(in: listRows(of: listNode)[0]).contains("HIDDEN"))

            XCTAssertEqual(
                listRows(of: listNode)[1].listSectionSeparator,
                RetainedListSectionSeparator(visibility: .visible, edges: .top)
            )
            XCTAssertEqual(listRows(of: listNode)[1].children.count, 2)
            XCTAssertEqual(listRows(of: listNode)[1].children[0].preferredSize, Size(width: 0, height: 1))
            XCTAssertTrue(allTexts(in: listRows(of: listNode)[1].children[1]).contains("TOP"))

            XCTAssertEqual(
                listRows(of: listNode)[2].listSectionSeparator,
                RetainedListSectionSeparator(visibility: .visible, edges: .bottom)
            )
            XCTAssertEqual(listRows(of: listNode)[2].children.count, 2)
            XCTAssertTrue(allTexts(in: listRows(of: listNode)[2].children[0]).contains("BOTTOM"))
            XCTAssertEqual(listRows(of: listNode)[2].children[1].preferredSize, Size(width: 0, height: 1))

            XCTAssertEqual(
                listRows(of: listNode)[3].listSectionSeparator,
                RetainedListSectionSeparator(visibility: .visible, edges: .all)
            )
            XCTAssertEqual(listRows(of: listNode)[3].children.count, 3)
            XCTAssertTrue(allTexts(in: listRows(of: listNode)[3].children[1]).contains("BOTH"))
        }
    }

    func testListSectionSeparatorTintStoresMetadataAndColorsVisibleDividers() async {
        await MainActor.run {
            let topTint = Color(red: 1, green: 0.2, blue: 0.1, alpha: 1)
            let bottomTint = Color(red: 0.1, green: 0.7, blue: 1, alpha: 1)
            let defaultSeparatorTint = ControlPalette.darkStandard.separator
            let listNode = makeNode(
                List {
                    Section("BEFORE") {
                        Text("ONE")
                    }
                    .listSectionSeparatorTint(topTint, edges: .top)
                    .listSectionSeparator(.visible)
                    Section("AFTER") {
                        Text("TWO")
                    }
                    .listSectionSeparator(.visible)
                    .listSectionSeparatorTint(bottomTint, edges: .bottom)
                    Section("RESET") {
                        Text("THREE")
                    }
                    .listSectionSeparatorTint(nil, edges: .top)
                    Section("CLEAR") {
                        Text("FOUR")
                    }
                    .listSectionSeparatorTint(topTint, edges: .top)
                    .listSectionSeparator(.visible)
                    .listSectionSeparatorTint(nil, edges: .top)
                }
            )

            XCTAssertEqual(
                listRows(of: listNode)[0].listSectionSeparatorTint,
                RetainedListSeparatorTint(color: topTint, edges: .top)
            )
            XCTAssertEqual(listRows(of: listNode)[0].children[0].backgroundColor, topTint)
            XCTAssertNotEqual(listRows(of: listNode)[0].children[2].backgroundColor, topTint)

            XCTAssertEqual(
                listRows(of: listNode)[1].listSectionSeparatorTint,
                RetainedListSeparatorTint(color: bottomTint, edges: .bottom)
            )
            XCTAssertNotEqual(listRows(of: listNode)[1].children[0].backgroundColor, bottomTint)
            XCTAssertEqual(listRows(of: listNode)[1].children[2].backgroundColor, bottomTint)

            XCTAssertEqual(
                listRows(of: listNode)[2].listSectionSeparatorTint,
                RetainedListSeparatorTint(color: nil, edges: .top)
            )
            XCTAssertTrue(allTexts(in: listRows(of: listNode)[2]).contains("RESET"))

            XCTAssertEqual(
                listRows(of: listNode)[3].listSectionSeparatorTint,
                RetainedListSeparatorTint(color: nil, edges: .top)
            )
            XCTAssertEqual(listRows(of: listNode)[3].children[0].backgroundColor, defaultSeparatorTint)
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

            XCTAssertEqual(
                spacedLayout,
                .vertical(
                    spacing: 12,
                    padding: EdgeInsets(
                        top: 0, leading: MacOSControlMetrics.List.contentInset, bottom: 0,
                        trailing: MacOSControlMetrics.List.contentInset), alignment: .stretch)
            )
            XCTAssertEqual(
                resetLayout,
                .vertical(
                    spacing: 0,
                    padding: EdgeInsets(
                        top: 0, leading: MacOSControlMetrics.List.contentInset, bottom: 0,
                        trailing: MacOSControlMetrics.List.contentInset), alignment: .stretch)
            )
        }
    }

    func testListSectionSpacingMapsToRetainedListStackSpacing() async {
        await MainActor.run {
            let customListNode = makeNode(
                List {
                    Section("COLORS") {
                        Text("BLUE")
                    }
                    Section("SHAPES") {
                        Text("SQUARE")
                    }
                }
                .listSectionSpacing(14)
            )
            let compactListNode = makeNode(
                List {
                    Section("COLORS") {
                        Text("BLUE")
                    }
                    Section("SHAPES") {
                        Text("SQUARE")
                    }
                }
                .listStyle(GroupedListStyle())
                .listSectionSpacing(.compact)
            )
            let defaultListNode = makeNode(
                List {
                    Section("COLORS") {
                        Text("BLUE")
                    }
                    Section("SHAPES") {
                        Text("SQUARE")
                    }
                }
                .listStyle(GroupedListStyle())
                .listSectionSpacing(.default)
            )
            let rowSpacingWinsNode = makeNode(
                List {
                    Section("COLORS") {
                        Text("BLUE")
                    }
                    Section("SHAPES") {
                        Text("SQUARE")
                    }
                }
                .listSectionSpacing(30)
                .listRowSpacing(9)
            )

            guard case .stack(let customLayout) = customListNode.layoutMode,
                case .stack(let compactLayout) = compactListNode.layoutMode,
                case .stack(let defaultLayout) = defaultListNode.layoutMode,
                case .stack(let rowSpacingWinsLayout) = rowSpacingWinsNode.layoutMode
            else {
                return XCTFail("Expected List to keep retained stack layout")
            }

            XCTAssertEqual(
                customLayout,
                .vertical(
                    spacing: 14,
                    padding: EdgeInsets(
                        top: 0, leading: MacOSControlMetrics.List.contentInset, bottom: 0,
                        trailing: MacOSControlMetrics.List.contentInset), alignment: .stretch)
            )
            XCTAssertEqual(
                compactLayout,
                .vertical(
                    spacing: 4,
                    padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
                    alignment: .stretch
                )
            )
            XCTAssertEqual(
                defaultLayout,
                .vertical(
                    spacing: 8,
                    padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
                    alignment: .stretch
                )
            )
            XCTAssertEqual(
                rowSpacingWinsLayout,
                .vertical(
                    spacing: 9,
                    padding: EdgeInsets(
                        top: 0, leading: MacOSControlMetrics.List.contentInset, bottom: 0,
                        trailing: MacOSControlMetrics.List.contentInset), alignment: .stretch)
            )
            XCTAssertEqual(ListSectionSpacing.custom(12), .custom(12))
            XCTAssertNotEqual(ListSectionSpacing.compact, .default)
        }
    }

    func testListStyleModifierMapsToRetainedListChrome() async {
        await MainActor.run {
            let plainNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listStyle(PlainListStyle())
            )
            let borderedNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listStyle(BorderedListStyle())
            )
            let carouselNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listStyle(CarouselListStyle())
            )
            let insetGroupedNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listStyle(InsetGroupedListStyle())
            )
            let alternatingInsetNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                    Text("THREE")
                }
                .listStyle(InsetListStyle(alternatesRowBackgrounds: true))
            )
            let nonAlternatingInsetNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listStyle(InsetListStyle(alternatesRowBackgrounds: false))
            )
            let overriddenSpacingNode = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
                .listStyle(GroupedListStyle())
                .listRowSpacing(18)
            )

            guard case .stack(let plainLayout) = plainNode.layoutMode else {
                return XCTFail("Expected plain List to keep retained stack layout")
            }
            guard case .stack(let borderedLayout) = borderedNode.layoutMode else {
                return XCTFail("Expected bordered List to keep retained stack layout")
            }
            guard case .stack(let carouselLayout) = carouselNode.layoutMode else {
                return XCTFail("Expected carousel List to keep retained stack layout")
            }
            guard case .stack(let insetGroupedLayout) = insetGroupedNode.layoutMode else {
                return XCTFail("Expected insetGrouped List to keep retained stack layout")
            }
            guard case .stack(let overriddenSpacingLayout) = overriddenSpacingNode.layoutMode else {
                return XCTFail("Expected grouped List to keep retained stack layout")
            }

            // The plain body is `textBackgroundColor` and it fills the view,
            // not the rows: an NSTableView shorter than its scroll view still
            // paints down to the clip view's bottom edge.
            XCTAssertEqual(plainNode.backgroundColor, ControlPalette.darkStandard.controlBackground)
            XCTAssertEqual(plainNode.borderWidth, 0)
            XCTAssertEqual(plainNode.cornerRadius, 0)
            XCTAssertEqual(
                plainLayout,
                .vertical(
                    spacing: 0,
                    padding: EdgeInsets(
                        top: 0, leading: MacOSControlMetrics.List.contentInset, bottom: 0,
                        trailing: MacOSControlMetrics.List.contentInset), alignment: .stretch)
            )

            XCTAssertNil(borderedNode.backgroundColor)
            XCTAssertEqual(borderedNode.borderWidth, 1)
            XCTAssertEqual(borderedNode.cornerRadius, 6)
            XCTAssertEqual(borderedLayout, .vertical(spacing: 0, padding: .zero, alignment: .stretch))

            // List bodies are appearance roles, not literals.
            XCTAssertEqual(carouselNode.backgroundColor, ControlPalette.darkStandard.controlBackground)
            XCTAssertEqual(carouselNode.borderWidth, 1)
            XCTAssertEqual(carouselNode.cornerRadius, MacOSControlMetrics.Radius.lg)
            XCTAssertEqual(
                carouselLayout,
                .vertical(
                    spacing: 6,
                    padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
                    alignment: .stretch
                )
            )

            XCTAssertEqual(insetGroupedNode.backgroundColor, ControlPalette.darkStandard.controlBackground)
            XCTAssertEqual(insetGroupedNode.borderWidth, 1)
            XCTAssertEqual(insetGroupedNode.cornerRadius, MacOSControlMetrics.Radius.lg)
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
            XCTAssertNil(alternatingInsetNode.children[0].backgroundColor)
            XCTAssertEqual(
                alternatingInsetNode.children[1].backgroundColor,
                ControlPalette.darkStandard.quinaryFill
            )
            XCTAssertEqual(alternatingInsetNode.children[1].cornerRadius, 8)
            XCTAssertNil(alternatingInsetNode.children[2].backgroundColor)
            // An un-striped inset table rules between its rows instead, so
            // the second child is the hairline, not the second row.
            XCTAssertNil(nonAlternatingInsetNode.children[0].backgroundColor)
            XCTAssertTrue(nonAlternatingInsetNode.children[1].isSeparatorRule)
            XCTAssertNil(nonAlternatingInsetNode.children[2].backgroundColor)
        }
    }

    func testListStyleEnvironmentCanBeRead() async {
        await MainActor.run {
            struct ListStyleReader: View {
                @Environment(\.listStyle) var listStyle

                var body: some View {
                    Text(
                        listStyle == .sidebar
                            ? "SIDEBAR"
                            : listStyle == .bordered
                                ? "BORDERED"
                                : listStyle == .elliptical
                                    ? "ELLIPTICAL"
                                    : listStyle == .inset
                                        ? "INSET"
                                        : listStyle == .automatic
                                            ? "AUTOMATIC"
                                            : "OTHER"
                    )
                }
            }

            let defaultNode = makeNode(ListStyleReader())
            let sidebarNode = makeNode(ListStyleReader().listStyle(SidebarListStyle()))
            let borderedNode = makeNode(ListStyleReader().listStyle(BorderedListStyle()))
            let ellipticalNode = makeNode(ListStyleReader().listStyle(EllipticalListStyle()))
            let insetNode = makeNode(ListStyleReader().listStyle(InsetListStyle(alternatesRowBackgrounds: true)))

            XCTAssertEqual(defaultNode.text, "AUTOMATIC")
            XCTAssertEqual(sidebarNode.text, "SIDEBAR")
            XCTAssertEqual(borderedNode.text, "BORDERED")
            XCTAssertEqual(ellipticalNode.text, "ELLIPTICAL")
            XCTAssertEqual(insetNode.text, "INSET")
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

            XCTAssertEqual(listRows(of: node)[0].layoutConstraints?.minHeight, 44)
            XCTAssertEqual(listRows(of: node)[0].layoutConstraints?.maxHeight, .infinity)
            XCTAssertEqual(listRows(of: node)[1].layoutConstraints?.minHeight, 60)
            XCTAssertEqual(listRows(of: node)[1].layoutConstraints?.maxHeight, .infinity)
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
                Color(red: 0.977, green: 0.977, blue: 0.977, alpha: 0.22)
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

            XCTAssertEqual(listRows(of: node).count, 2)
            XCTAssertEqual(listRows(of: node)[0].text, "ONE")
            XCTAssertEqual(listRows(of: node)[1].text, "TWO")
            XCTAssertEqual(listRows(of: node)[0].nodeTag, "ONE#0")
            XCTAssertEqual(listRows(of: node)[1].nodeTag, "TWO#0")
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

            XCTAssertEqual(listRows(of: node).count, 2)
            XCTAssertEqual(listRows(of: node)[0].text, "SEVEN")
            XCTAssertEqual(listRows(of: node)[1].text, "NINE")
            XCTAssertEqual(listRows(of: node)[0].nodeTag, "7#0")
            XCTAssertEqual(listRows(of: node)[1].nodeTag, "9#0")
        }
    }

    func testListBindingCollectionInitializerFeedsRetainedControls() async {
        await MainActor.run {
            struct Row: Identifiable {
                let id: Int
                var title: String
                var isEnabled: Bool
            }

            var rows = [
                Row(id: 7, title: "SEVEN", isEnabled: false),
                Row(id: 9, title: "NINE", isEnabled: true),
            ]
            let rowsBinding = Binding(
                get: { rows },
                set: { rows = $0 }
            )

            let node = makeNode(
                List(rowsBinding) { row in
                    Toggle(row.wrappedValue.title, isOn: row.isEnabled)
                    TextField("TITLE", text: row.title)
                }
            )
            let controls = focusableNodes(in: node)

            controls[0].onActivate?()
            controls[3].onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertTrue(rows[0].isEnabled)
            XCTAssertEqual(rows[1].title, "NINEz")
            XCTAssertEqual(listRows(of: node)[0].nodeTag, "7#0")
            XCTAssertEqual(listRows(of: node)[2].nodeTag, "9#0")
        }
    }

    func testListBindingCollectionInitializerSupportsExplicitIDKeyPath() async {
        await MainActor.run {
            struct Row {
                let key: String
                var title: String
            }

            var rows = [
                Row(key: "alpha", title: "ALPHA"),
                Row(key: "beta", title: "BETA"),
            ]
            let rowsBinding = Binding(
                get: { rows },
                set: { rows = $0 }
            )

            let node = makeNode(
                List(rowsBinding, id: \.key) { row in
                    TextField("TITLE", text: row.title)
                }
            )

            firstFocusable(in: node)?.onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertEqual(rows[0].title, "ALPHAz")
            XCTAssertEqual(listRows(of: node)[0].nodeTag, "alpha#0")
            XCTAssertEqual(listRows(of: node)[1].nodeTag, "beta#0")
        }
    }

    func testListSelectionContentInitializerSelectsTaggedRows() async {
        await MainActor.run {
            var selected: String? = "one"
            var didInvalidate = false
            let binding = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeNode(
                List(selection: binding) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(listRows(of: node).count, 2)
            XCTAssertEqual(listRows(of: node)[0].children[0].text, "ONE")
            XCTAssertEqual(listRows(of: node)[1].children[0].text, "TWO")
            XCTAssertNotNil(listRows(of: node)[0].backgroundColor)
            XCTAssertNil(listRows(of: node)[1].backgroundColor)

            listRows(of: node)[1].onActivate?()

            XCTAssertEqual(selected, "two")
            XCTAssertTrue(didInvalidate)
        }
    }

    func testListDataSelectionInitializerTagsRowsByElementID() async {
        await MainActor.run {
            struct Row: Identifiable {
                let id: Int
                let title: String
            }

            var selected: Int? = 7
            let binding = Binding<Int?>(
                get: { selected },
                set: { selected = $0 }
            )
            let rows = [
                Row(id: 7, title: "SEVEN"),
                Row(id: 9, title: "NINE"),
            ]
            let node = makeNode(
                List(rows, selection: binding) { row in
                    Text(row.title)
                }
            )

            XCTAssertEqual(listRows(of: node)[0].nodeTag, "7#0")
            XCTAssertEqual(listRows(of: node)[1].nodeTag, "9#0")
            XCTAssertEqual(listRows(of: node)[0].children[0].text, "SEVEN")
            XCTAssertEqual(listRows(of: node)[1].children[0].text, "NINE")
            XCTAssertNotNil(listRows(of: node)[0].backgroundColor)
            XCTAssertNil(listRows(of: node)[1].backgroundColor)

            listRows(of: node)[1].onActivate?()

            XCTAssertEqual(selected, 9)
        }
    }

    func testListMultipleSelectionTogglesTaggedRows() async {
        await MainActor.run {
            var selected: Set<String> = ["one"]
            let binding = Binding<Set<String>>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeNode(
                List(selection: binding) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                }
            )

            XCTAssertNotNil(listRows(of: node)[0].backgroundColor)
            XCTAssertNil(listRows(of: node)[1].backgroundColor)

            listRows(of: node)[1].onActivate?()
            XCTAssertEqual(selected, ["one", "two"])

            listRows(of: node)[0].onActivate?()
            XCTAssertEqual(selected, ["two"])
        }
    }

    func testListSelectionRowsRenderEditModeSelectionChrome() async {
        await MainActor.run {
            var selected: String? = "one"
            var editMode = EditMode.inactive
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )
            let editing = Binding(
                get: { editMode },
                set: { editMode = $0 }
            )

            let inactiveNode = makeNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                }
                .environment(\.editMode, editing)
            )

            XCTAssertEqual(inactiveNode.children[0].children[0].text, "ONE")

            editMode = .active
            let activeNode = makeNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                }
                .environment(\.editMode, editing)
            )

            let selectedContent = activeNode.children[0].children[0]
            let unselectedContent = activeNode.children[1].children[0]
            let selectedIndicator = selectedContent.children[0]
            let unselectedIndicator = unselectedContent.children[0]

            XCTAssertEqual(selectedIndicator.nodeTag, "list-edit-selection-selected")
            XCTAssertEqual(selectedIndicator.preferredSize, Size(width: 18, height: 18))
            XCTAssertNotNil(selectedIndicator.backgroundColor)
            XCTAssertEqual(selectedIndicator.children.first?.nodeTag, "list-edit-selection-dot")
            XCTAssertEqual(selectedContent.children[1].text, "ONE")
            XCTAssertEqual(unselectedIndicator.nodeTag, "list-edit-selection-unselected")
            XCTAssertNil(unselectedIndicator.backgroundColor)
            XCTAssertTrue(unselectedIndicator.children.isEmpty)
            XCTAssertEqual(unselectedContent.children[1].text, "TWO")

            activeNode.children[1].onActivate?()
            XCTAssertEqual(selected, "two")
        }
    }

    func testSelectedListRowsExposeIncreasedBackgroundProminenceToContent() async {
        await MainActor.run {
            struct RowProminenceReader: View {
                @Environment(\.backgroundProminence) var backgroundProminence

                var body: some View {
                    Text(backgroundProminence == .increased ? "INCREASED" : "STANDARD")
                }
            }

            var selected: String? = "one"
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeNode(
                List(selection: selection) {
                    RowProminenceReader().tag("one")
                    RowProminenceReader().tag("two")
                }
            )

            // `.increased` background prominence means "this content sits on
            // a *filled* emphasised surface", and a selected row is an accent
            // wash now, not a fill — so a selected row no longer claims it.
            // Inverting content to white on a wash is white-on-#E4E2F8 in the
            // light appearance, which is unreadable.
            XCTAssertEqual(listRows(of: node)[0].children[0].text, "STANDARD")
            XCTAssertEqual(listRows(of: node)[1].children[0].text, "STANDARD")
        }
    }

    func testSelectionDisabledPreventsRetainedListRowSelection() async {
        await MainActor.run {
            var selected: String? = "one"
            var didInvalidate = false
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                        .selectionDisabled()
                    Text("THREE").tag("three")
                        .selectionDisabled(false)
                }
                .selectionDisabled(),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(listRows(of: node)[0].text, "ONE")
            XCTAssertTrue(listRows(of: node)[0].selectionDisabled)
            XCTAssertNil(listRows(of: node)[0].onActivate)
            XCTAssertEqual(listRows(of: node)[1].text, "TWO")
            XCTAssertTrue(listRows(of: node)[1].selectionDisabled)
            XCTAssertNil(listRows(of: node)[1].onActivate)

            XCTAssertFalse(listRows(of: node)[2].selectionDisabled)
            XCTAssertEqual(listRows(of: node)[2].children[0].text, "THREE")
            listRows(of: node)[2].onActivate?()

            XCTAssertEqual(selected, "three")
            XCTAssertTrue(didInvalidate)
        }
    }

    func testDeleteAndMoveDisabledStoreRetainedListRowMetadata() async {
        await MainActor.run {
            let node = makeNode(
                List {
                    Text("ONE")
                    Text("TWO")
                        .deleteDisabled(false)
                    Text("THREE")
                        .moveDisabled(false)
                    Text("FOUR")
                        .deleteDisabled(true)
                        .moveDisabled(true)
                }
                .deleteDisabled(true)
                .moveDisabled(true)
            )

            XCTAssertEqual(listRows(of: node)[0].text, "ONE")
            XCTAssertTrue(listRows(of: node)[0].deleteDisabled)
            XCTAssertNil(listRows(of: node)[0].deleteDisabledOverride)
            XCTAssertTrue(listRows(of: node)[0].moveDisabled)
            XCTAssertNil(listRows(of: node)[0].moveDisabledOverride)

            XCTAssertFalse(listRows(of: node)[1].deleteDisabled)
            XCTAssertEqual(listRows(of: node)[1].deleteDisabledOverride, false)
            XCTAssertTrue(listRows(of: node)[1].moveDisabled)
            XCTAssertNil(listRows(of: node)[1].moveDisabledOverride)

            XCTAssertTrue(listRows(of: node)[2].deleteDisabled)
            XCTAssertNil(listRows(of: node)[2].deleteDisabledOverride)
            XCTAssertFalse(listRows(of: node)[2].moveDisabled)
            XCTAssertEqual(listRows(of: node)[2].moveDisabledOverride, false)

            XCTAssertTrue(listRows(of: node)[3].deleteDisabled)
            XCTAssertEqual(listRows(of: node)[3].deleteDisabledOverride, true)
            XCTAssertTrue(listRows(of: node)[3].moveDisabled)
            XCTAssertEqual(listRows(of: node)[3].moveDisabledOverride, true)
        }
    }

    func testListRequiredRangeSelectionWritesIntegerIndex() async {
        await MainActor.run {
            var selected = 1
            let binding = Binding<Int>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeNode(
                List(0..<3, selection: binding) { index in
                    Text("ROW \(index)")
                }
            )

            XCTAssertEqual(listRows(of: node)[1].nodeTag, "1#0")
            XCTAssertNotNil(listRows(of: node)[1].backgroundColor)

            listRows(of: node)[2].onActivate?()

            XCTAssertEqual(selected, 2)
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

            // A Form is a centring box around a ~640pt content column:
            // macOS settings live in a column with margins, not edge to
            // edge across the window.
            guard case .stack(let centringLayout) = node.layoutMode else {
                return XCTFail("Expected Form to use retained stack layout")
            }
            XCTAssertEqual(centringLayout.axis, .vertical)
            XCTAssertEqual(centringLayout.alignment, .center)
            XCTAssertEqual(node.children.count, 1)

            let column = node.children[0]
            XCTAssertEqual(column.layoutConstraints?.maxWidth, MacOSControlMetrics.Form.contentMaxWidth)
            guard case .stack(let columnLayout) = column.layoutMode else {
                return XCTFail("Expected the Form's content column to use retained stack layout")
            }
            XCTAssertEqual(
                columnLayout,
                .vertical(
                    spacing: MacOSControlMetrics.Form.sectionSpacing,
                    padding: EdgeInsets(
                        top: 16,
                        leading: MacOSControlMetrics.Form.contentHorizontalMargin,
                        bottom: MacOSControlMetrics.Form.contentHorizontalMargin,
                        trailing: MacOSControlMetrics.Form.contentHorizontalMargin
                    ),
                    alignment: .stretch
                )
            )
            XCTAssertEqual(column.children.count, 2)
            // The label-less row is indented to the value column beside the
            // toggle's label, so it is a wrapper now, not the Text itself.
            XCTAssertEqual(firstText(in: column.children[0]), "NAME")
            XCTAssertEqual(firstText(in: column.children[1]), "ENABLED")
        }
    }

    func testFormStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct FormStyleReaderView: View {
                @Environment(\.formStyle) var formStyle

                var body: some View {
                    Text(formStyle == .columns ? "COLUMNS" : formStyle == .grouped ? "GROUPED" : "AUTOMATIC")
                }
            }

            let columnsReaderNode = makeNode(FormStyleReaderView().formStyle(ColumnsFormStyle()))
            let groupedReaderNode = makeNode(FormStyleReaderView().formStyle(.grouped))
            let inheritedNode = makeNode(
                VStack {
                    Form {
                        Text("NAME")
                        Text("VALUE")
                    }
                }
                .formStyle(GroupedFormStyle())
            )
            let columnsNode = makeNode(
                Form {
                    Text("LABEL")
                    Text("VALUE")
                }
                .formStyle(.columns)
            )

            // A Form's chrome lives on the content column inside its
            // centring box, so each style's box is one level down.
            let inheritedColumn = inheritedNode.children[0].children[0]
            let columnsColumn = columnsNode.children[0]

            XCTAssertEqual(columnsReaderNode.text, "COLUMNS")
            XCTAssertEqual(groupedReaderNode.text, "GROUPED")
            XCTAssertEqual(inheritedColumn.children.count, 2)
            XCTAssertEqual(inheritedColumn.children[0].text, "NAME")
            XCTAssertEqual(inheritedColumn.backgroundColor, ControlPalette.darkStandard.raisedSurface)
            // A grouped card is a panel material, and its ring starts at the
            // appearance's top highlight rather than at the separator tone.
            XCTAssertNotNil(inheritedColumn.backgroundGradient)
            XCTAssertEqual(inheritedColumn.borderColor, ControlPalette.darkStandard.raisedSurfaceHighlight)
            XCTAssertEqual(inheritedColumn.borderWidth, 1)
            XCTAssertEqual(inheritedColumn.cornerRadius, MacOSControlMetrics.GroupBox.cornerRadius)
            guard case .stack(let groupedStackLayout) = inheritedColumn.layoutMode else {
                return XCTFail("Expected grouped Form to use retained stack layout")
            }
            XCTAssertEqual(
                groupedStackLayout,
                .vertical(
                    spacing: MacOSControlMetrics.Form.sectionSpacing,
                    padding: EdgeInsets(
                        top: 16,
                        leading: MacOSControlMetrics.Form.contentHorizontalMargin,
                        bottom: MacOSControlMetrics.Form.contentHorizontalMargin,
                        trailing: MacOSControlMetrics.Form.contentHorizontalMargin
                    ),
                    alignment: .stretch
                )
            )
            guard case .stack(let columnsStackLayout) = columnsColumn.layoutMode else {
                return XCTFail("Expected columns Form to use retained stack layout")
            }
            XCTAssertEqual(
                columnsStackLayout,
                .vertical(
                    spacing: 8,
                    padding: EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18),
                    alignment: .stretch
                )
            )
            XCTAssertEqual(columnsColumn.borderWidth, 1)
            XCTAssertEqual(columnsColumn.cornerRadius, 8)
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

            XCTAssertEqual(
                stackLayout,
                .vertical(
                    spacing: 16, padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                    alignment: .leading))
            XCTAssertEqual(node.borderWidth, 1)
            XCTAssertEqual(node.cornerRadius, 28)
            XCTAssertEqual(node.children.count, 3)
            XCTAssertEqual(node.children[0].text, "HEADER")
            XCTAssertEqual(node.children[1].text, "ROW")
            XCTAssertEqual(node.children[2].text, "FOOTER")
            // A **list** group header keeps its eyebrow: `nil` resolves to
            // the appearance's secondary label at 11pt. Only a *grouped-form*
            // section header is promoted to a 15/600 heading — a settings
            // section names a group you are about to read, a list group names
            // rows you are already reading past.
            XCTAssertEqual(node.children[0].textStyle.color, ControlPalette.darkStandard.secondaryLabel)
            XCTAssertEqual(node.children[2].textStyle.color, .secondary)
        }
    }

    func testSectionSupportsFooterOnlyBuilderSyntax() async {
        await MainActor.run {
            let node = makeNode(
                Section {
                    Text("ROW")
                } footer: {
                    Text("FOOTER")
                }
            )

            guard case .stack(let stackLayout) = node.layoutMode else {
                return XCTFail("Expected Section to use retained stack layout")
            }

            XCTAssertEqual(
                stackLayout,
                .vertical(
                    spacing: 16, padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                    alignment: .leading))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "ROW")
            XCTAssertEqual(node.children[1].text, "FOOTER")
            XCTAssertEqual(node.children[1].textStyle.color, .secondary)
            XCTAssertEqual(node.children[1].textStyle.scale, Font.footnote.resolvedScale)
        }
    }

    func testSectionSupportsDeprecatedDirectHeaderFooterSyntax() async {
        await MainActor.run {
            let headerNode = makeNode(
                Section(header: Text("HEADER")) {
                    Text("ROW")
                }
            )
            let footerNode = makeNode(
                Section(footer: Text("FOOTER")) {
                    Text("ROW")
                }
            )
            let headerFooterNode = makeNode(
                Section(header: Text("HEADER"), footer: Text("FOOTER")) {
                    Text("ROW")
                }
            )

            XCTAssertEqual(allTexts(in: headerNode), ["HEADER", "ROW"])
            XCTAssertEqual(headerNode.children[0].textStyle.color, ControlPalette.darkStandard.secondaryLabel)
            XCTAssertEqual(allTexts(in: footerNode), ["ROW", "FOOTER"])
            XCTAssertEqual(footerNode.children[1].textStyle.color, .secondary)
            XCTAssertEqual(allTexts(in: headerFooterNode), ["HEADER", "ROW", "FOOTER"])
        }
    }

    func testSectionExpandedBindingControlsRetainedContentAndHeaderActivation() async {
        await MainActor.run {
            var isExpanded = false
            var didInvalidate = false
            let binding = Binding(
                get: { isExpanded },
                set: { isExpanded = $0 }
            )

            let collapsedNode = makeNode(
                Section("ADVANCED", isExpanded: binding) {
                    Text("ROW")
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(allTexts(in: collapsedNode).contains("ADVANCED"))
            XCTAssertTrue(allTexts(in: collapsedNode).contains(">"))
            XCTAssertFalse(allTexts(in: collapsedNode).contains("ROW"))

            collapsedNode.children[0].onActivate?()

            XCTAssertTrue(isExpanded)
            XCTAssertTrue(didInvalidate)

            let expandedNode = makeNode(
                Section(isExpanded: binding) {
                    Text("DETAIL")
                } header: {
                    Text("OPTIONS")
                }
            )

            XCTAssertTrue(allTexts(in: expandedNode).contains("OPTIONS"))
            XCTAssertTrue(allTexts(in: expandedNode).contains("V"))
            XCTAssertTrue(allTexts(in: expandedNode).contains("DETAIL"))

            expandedNode.children[0].onActivate?()
            XCTAssertFalse(isExpanded)

            let localizedCollapsedNode = makeNode(
                Section(LocalizedStringKey("LOCAL"), isExpanded: binding) {
                    Text("HIDDEN")
                }
            )

            XCTAssertTrue(allTexts(in: localizedCollapsedNode).contains("LOCAL"))
            XCTAssertFalse(allTexts(in: localizedCollapsedNode).contains("HIDDEN"))
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

    func testBackgroundProminenceEnvironmentCanBeReadAndOverridden() async {
        await MainActor.run {
            struct BackgroundProminenceReader: View {
                @Environment(\.backgroundProminence) var backgroundProminence

                var body: some View {
                    Text(backgroundProminence == .increased ? "INCREASED" : "STANDARD")
                }
            }

            let defaultNode = makeNode(BackgroundProminenceReader())
            let overrideNode = makeNode(
                BackgroundProminenceReader()
                    .environment(\.backgroundProminence, .increased)
            )
            let transformedNode = makeNode(
                BackgroundProminenceReader()
                    .transformEnvironment(\.backgroundProminence) { prominence in
                        prominence = .increased
                    }
            )

            XCTAssertEqual(defaultNode.text, "STANDARD")
            XCTAssertEqual(overrideNode.text, "INCREASED")
            XCTAssertEqual(transformedNode.text, "INCREASED")
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
            // An NSBox is the same grouped container a Form section is: the
            // pinned 10pt corner, the appearance's raised surface, and the
            // panel material on it. The 12pt radius and the translucent dark
            // charcoal it used to carry were literals no appearance resolved.
            XCTAssertEqual(node.cornerRadius, MacOSControlMetrics.GroupBox.cornerRadius)
            XCTAssertEqual(node.backgroundColor, ControlPalette.darkStandard.raisedSurface)
            XCTAssertNotNil(node.backgroundGradient)
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

    func testGroupBoxStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct GroupBoxStyleReaderView: View {
                @Environment(\.groupBoxStyle) var groupBoxStyle

                var body: some View {
                    Text(groupBoxStyle == .automatic ? "AUTOMATIC" : "OTHER")
                }
            }

            let readerNode = makeNode(GroupBoxStyleReaderView().groupBoxStyle(DefaultGroupBoxStyle()))
            let inheritedNode = makeNode(
                VStack {
                    GroupBox("SETTINGS") {
                        Text("BODY")
                    }
                }
                .groupBoxStyle(.automatic)
            )

            XCTAssertEqual(readerNode.text, "AUTOMATIC")
            XCTAssertEqual(inheritedNode.children[0].children.count, 2)
            XCTAssertEqual(inheritedNode.children[0].children[0].text, "SETTINGS")
            XCTAssertEqual(
                inheritedNode.children[0].cornerRadius, MacOSControlMetrics.GroupBox.cornerRadius)
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

    func testDisclosureGroupStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct DisclosureGroupStyleReaderView: View {
                @Environment(\.disclosureGroupStyle) var disclosureGroupStyle

                var body: some View {
                    Text(disclosureGroupStyle == .automatic ? "AUTOMATIC" : "OTHER")
                }
            }

            let readerNode = makeNode(
                DisclosureGroupStyleReaderView()
                    .disclosureGroupStyle(AutomaticDisclosureGroupStyle())
            )
            let inheritedNode = makeNode(
                VStack {
                    DisclosureGroup("DETAILS", isExpanded: .constant(true)) {
                        Text("NESTED")
                    }
                }
                .disclosureGroupStyle(.automatic)
            )

            XCTAssertEqual(readerNode.text, "AUTOMATIC")
            XCTAssertEqual(inheritedNode.children[0].children.count, 2)
            XCTAssertTrue(allTexts(in: inheritedNode.children[0].children[0]).contains("DETAILS"))
            XCTAssertEqual(firstText(in: inheritedNode.children[0].children[1]), "NESTED")
        }
    }

    func testMenuRevealsOverlayContentDismissesAfterActionAndProvidesEnvironment() async {
        await MainActor.run {
            struct MenuPresentationProbe: View {
                @Environment(\.isPresented) var isPresented

                var body: some View {
                    Text(isPresented ? "PRESENTED" : "HIDDEN")
                }
            }

            var didInvalidate = false
            var activationCount = 0
            let menu = Menu("ACTIONS") {
                Button("EXPORT") {
                    activationCount += 1
                }
                MenuPresentationProbe()
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
            XCTAssertFalse(allTexts(in: collapsedNode).contains("EXPORT"))

            collapsedNode.children[0].onActivate?()

            XCTAssertTrue(didInvalidate)

            let expandedNode = makeNode(menu)

            guard case .absolute = expandedNode.layoutMode else {
                return XCTFail("Expected Menu to use retained absolute overlay layout")
            }
            XCTAssertEqual(expandedNode.children.count, 2)
            XCTAssertTrue(allTexts(in: expandedNode.children[1]).contains("EXPORT"))
            XCTAssertTrue(allTexts(in: expandedNode.children[1]).contains("PRESENTED"))
            XCTAssertTrue(allTexts(in: expandedNode.children[1]).contains("ARCHIVE"))

            let exportButton = focusableNodes(in: expandedNode.children[1]).first {
                allTexts(in: $0).contains("EXPORT")
            }
            exportButton?.onActivate?()

            XCTAssertEqual(activationCount, 1)

            let dismissedNode = makeNode(menu)
            XCTAssertTrue(allTexts(in: dismissedNode).contains("ACTIONS"))
            XCTAssertFalse(allTexts(in: dismissedNode).contains("EXPORT"))
        }
    }

    func testMenuPrimaryActionRunsWithoutOpeningPopup() async {
        await MainActor.run {
            var primaryCount = 0
            var itemCount = 0
            let titleMenu = Menu(
                "ACTIONS",
                content: {
                    Button("EXPORT") {
                        itemCount += 1
                    }
                },
                primaryAction: {
                    primaryCount += 1
                })

            let titleNode = makeNode(titleMenu)

            XCTAssertTrue(allTexts(in: titleNode).contains("ACTIONS"))
            XCTAssertFalse(allTexts(in: titleNode).contains("EXPORT"))

            titleNode.children[0].onActivate?()

            XCTAssertEqual(primaryCount, 1)
            XCTAssertEqual(itemCount, 0)

            let afterPrimaryNode = makeNode(titleMenu)
            XCTAssertTrue(allTexts(in: afterPrimaryNode).contains("ACTIONS"))
            XCTAssertFalse(allTexts(in: afterPrimaryNode).contains("EXPORT"))

            var imagePrimaryCount = 0
            let imageMenu = Menu(
                "MORE", systemImage: "ellipsis.circle",
                content: {
                    Button("DELETE") {}
                },
                primaryAction: {
                    imagePrimaryCount += 1
                })

            makeNode(imageMenu).children[0].onActivate?()

            XCTAssertEqual(imagePrimaryCount, 1)
            XCTAssertFalse(allTexts(in: makeNode(imageMenu)).contains("DELETE"))
        }
    }

    func testMenuNamedImageInitializersComposeBitmapLabelAndPrimaryAction() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-menu-image-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            var primaryCount = 0
            let stringNode = makeNode(
                Menu("PHOTO", image: url.path) {
                    Button("OPEN") {}
                })
            let protocolTitle: Substring = "TOOLS"[...]
            let protocolMenu = Menu(
                protocolTitle, image: url.path,
                content: {
                    Button("PICK") {}
                },
                primaryAction: {
                    primaryCount += 1
                })
            let protocolNode = makeNode(protocolMenu)
            let keyNode = makeNode(
                Menu(LocalizedStringKey("ALBUM"), image: url.path) {
                    Button("EDIT") {}
                })

            XCTAssertTrue(allTexts(in: stringNode).contains("PHOTO"))
            XCTAssertEqual(firstBitmapNode(in: stringNode)?.bitmapSurface?.width, 2)
            XCTAssertEqual(firstBitmapNode(in: stringNode)?.bitmapSurface?.height, 1)
            XCTAssertTrue(allTexts(in: protocolNode).contains("TOOLS"))
            XCTAssertTrue(allTexts(in: keyNode).contains("ALBUM"))

            protocolNode.children[0].onActivate?()

            XCTAssertEqual(primaryCount, 1)
            XCTAssertFalse(allTexts(in: makeNode(protocolMenu)).contains("PICK"))
        }
    }

    func testMenuIndicatorVisibilityControlsRetainedDisclosureGlyph() async {
        await MainActor.run {
            let automaticNode = makeNode(
                Menu("ACTIONS") {
                    Button("EXPORT") {}
                }
            )
            let hiddenNode = makeNode(
                Menu("ACTIONS") {
                    Button("EXPORT") {}
                }
                .menuIndicator(.hidden)
            )
            let visibleNode = makeNode(
                Menu("ACTIONS") {
                    Button("EXPORT") {}
                }
                .menuIndicator(.visible)
            )

            XCTAssertTrue(allTexts(in: automaticNode).contains(">"))
            XCTAssertFalse(allTexts(in: hiddenNode).contains(">"))
            XCTAssertTrue(allTexts(in: visibleNode).contains(">"))
        }
    }

    func testMenuStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct MenuStyleReaderView: View {
                @Environment(\.menuStyle) var menuStyle

                var body: some View {
                    Text(menuStyle == .button ? "BUTTON" : menuStyle == .automatic ? "AUTOMATIC" : "OTHER")
                }
            }

            let buttonReaderNode = makeNode(MenuStyleReaderView().menuStyle(ButtonMenuStyle()))
            let automaticReaderNode = makeNode(MenuStyleReaderView().menuStyle(DefaultMenuStyle()))
            let inheritedNode = makeNode(
                VStack {
                    Menu("ACTIONS") {
                        Button("DELETE") {}
                    }
                }
                .menuStyle(BorderlessButtonMenuStyle(showsMenuIndicator: false))
            )

            XCTAssertEqual(buttonReaderNode.text, "BUTTON")
            XCTAssertEqual(automaticReaderNode.text, "AUTOMATIC")
            XCTAssertEqual(allTexts(in: inheritedNode.children[0]), ["ACTIONS"])
            XCTAssertEqual(inheritedNode.children[0].children[0].backgroundColor, .clear)
            XCTAssertEqual(inheritedNode.children[0].children[0].borderColor, .clear)
        }
    }

    func testContextMenuRightClickRevealsRetainedOverlayAndDismissesFromEnvironment() async {
        await MainActor.run {
            struct DismissContextMenuButton: View {
                @Environment(\.dismiss) var dismiss
                let onClose: @MainActor () -> Void

                var body: some View {
                    Button("CLOSE") {
                        onClose()
                        dismiss()
                    }
                }
            }

            var didInvalidate = false
            var copyCount = 0
            var closeCount = 0
            let view = Text("ROOT")
                .frame(width: 220, height: 120)
                .contextMenu {
                    Button("COPY") {
                        copyCount += 1
                    }
                    DismissContextMenuButton {
                        closeCount += 1
                    }
                }

            let (runtime, closedNode) = makeRuntimeNode(
                view,
                size: Size(width: 320, height: 240),
                onInvalidate: {
                    didInvalidate = true
                }
            )
            XCTAssertTrue(allTexts(in: closedNode).contains("ROOT"))

            runtime.contextClick(at: Point(x: 24, y: 32))

            XCTAssertTrue(didInvalidate)

            let openedNode = makeNode(view, size: Size(width: 320, height: 240))
            guard case .absolute = openedNode.layoutMode else {
                return XCTFail("Expected contextMenu to use retained absolute overlay layout while open")
            }
            XCTAssertTrue(allTexts(in: openedNode).contains("ROOT"))
            XCTAssertTrue(allTexts(in: openedNode).contains("COPY"))
            XCTAssertTrue(allTexts(in: openedNode).contains("CLOSE"))

            let copyButton = focusableNodes(in: openedNode).first { allTexts(in: $0).contains("COPY") }
            copyButton?.onActivate?()

            XCTAssertEqual(copyCount, 1)

            let dismissedNode = makeNode(view, size: Size(width: 320, height: 240))
            XCTAssertTrue(allTexts(in: dismissedNode).contains("ROOT"))
            XCTAssertFalse(allTexts(in: dismissedNode).contains("COPY"))

            runtime.contextClick(at: Point(x: 24, y: 32))
            let reopenedNode = makeNode(view, size: Size(width: 320, height: 240))
            let closeButton = focusableNodes(in: reopenedNode).first { allTexts(in: $0).contains("CLOSE") }
            closeButton?.onActivate?()

            XCTAssertEqual(closeCount, 1)
            let explicitlyDismissedNode = makeNode(view, size: Size(width: 320, height: 240))
            XCTAssertFalse(allTexts(in: explicitlyDismissedNode).contains("COPY"))
        }
    }

    func testContextMenuPreviewOverloadComposesPreviewContent() async {
        await MainActor.run {
            let view = Text("ROOT")
                .frame(width: 220, height: 120)
                .contextMenu {
                    Button("OPEN") {}
                } preview: {
                    Text("PREVIEW")
                }

            let (runtime, _) = makeRuntimeNode(view, size: Size(width: 320, height: 240))
            runtime.contextClick(at: Point(x: 24, y: 32))

            let openedNode = makeNode(view, size: Size(width: 320, height: 240))
            XCTAssertTrue(allTexts(in: openedNode).contains("ROOT"))
            XCTAssertTrue(allTexts(in: openedNode).contains("OPEN"))
            XCTAssertTrue(allTexts(in: openedNode).contains("PREVIEW"))
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
            let systemImageNode = makeNode(
                ControlGroup("TOOLS", systemImage: "slider.horizontal.3") {
                    Button("RESET") {}
                }
            )
            let localizedImageNode = makeNode(
                ControlGroup(LocalizedStringKey("ACTIONS"), systemImage: "gearshape") {
                    Button("APPLY") {}
                }
            )

            XCTAssertEqual(allTexts(in: node), ["TOOLS", "EXPORT", "ARCHIVE"])
            XCTAssertEqual(node.children[0].layoutPriority, 1)
            XCTAssertEqual(node.cornerRadius, 10)

            node.children[1].onActivate?()

            XCTAssertEqual(activationCount, 1)
            XCTAssertEqual(allTexts(in: titleNode), ["ACTIONS", "SYNC"])
            XCTAssertTrue(allTexts(in: systemImageNode).contains("TOOLS"))
            XCTAssertTrue(allTexts(in: systemImageNode).contains("RESET"))
            XCTAssertTrue(allTexts(in: localizedImageNode).contains("ACTIONS"))
            XCTAssertTrue(allTexts(in: localizedImageNode).contains("APPLY"))
        }
    }

    func testControlGroupNamedImageInitializersComposeBitmapLabel() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-controlgroup-image-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            var activationCount = 0
            let stringNode = makeNode(
                ControlGroup("PHOTO", image: url.path) {
                    Button("EXPORT") {
                        activationCount += 1
                    }
                }
            )
            let protocolTitle: Substring = "TOOLS"[...]
            let protocolNode = makeNode(
                ControlGroup(protocolTitle, image: url.path) {
                    Button("RESET") {}
                }
            )
            let keyNode = makeNode(
                ControlGroup(LocalizedStringKey("ALBUM"), image: url.path) {
                    Button("APPLY") {}
                }
            )

            XCTAssertTrue(allTexts(in: stringNode).contains("PHOTO"))
            XCTAssertEqual(firstBitmapNode(in: stringNode)?.bitmapSurface?.width, 2)
            XCTAssertEqual(firstBitmapNode(in: stringNode)?.bitmapSurface?.height, 1)
            XCTAssertTrue(allTexts(in: protocolNode).contains("TOOLS"))
            XCTAssertTrue(allTexts(in: keyNode).contains("ALBUM"))

            stringNode.children[1].onActivate?()

            XCTAssertEqual(activationCount, 1)
        }
    }

    func testControlGroupStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct ControlGroupStyleReaderView: View {
                @Environment(\.controlGroupStyle) var controlGroupStyle

                var body: some View {
                    Text(
                        controlGroupStyle == .palette
                            ? "PALETTE"
                            : controlGroupStyle == .compactMenu
                                ? "COMPACT"
                                : controlGroupStyle == .navigation
                                    ? "NAVIGATION"
                                    : controlGroupStyle == .automatic
                                        ? "AUTOMATIC"
                                        : "OTHER"
                    )
                }
            }

            let readerNode = makeNode(ControlGroupStyleReaderView().controlGroupStyle(PaletteControlGroupStyle()))
            let compactReaderNode = makeNode(
                ControlGroupStyleReaderView().controlGroupStyle(CompactMenuControlGroupStyle())
            )
            let navigationReaderNode = makeNode(
                ControlGroupStyleReaderView().controlGroupStyle(NavigationControlGroupStyle())
            )
            let automaticReaderNode = makeNode(
                ControlGroupStyleReaderView().controlGroupStyle(AutomaticControlGroupStyle())
            )
            let inheritedNode = makeNode(
                VStack {
                    ControlGroup {
                        Button("EXPORT") {}
                        Button("ARCHIVE") {}
                    }
                }
                .controlGroupStyle(MenuControlGroupStyle())
            )
            let tint = Color(red: 0.25, green: 0.65, blue: 0.95, alpha: 1)
            let paletteGroupNode = makeNode(
                ControlGroup {
                    Button("BOLD") {}
                    Button("ITALIC") {}
                }
                .controlGroupStyle(.palette)
                .tint(tint)
            )
            let compactGroupNode = makeNode(
                ControlGroup {
                    Button("COPY") {}
                    Button("PASTE") {}
                }
                .controlGroupStyle(CompactMenuControlGroupStyle())
            )
            let navigationGroupNode = makeNode(
                ControlGroup {
                    Button("BACK") {}
                    Button("NEXT") {}
                }
                .controlGroupStyle(NavigationControlGroupStyle())
                .tint(tint)
            )

            XCTAssertEqual(readerNode.text, "PALETTE")
            XCTAssertEqual(compactReaderNode.text, "COMPACT")
            XCTAssertEqual(navigationReaderNode.text, "NAVIGATION")
            XCTAssertEqual(automaticReaderNode.text, "AUTOMATIC")
            XCTAssertEqual(allTexts(in: inheritedNode.children[0]), ["EXPORT", "ARCHIVE"])
            XCTAssertEqual(inheritedNode.children[0].cornerRadius, 12)
            XCTAssertEqual(
                inheritedNode.children[0].backgroundColor, Color(red: 0.097, green: 0.097, blue: 0.097, alpha: 0.64))
            guard case .stack(let menuLayout) = inheritedNode.children[0].layoutMode else {
                XCTFail("Expected menu control group stack layout")
                return
            }
            XCTAssertEqual(
                menuLayout,
                .horizontal(
                    spacing: 5, padding: EdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 7), alignment: .center))

            XCTAssertEqual(compactGroupNode.cornerRadius, 7)
            XCTAssertEqual(compactGroupNode.backgroundColor, Color(red: 0.117, green: 0.117, blue: 0.117, alpha: 0.58))
            guard case .stack(let compactLayout) = compactGroupNode.layoutMode else {
                XCTFail("Expected compact menu control group stack layout")
                return
            }
            XCTAssertEqual(
                compactLayout,
                .horizontal(
                    spacing: 2, padding: EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4), alignment: .center))

            XCTAssertEqual(navigationGroupNode.cornerRadius, 9)
            XCTAssertEqual(navigationGroupNode.borderColor, tint.opacity(0.24))
            guard case .stack(let navigationLayout) = navigationGroupNode.layoutMode else {
                XCTFail("Expected navigation control group stack layout")
                return
            }
            XCTAssertEqual(
                navigationLayout,
                .horizontal(
                    spacing: 3, padding: EdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5), alignment: .center))

            XCTAssertEqual(paletteGroupNode.cornerRadius, 8)
            XCTAssertEqual(paletteGroupNode.borderColor, tint.opacity(0.34))
            XCTAssertEqual(paletteGroupNode.children[0].backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
            XCTAssertEqual(paletteGroupNode.children[1].backgroundColor, ButtonSurfaceStyle.defaultPalette.idle)
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
            // The title band is window chrome: the body starts directly
            // under its hairline, with no gap.
            XCTAssertEqual(stackLayout, .vertical(spacing: 0, alignment: .stretch))
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

    func testNavigationSubtitleRendersInRetainedChrome() async {
        await MainActor.run {
            let detailSubtitle: Substring = "DETAIL SUBTITLE"[...]
            let stack = NavigationStack {
                NavigationLink(
                    "OPEN",
                    destination: Text("DETAIL")
                        .navigationTitle("DETAIL TITLE")
                        .navigationSubtitle(detailSubtitle)
                )
                .navigationTitle("ROOT TITLE")
                .navigationSubtitle(LocalizedStringKey("ROOT SUBTITLE"))
            }

            let rootNode = makeNode(stack)
            let rootHeaderTexts = allTexts(in: rootNode.children[0])

            XCTAssertTrue(rootHeaderTexts.contains("ROOT TITLE"))
            XCTAssertTrue(rootHeaderTexts.contains("ROOT SUBTITLE"))
            guard case .stack(let rootTitleLayout) = rootNode.children[0].children[0].children[0].layoutMode else {
                return XCTFail("Expected titled navigation header to stack title and subtitle")
            }
            XCTAssertEqual(rootTitleLayout, .vertical(spacing: 2, padding: .zero, alignment: .leading))

            let textSubtitleNode = makeNode(
                NavigationStack {
                    Text("TEXT")
                        .navigationTitle("TEXT TITLE")
                        .navigationSubtitle(Text("TEXT SUBTITLE"))
                }
            )
            XCTAssertTrue(allTexts(in: textSubtitleNode.children[0]).contains("TEXT SUBTITLE"))

            rootNode.children[1].onActivate?()

            let detailNode = makeNode(stack)
            let detailHeaderTexts = allTexts(in: detailNode.children[0])

            XCTAssertTrue(detailHeaderTexts.contains("DETAIL TITLE"))
            XCTAssertTrue(detailHeaderTexts.contains("DETAIL SUBTITLE"))
            XCTAssertEqual(detailNode.children[1].text, "DETAIL")
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

    func testNavigationViewStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct NavigationViewStyleReader: View {
                @Environment(\.navigationViewStyle) var navigationViewStyle

                var body: some View {
                    Text(
                        navigationViewStyle == .stack
                            ? "STACK"
                            : navigationViewStyle == .doubleColumn
                                ? "DOUBLE"
                                : navigationViewStyle == .columns
                                    ? "COLUMNS"
                                    : navigationViewStyle == .automatic
                                        ? "AUTOMATIC"
                                        : "OTHER"
                    )
                }
            }

            let stackReaderNode = makeNode(
                NavigationViewStyleReader()
                    .navigationViewStyle(StackNavigationViewStyle())
            )
            let doubleReaderNode = makeNode(
                NavigationViewStyleReader()
                    .navigationViewStyle(DoubleColumnNavigationViewStyle())
            )
            let columnsReaderNode = makeNode(
                NavigationViewStyleReader()
                    .navigationViewStyle(ColumnsNavigationViewStyle())
            )
            let automaticReaderNode = makeNode(
                NavigationViewStyleReader()
                    .navigationViewStyle(DefaultNavigationViewStyle())
            )
            let navigationNode = makeNode(
                NavigationView {
                    Text("ROOT")
                        .navigationTitle("ROOT TITLE")
                }
                .navigationViewStyle(.stack)
            )
            let doubleColumnNavigationNode = makeNode(
                NavigationView {
                    Text("DOUBLE ROOT")
                        .navigationTitle("DOUBLE TITLE")
                }
                .navigationViewStyle(.doubleColumn)
            )
            let columnsNavigationNode = makeNode(
                NavigationView {
                    Text("COLUMNS ROOT")
                        .navigationTitle("COLUMNS TITLE")
                }
                .navigationViewStyle(ColumnsNavigationViewStyle())
            )

            XCTAssertEqual(stackReaderNode.text, "STACK")
            XCTAssertEqual(doubleReaderNode.text, "DOUBLE")
            XCTAssertEqual(columnsReaderNode.text, "COLUMNS")
            XCTAssertEqual(automaticReaderNode.text, "AUTOMATIC")
            XCTAssertTrue(allTexts(in: navigationNode).contains("ROOT"))
            XCTAssertTrue(allTexts(in: navigationNode).contains("ROOT TITLE"))
            // children[0] is the toolbar band; the header row is its first
            // child and the bottom hairline its second.
            XCTAssertEqual(
                navigationNode.children[0].children[0].backgroundColor,
                ControlPalette.darkStandard.windowBackground
            )
            XCTAssertEqual(navigationNode.children[0].children[0].cornerRadius, 0)
            XCTAssertEqual(
                doubleColumnNavigationNode.backgroundColor, ControlPalette.darkStandard.controlBackground)
            XCTAssertEqual(doubleColumnNavigationNode.borderWidth, 1)
            XCTAssertEqual(doubleColumnNavigationNode.cornerRadius, 12)
            XCTAssertEqual(doubleColumnNavigationNode.children[0].cornerRadius, 8)
            XCTAssertEqual(
                columnsNavigationNode.backgroundColor, ControlPalette.darkStandard.controlBackground)
            XCTAssertEqual(columnsNavigationNode.cornerRadius, 14)
            XCTAssertEqual(columnsNavigationNode.children[0].cornerRadius, 12)
        }
    }

    func testNavigationSplitViewStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct NavigationSplitViewStyleReader: View {
                @Environment(\.navigationSplitViewStyle) var navigationSplitViewStyle

                var body: some View {
                    Text(
                        navigationSplitViewStyle == .balanced
                            ? "BALANCED"
                            : navigationSplitViewStyle == .prominentDetail
                                ? "PROMINENT"
                                : navigationSplitViewStyle == .automatic
                                    ? "AUTOMATIC"
                                    : "OTHER"
                    )
                }
            }

            let balancedReaderNode = makeNode(
                NavigationSplitViewStyleReader()
                    .navigationSplitViewStyle(BalancedNavigationSplitViewStyle())
            )
            let prominentReaderNode = makeNode(
                NavigationSplitViewStyleReader()
                    .navigationSplitViewStyle(ProminentDetailNavigationSplitViewStyle())
            )
            let automaticReaderNode = makeNode(
                NavigationSplitViewStyleReader()
                    .navigationSplitViewStyle(AutomaticNavigationSplitViewStyle())
            )
            let splitNode = makeNode(
                NavigationSplitView {
                    Text("SIDEBAR")
                } detail: {
                    Text("DETAIL")
                }
                .navigationSplitViewStyle(.balanced)
            )
            let prominentNode = makeNode(
                NavigationSplitView {
                    Text("SIDEBAR")
                } content: {
                    Text("CONTENT")
                } detail: {
                    Text("DETAIL")
                }
                .navigationSplitViewStyle(ProminentDetailNavigationSplitViewStyle())
            )

            XCTAssertEqual(balancedReaderNode.text, "BALANCED")
            XCTAssertEqual(prominentReaderNode.text, "PROMINENT")
            XCTAssertEqual(automaticReaderNode.text, "AUTOMATIC")
            XCTAssertEqual(splitNode.children.count, 2)
            XCTAssertEqual(splitNode.children[0].text, "SIDEBAR")
            XCTAssertEqual(splitNode.children[1].text, "DETAIL")
            XCTAssertEqual(splitNode.children[0].layoutPriority, 1)
            XCTAssertEqual(splitNode.children[1].layoutPriority, 1)
            XCTAssertEqual(splitNode.children[0].borderWidth, 1)
            XCTAssertEqual(splitNode.children[1].borderWidth, 0)
            XCTAssertEqual(
                splitNode.children[0].backgroundColor, Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 0.24))

            XCTAssertEqual(prominentNode.children.count, 3)
            XCTAssertEqual(prominentNode.children[0].layoutPriority, 0.75)
            XCTAssertEqual(prominentNode.children[1].layoutPriority, 0.75)
            XCTAssertEqual(prominentNode.children[2].layoutPriority, 2)
            XCTAssertEqual(prominentNode.children[0].borderWidth, 1)
            XCTAssertEqual(prominentNode.children[1].borderWidth, 1)
            XCTAssertEqual(prominentNode.children[2].borderWidth, 0)
            XCTAssertEqual(
                prominentNode.children[2].backgroundColor, Color(red: 0.136, green: 0.136, blue: 0.136, alpha: 0.30))
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
            // children[0] is the inset tab band; the bar itself is its
            // only child (macOS insets the control from the window edge).
            defaultNode.children[0].children[0].children[1].onActivate?()
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

            node.children[0].children[0].children[1].onActivate?()

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

            let firstTabButton = node.children[0].children[0].children[0]
            let firstTabContent = firstTabButton.children[0]
            XCTAssertEqual(
                firstTabContent.children[1].backgroundColor, Color(red: 0.92, green: 0.18, blue: 0.24, alpha: 0.96))
            XCTAssertEqual(node.children[0].children[0].children[1].children[0].text, "SECOND TAB")
        }
    }

    func testTabViewStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct TabViewStyleReader: View {
                @Environment(\.tabViewStyle) var tabViewStyle

                var body: some View {
                    Text(
                        tabViewStyle == .page(indexDisplayMode: .never)
                            ? "PAGE"
                            : tabViewStyle == .verticalPage(transitionStyle: .blur)
                                ? "VERTICAL"
                                : tabViewStyle == .sidebarAdaptable
                                    ? "SIDEBAR"
                                    : tabViewStyle == .tabBarOnly
                                        ? "TABBAR"
                                        : tabViewStyle == .grouped
                                            ? "GROUPED"
                                            : tabViewStyle == .carousel
                                                ? "CAROUSEL"
                                                : tabViewStyle == .automatic
                                                    ? "AUTOMATIC"
                                                    : "OTHER"
                    )
                }
            }

            let pageReaderNode = makeNode(
                TabViewStyleReader()
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            )
            let verticalReaderNode = makeNode(
                TabViewStyleReader()
                    .tabViewStyle(VerticalPageTabViewStyle(transitionStyle: .blur))
            )
            let sidebarReaderNode = makeNode(
                TabViewStyleReader()
                    .tabViewStyle(SidebarAdaptableTabViewStyle())
            )
            let tabBarReaderNode = makeNode(
                TabViewStyleReader()
                    .tabViewStyle(TabBarOnlyTabViewStyle())
            )
            let groupedReaderNode = makeNode(
                TabViewStyleReader()
                    .tabViewStyle(GroupedTabViewStyle())
            )
            let carouselReaderNode = makeNode(
                TabViewStyleReader()
                    .tabViewStyle(CarouselTabViewStyle())
            )
            let automaticReaderNode = makeNode(
                TabViewStyleReader()
                    .tabViewStyle(DefaultTabViewStyle())
            )
            let styledTabNode = makeNode(
                TabView {
                    Text("FIRST")
                        .tabItem { Text("FIRST TAB") }
                    Text("SECOND")
                        .tabItem { Text("SECOND TAB") }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            )
            let groupedTabNode = makeNode(
                TabView {
                    Text("FIRST")
                        .tabItem { Text("FIRST TAB") }
                    Text("SECOND")
                        .tabItem { Text("SECOND TAB") }
                }
                .tabViewStyle(GroupedTabViewStyle())
            )
            let sidebarTabNode = makeNode(
                TabView {
                    Text("FIRST")
                        .tabItem { Text("FIRST TAB") }
                    Text("SECOND")
                        .tabItem { Text("SECOND TAB") }
                }
                .tabViewStyle(SidebarAdaptableTabViewStyle())
            )
            let carouselTabNode = makeNode(
                TabView {
                    Text("FIRST")
                        .tabItem { Text("FIRST TAB") }
                    Text("SECOND")
                        .tabItem { Text("SECOND TAB") }
                }
                .tabViewStyle(CarouselTabViewStyle())
            )

            XCTAssertEqual(pageReaderNode.text, "PAGE")
            XCTAssertEqual(verticalReaderNode.text, "VERTICAL")
            XCTAssertEqual(sidebarReaderNode.text, "SIDEBAR")
            XCTAssertEqual(tabBarReaderNode.text, "TABBAR")
            XCTAssertEqual(groupedReaderNode.text, "GROUPED")
            XCTAssertEqual(carouselReaderNode.text, "CAROUSEL")
            XCTAssertEqual(automaticReaderNode.text, "AUTOMATIC")
            XCTAssertTrue(allTexts(in: styledTabNode.children[0]).contains("FIRST TAB"))
            XCTAssertEqual(styledTabNode.children[1].text, "FIRST")

            // Every style draws a *selector bar*: a square band with no track
            // of its own, and items with no pill. What varies is the item's
            // own box — a page bar is denser than a window's primary
            // navigation and a carousel's is looser — never the presence of a
            // groove. The band used to be a rounded, bordered capsule at
            // `Radius.xl` in four of the six styles, which is what made the
            // top of every screen a stack of slabs.
            let bar = MacOSControlMetrics.SelectorBar.self
            for (name, node) in [
                ("page", styledTabNode), ("grouped", groupedTabNode),
                ("sidebar", sidebarTabNode), ("carousel", carouselTabNode),
            ] {
                let band = node.children[0]
                let row = band.children[0]
                XCTAssertEqual(row.cornerRadius, 0, "\(name) band is square")
                XCTAssertNil(row.backgroundColor, "\(name) band carries no track fill")
                XCTAssertEqual(row.borderWidth, 0, "\(name) band carries no ring")
                for (index, tab) in row.children.enumerated() {
                    XCTAssertEqual(tab.cornerRadius, bar.itemCornerRadius, "\(name) tab \(index)")
                    XCTAssertEqual(tab.borderWidth, 0, "\(name) tab \(index) carries no border")
                }
                // The band itself is the page tone, closed by one hairline.
                XCTAssertEqual(band.children.count, 2, "\(name) band is a row plus its hairline")
                XCTAssertEqual(
                    band.children[1].preferredSize?.height, bar.hairlineThickness, "\(name) hairline")
            }

            guard case .stack(let pageLayout) = styledTabNode.children[0].children[0].layoutMode else {
                XCTFail("Expected page tab bar stack layout")
                return
            }
            XCTAssertEqual(pageLayout.spacing, bar.itemSpacing)
            XCTAssertEqual(pageLayout.alignment, .center)

            guard case .stack(let carouselLayout) = carouselTabNode.children[0].children[0].layoutMode else {
                XCTFail("Expected carousel tab bar stack layout")
                return
            }
            XCTAssertEqual(carouselLayout.spacing, MacOSControlMetrics.Spacing.s2)
        }
    }

    func testIndexViewStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct IndexViewStyleReader: View {
                @Environment(\.indexViewStyle) var indexViewStyle

                var body: some View {
                    Text(
                        indexViewStyle == .page(backgroundDisplayMode: .never)
                            ? "NEVER"
                            : indexViewStyle == .page(backgroundDisplayMode: .always)
                                ? "ALWAYS"
                                : indexViewStyle == .page(backgroundDisplayMode: .interactive)
                                    ? "INTERACTIVE"
                                    : indexViewStyle == .page
                                        ? "PAGE"
                                        : "OTHER"
                    )
                }
            }

            let defaultNode = makeNode(IndexViewStyleReader())
            let neverNode = makeNode(
                IndexViewStyleReader()
                    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))
            )
            let alwaysNode = makeNode(
                IndexViewStyleReader()
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
            )
            let interactiveNode = makeNode(
                IndexViewStyleReader()
                    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .interactive))
            )
            let styledTabNode = makeNode(
                TabView {
                    Text("FIRST")
                        .tabItem { Text("FIRST TAB") }
                    Text("SECOND")
                        .tabItem { Text("SECOND TAB") }
                }
                .tabViewStyle(.page)
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))
            )
            let alwaysBackgroundTabNode = makeNode(
                TabView {
                    Text("FIRST")
                        .tabItem { Text("FIRST TAB") }
                    Text("SECOND")
                        .tabItem { Text("SECOND TAB") }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            )
            let hiddenIndexTabNode = makeNode(
                TabView {
                    Text("FIRST")
                        .tabItem { Text("FIRST TAB") }
                    Text("SECOND")
                        .tabItem { Text("SECOND TAB") }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            )

            XCTAssertEqual(defaultNode.text, "PAGE")
            XCTAssertEqual(neverNode.text, "NEVER")
            XCTAssertEqual(alwaysNode.text, "ALWAYS")
            XCTAssertEqual(interactiveNode.text, "INTERACTIVE")
            XCTAssertTrue(allTexts(in: styledTabNode.children[0]).contains("FIRST TAB"))
            XCTAssertEqual(styledTabNode.children[1].text, "FIRST")
            XCTAssertEqual(styledTabNode.children.count, 3)
            XCTAssertEqual(styledTabNode.children[2].nodeTag, "tab-page-index")
            XCTAssertNil(styledTabNode.children[2].backgroundColor)
            XCTAssertEqual(styledTabNode.children[2].borderWidth, 0)
            XCTAssertEqual(styledTabNode.children[2].children[0].nodeTag, "tab-page-index-selected")
            XCTAssertEqual(styledTabNode.children[2].children[1].nodeTag, "tab-page-index-unselected")
            XCTAssertEqual(styledTabNode.children[2].children[0].preferredSize, Size(width: 18, height: 6))
            XCTAssertEqual(styledTabNode.children[2].children[1].preferredSize, Size(width: 6, height: 6))
            XCTAssertEqual(
                alwaysBackgroundTabNode.children[2].backgroundColor,
                Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 0.72))
            XCTAssertEqual(alwaysBackgroundTabNode.children[2].cornerRadius, 10)
            XCTAssertEqual(hiddenIndexTabNode.children.count, 2)
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

            detailNode.children[0].children[0].children[0].onActivate?()

            let poppedNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: poppedNode.children[0]).contains("ROOT TITLE"))
            XCTAssertTrue(allTexts(in: poppedNode.children[1]).contains("OPEN"))
        }
    }

    func testNavigationLinkIsActiveBindingPushesAndClearsOnBack() async {
        await MainActor.run {
            var isActive = false
            let stack = NavigationStack {
                VStack(alignment: .leading, spacing: 2) {
                    NavigationLink(
                        destination: Text("DETAIL").navigationTitle("DETAIL TITLE"),
                        isActive: Binding(
                            get: { isActive },
                            set: { isActive = $0 }
                        )
                    ) {
                        Text("OPEN")
                    }
                }
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(stack)

            XCTAssertFalse(isActive)
            XCTAssertTrue(allTexts(in: rootNode.children[1]).contains("OPEN"))

            rootNode.children[1].children[0].onActivate?()

            XCTAssertTrue(isActive)

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("DETAIL TITLE"))
            XCTAssertEqual(detailNode.children[1].text, "DETAIL")

            detailNode.children[0].children[0].children[0].onActivate?()

            XCTAssertFalse(isActive)

            let poppedNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: poppedNode.children[0]).contains("ROOT TITLE"))
            XCTAssertTrue(allTexts(in: poppedNode.children[1]).contains("OPEN"))
        }
    }

    func testNavigationLinkIsActiveTitleOverloadsRenderLabelsAndPush() async {
        await MainActor.run {
            var firstActive = false
            var secondActive = false
            let title: Substring = "OPEN TWO"[...]
            let stack = NavigationStack {
                VStack(alignment: .leading, spacing: 2) {
                    NavigationLink(
                        LocalizedStringKey("OPEN ONE"),
                        destination: Text("DETAIL ONE").navigationTitle("ONE"),
                        isActive: Binding(
                            get: { firstActive },
                            set: { firstActive = $0 }
                        )
                    )
                    NavigationLink(
                        title,
                        destination: Text("DETAIL TWO").navigationTitle("TWO"),
                        isActive: Binding(
                            get: { secondActive },
                            set: { secondActive = $0 }
                        )
                    )
                }
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(stack)

            XCTAssertTrue(allTexts(in: rootNode.children[1]).contains("OPEN ONE"))
            XCTAssertTrue(allTexts(in: rootNode.children[1]).contains("OPEN TWO"))

            rootNode.children[1].children[1].onActivate?()

            XCTAssertFalse(firstActive)
            XCTAssertTrue(secondActive)

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("TWO"))
            XCTAssertEqual(detailNode.children[1].text, "DETAIL TWO")
        }
    }

    func testNavigationLinkTagSelectionPushesAndClearsOnBack() async {
        await MainActor.run {
            var selection: String? = nil
            let stack = NavigationStack {
                VStack(alignment: .leading, spacing: 2) {
                    NavigationLink(
                        destination: Text("DETAIL").navigationTitle("DETAIL TITLE"),
                        tag: "detail",
                        selection: Binding(
                            get: { selection },
                            set: { selection = $0 }
                        )
                    ) {
                        Text("OPEN")
                    }
                }
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(stack)

            XCTAssertNil(selection)
            XCTAssertTrue(allTexts(in: rootNode.children[1]).contains("OPEN"))

            rootNode.children[1].children[0].onActivate?()

            XCTAssertEqual(selection, "detail")

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("DETAIL TITLE"))
            XCTAssertEqual(detailNode.children[1].text, "DETAIL")

            detailNode.children[0].children[0].children[0].onActivate?()

            XCTAssertNil(selection)
        }
    }

    func testNavigationLinkTagSelectionTitleOverloadsRenderLabelsAndPush() async {
        await MainActor.run {
            var selection: Int? = nil
            let title: Substring = "TWO"[...]
            let stack = NavigationStack {
                VStack(alignment: .leading, spacing: 2) {
                    NavigationLink(
                        LocalizedStringKey("ONE"),
                        destination: Text("DETAIL ONE").navigationTitle("ONE TITLE"),
                        tag: 1,
                        selection: Binding(
                            get: { selection },
                            set: { selection = $0 }
                        )
                    )
                    NavigationLink(
                        title,
                        destination: Text("DETAIL TWO").navigationTitle("TWO TITLE"),
                        tag: 2,
                        selection: Binding(
                            get: { selection },
                            set: { selection = $0 }
                        )
                    )
                }
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(stack)

            XCTAssertTrue(allTexts(in: rootNode.children[1]).contains("ONE"))
            XCTAssertTrue(allTexts(in: rootNode.children[1]).contains("TWO"))

            rootNode.children[1].children[1].onActivate?()

            XCTAssertEqual(selection, 2)

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("TWO TITLE"))
            XCTAssertEqual(detailNode.children[1].text, "DETAIL TWO")
        }
    }

    func testNavigationLinkTagSelectionDismissKeepsExternalSelectionChange() async {
        await MainActor.run {
            var selection: String? = nil
            let stack = NavigationStack {
                NavigationLink(
                    destination: Text("DETAIL").navigationTitle("DETAIL TITLE"),
                    tag: "detail",
                    selection: Binding(
                        get: { selection },
                        set: { selection = $0 }
                    )
                ) {
                    Text("OPEN")
                }
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(stack)
            rootNode.children[1].onActivate?()

            XCTAssertEqual(selection, "detail")

            selection = "external"

            let detailNode = makeNode(stack)
            detailNode.children[0].children[0].children[0].onActivate?()

            XCTAssertEqual(selection, "external")
        }
    }

    func testNavigationBarBackButtonHiddenSuppressesRetainedBackControl() async {
        await MainActor.run {
            let stack = NavigationStack {
                NavigationLink(
                    "OPEN",
                    destination: Text("DETAIL")
                        .navigationTitle("DETAIL TITLE")
                        .navigationBarBackButtonHidden()
                )
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(stack)
            rootNode.children[1].onActivate?()

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("DETAIL TITLE"))
            // The band is [header row, bottom hairline]; with the back
            // control hidden the header row carries the title alone.
            XCTAssertEqual(detailNode.children[0].children[0].children.count, 1)
            XCTAssertFalse(allTexts(in: detailNode.children[0]).contains("<"))
            XCTAssertEqual(detailNode.children[1].text, "DETAIL")
        }
    }

    func testNavigationBarBackButtonHiddenFalseKeepsRetainedBackControl() async {
        await MainActor.run {
            let stack = NavigationStack {
                NavigationLink(
                    "OPEN",
                    destination: Text("DETAIL")
                        .navigationTitle("DETAIL TITLE")
                        .navigationBarBackButtonHidden(false)
                )
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(stack)
            rootNode.children[1].onActivate?()

            let detailNode = makeNode(stack)
            XCTAssertEqual(detailNode.children[0].children.count, 2)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("<"))
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("DETAIL TITLE"))
        }
    }

    func testNavigationBarHiddenSuppressesRetainedNavigationChrome() async {
        await MainActor.run {
            let stack = NavigationStack {
                NavigationLink(
                    "OPEN",
                    destination: Text("DETAIL")
                        .navigationTitle("DETAIL TITLE")
                        .navigationBarHidden(true)
                )
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(stack)
            rootNode.children[1].onActivate?()

            let detailNode = makeNode(stack)
            XCTAssertEqual(detailNode.text, "DETAIL")
            XCTAssertFalse(allTexts(in: detailNode).contains("DETAIL TITLE"))
            XCTAssertFalse(allTexts(in: detailNode).contains("<"))
        }
    }

    func testNavigationBarHiddenFalsePreservesRetainedNavigationChrome() async {
        await MainActor.run {
            let stack = NavigationStack {
                NavigationLink(
                    "OPEN",
                    destination: Text("DETAIL")
                        .navigationTitle("DETAIL TITLE")
                        .navigationBarHidden(false)
                )
                .navigationTitle("ROOT TITLE")
            }

            let rootNode = makeNode(stack)
            rootNode.children[1].onActivate?()

            let detailNode = makeNode(stack)
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("DETAIL TITLE"))
            XCTAssertTrue(allTexts(in: detailNode.children[0]).contains("<"))
            XCTAssertEqual(detailNode.children[1].text, "DETAIL")
        }
    }

    func testRootNavigationBarHiddenSuppressesRootNavigationChrome() async {
        await MainActor.run {
            let node = makeNode(
                NavigationStack {
                    Text("ROOT")
                        .navigationTitle("ROOT TITLE")
                        .navigationBarHidden(true)
                }
            )

            XCTAssertEqual(node.text, "ROOT")
            XCTAssertFalse(allTexts(in: node).contains("ROOT TITLE"))
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

            detailNode.children[0].children[0].children[0].onActivate?()

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

            presentedNode.children[0].children[0].children[0].onActivate?()

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

    func testSheetIsPresentedComposesRetainedModalAndDismisses() async {
        await MainActor.run {
            struct SheetContent: View {
                @Environment(\.dismiss) var dismiss
                @Environment(\.isPresented) var isPresented

                var body: some View {
                    VStack {
                        Text(isPresented ? "SHEET" : "ROOT")
                        Button("DONE") {
                            dismiss()
                        }
                    }
                }
            }

            var isPresented = true
            var dismissCount = 0
            var didInvalidate = false
            let view = Text("ROOT")
                .frame(width: 200, height: 100)
                .sheet(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    ),
                    onDismiss: {
                        dismissCount += 1
                    }
                ) {
                    SheetContent()
                }

            let presentedNode = makeNode(
                view,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            guard case .absolute = presentedNode.layoutMode else {
                return XCTFail("Expected sheet presentation to use retained absolute overlay layout")
            }
            XCTAssertEqual(presentedNode.children.count, 2)
            XCTAssertEqual(presentedNode.children.last?.nodeTag, "sheet-overlay")
            XCTAssertTrue(allTexts(in: presentedNode).contains("ROOT"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("SHEET"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DONE"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertFalse(isPresented)
            XCTAssertEqual(dismissCount, 1)
            XCTAssertTrue(didInvalidate)

            let rootNode = makeNode(view)
            XCTAssertTrue(allTexts(in: rootNode).contains("ROOT"))
            XCTAssertFalse(allTexts(in: rootNode).contains("SHEET"))
        }
    }

    func testSheetItemRendersSelectedItemAndClearsOnDismiss() async {
        await MainActor.run {
            struct ItemSheetContent: View {
                let id: String
                @Environment(\.dismiss) var dismiss

                var body: some View {
                    VStack {
                        Text(id)
                        Button("CLOSE") {
                            dismiss()
                        }
                    }
                }
            }

            var selectedItem: NavigationDestinationItem? = NavigationDestinationItem(id: "DETAIL")
            var didDismiss = false
            let view = Text("ROOT")
                .sheet(
                    item: Binding(
                        get: { selectedItem },
                        set: { selectedItem = $0 }
                    ),
                    onDismiss: {
                        didDismiss = true
                    }
                ) { item in
                    ItemSheetContent(id: item.id)
                }

            let presentedNode = makeNode(view)

            XCTAssertTrue(allTexts(in: presentedNode).contains("DETAIL"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("CLOSE"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertNil(selectedItem)
            XCTAssertTrue(didDismiss)

            let rootNode = makeNode(view)
            XCTAssertEqual(allTexts(in: rootNode), ["ROOT"])
        }
    }

    func testInteractiveDismissDisabledControlsRetainedSheetScrimDismissal() async {
        await MainActor.run {
            var defaultPresented = true
            var defaultDismissCount = 0
            let defaultNode = makeNode(
                Text("ROOT")
                    .sheet(
                        isPresented: Binding(
                            get: { defaultPresented },
                            set: { defaultPresented = $0 }
                        ),
                        onDismiss: {
                            defaultDismissCount += 1
                        }
                    ) {
                        Text("SHEET")
                    }
            )

            guard let defaultScrim = presentationOverlayChild(in: defaultNode, overlayTag: "sheet-overlay", index: 0)
            else {
                return
            }
            XCTAssertEqual(defaultScrim.nodeTag, "sheet-scrim-dismiss-enabled")
            XCTAssertTrue(defaultScrim.isHitTestVisible)
            defaultScrim.onActivate?()
            XCTAssertFalse(defaultPresented)
            XCTAssertEqual(defaultDismissCount, 1)

            var disabledPresented = true
            let disabledNode = makeNode(
                Text("ROOT")
                    .sheet(
                        isPresented: Binding(
                            get: { disabledPresented },
                            set: { disabledPresented = $0 }
                        )
                    ) {
                        Text("SHEET")
                            .interactiveDismissDisabled()
                    }
            )

            guard let disabledScrim = presentationOverlayChild(in: disabledNode, overlayTag: "sheet-overlay", index: 0)
            else {
                return
            }
            XCTAssertEqual(disabledScrim.nodeTag, "sheet-scrim-dismiss-disabled")
            XCTAssertFalse(disabledScrim.isHitTestVisible)
            XCTAssertNil(disabledScrim.onActivate)
            XCTAssertTrue(disabledPresented)

            var reenabledPresented = true
            let reenabledNode = makeNode(
                Text("ROOT")
                    .sheet(
                        isPresented: Binding(
                            get: { reenabledPresented },
                            set: { reenabledPresented = $0 }
                        )
                    ) {
                        Text("SHEET")
                            .interactiveDismissDisabled()
                            .interactiveDismissDisabled(false)
                    }
            )

            guard
                let reenabledScrim = presentationOverlayChild(
                    in: reenabledNode,
                    overlayTag: "sheet-overlay",
                    index: 0
                )
            else {
                return
            }
            XCTAssertEqual(reenabledScrim.nodeTag, "sheet-scrim-dismiss-enabled")
            reenabledScrim.onActivate?()
            XCTAssertFalse(reenabledPresented)
        }
    }

    func testPresentationBackgroundInteractionControlsRetainedSheetScrimHitTesting() async {
        await MainActor.run {
            var enabledPresented = true
            var enabledDismissCount = 0
            let enabledNode = makeNode(
                Text("ROOT")
                    .sheet(
                        isPresented: Binding(
                            get: { enabledPresented },
                            set: { enabledPresented = $0 }
                        ),
                        onDismiss: {
                            enabledDismissCount += 1
                        }
                    ) {
                        Text("SHEET")
                            .presentationBackgroundInteraction(.enabled)
                    }
            )

            guard let enabledScrim = presentationOverlayChild(in: enabledNode, overlayTag: "sheet-overlay", index: 0)
            else {
                return
            }
            XCTAssertEqual(enabledScrim.nodeTag, "sheet-scrim-background-interactive")
            XCTAssertFalse(enabledScrim.isHitTestVisible)
            XCTAssertNil(enabledScrim.onActivate)
            XCTAssertTrue(enabledPresented)
            XCTAssertEqual(enabledDismissCount, 0)

            var upThroughPresented = true
            let upThroughNode = makeNode(
                Text("ROOT")
                    .sheet(
                        isPresented: Binding(
                            get: { upThroughPresented },
                            set: { upThroughPresented = $0 }
                        )
                    ) {
                        Text("SHEET")
                            .presentationBackgroundInteraction(.enabled(upThrough: .height(120)))
                    }
            )

            guard
                let upThroughScrim = presentationOverlayChild(
                    in: upThroughNode,
                    overlayTag: "sheet-overlay",
                    index: 0
                )
            else {
                return
            }
            XCTAssertEqual(upThroughScrim.nodeTag, "sheet-scrim-background-interactive")
            XCTAssertFalse(upThroughScrim.isHitTestVisible)
            XCTAssertNil(upThroughScrim.onActivate)
            XCTAssertTrue(upThroughPresented)

            var disabledPresented = true
            let disabledNode = makeNode(
                Text("ROOT")
                    .sheet(
                        isPresented: Binding(
                            get: { disabledPresented },
                            set: { disabledPresented = $0 }
                        )
                    ) {
                        Text("SHEET")
                            .presentationBackgroundInteraction(.enabled)
                            .presentationBackgroundInteraction(.disabled)
                    }
            )

            guard let disabledScrim = presentationOverlayChild(in: disabledNode, overlayTag: "sheet-overlay", index: 0)
            else {
                return
            }
            XCTAssertEqual(disabledScrim.nodeTag, "sheet-scrim-dismiss-enabled")
            XCTAssertTrue(disabledScrim.isHitTestVisible)
            disabledScrim.onActivate?()
            XCTAssertFalse(disabledPresented)
        }
    }

    func testPresentationContentInteractionScrollsWrapsRetainedSheetContent() async {
        await MainActor.run {
            let scrollsNode = makeNode(
                Text("ROOT")
                    .sheet(isPresented: .constant(true)) {
                        VStack {
                            Text("ONE")
                            Text("TWO")
                        }
                        .presentationContentInteraction(.scrolls)
                    }
            )

            guard let sheetPanel = presentationOverlayChild(in: scrollsNode, overlayTag: "sheet-overlay", index: 1)
            else {
                return
            }
            XCTAssertEqual(sheetPanel.children.count, 1)

            let contentScrollNode = sheetPanel.children[0]
            XCTAssertEqual(contentScrollNode.nodeTag, "presentation-content-scrolls")
            XCTAssertEqual(contentScrollNode.scrollAxis, .vertical)
            XCTAssertTrue(contentScrollNode.showsScrollIndicator)
            XCTAssertTrue(contentScrollNode.clipsToBounds)
            XCTAssertTrue(allTexts(in: contentScrollNode).contains("ONE"))
            XCTAssertTrue(allTexts(in: contentScrollNode).contains("TWO"))

            let dragIndicatorNode = makeNode(
                Text("ROOT")
                    .sheet(isPresented: .constant(true)) {
                        Text("DRAGGABLE")
                            .presentationDragIndicator(.visible)
                            .presentationContentInteraction(.scrolls)
                    }
            )

            guard
                let dragIndicatorSheet = presentationOverlayChild(
                    in: dragIndicatorNode,
                    overlayTag: "sheet-overlay",
                    index: 1
                )
            else {
                return
            }
            XCTAssertEqual(dragIndicatorSheet.children.count, 2)
            XCTAssertEqual(dragIndicatorSheet.children[1].nodeTag, "presentation-content-scrolls")

            let resizesNode = makeNode(
                Text("ROOT")
                    .sheet(isPresented: .constant(true)) {
                        Text("RESIZES")
                            .presentationContentInteraction(.scrolls)
                            .presentationContentInteraction(.resizes)
                    }
            )

            guard
                let resizesContent = presentationOverlayChild(in: resizesNode, overlayTag: "sheet-overlay", index: 1)?
                    .children.first
            else {
                return XCTFail("Expected retained sheet content")
            }
            XCTAssertNotEqual(resizesContent.nodeTag, "presentation-content-scrolls")
            XCTAssertNil(resizesContent.scrollAxis)
            XCTAssertTrue(allTexts(in: resizesContent).contains("RESIZES"))
        }
    }

    func testPresentationCompactAdaptationAdaptsRetainedCompactPopovers() async {
        await MainActor.run {
            var sheetPopoverPresented = true
            let sheetNode = makeNode(
                Text("ROOT")
                    .popover(
                        isPresented: Binding(
                            get: { sheetPopoverPresented },
                            set: { sheetPopoverPresented = $0 }
                        )
                    ) {
                        Text("SHEET POPOVER")
                            .presentationCompactAdaptation(.sheet)
                    }
                    .environment(\.horizontalSizeClass, .compact)
            )

            XCTAssertEqual(sheetNode.children.count, 2)
            guard let sheetScrim = presentationOverlayChild(in: sheetNode, overlayTag: "sheet-overlay", index: 0),
                let sheetPanel = presentationOverlayChild(in: sheetNode, overlayTag: "sheet-overlay", index: 1)
            else {
                return
            }
            XCTAssertEqual(sheetScrim.nodeTag, "sheet-scrim-dismiss-enabled")
            XCTAssertTrue(allTexts(in: sheetPanel).contains("SHEET POPOVER"))
            sheetScrim.onActivate?()
            XCTAssertFalse(sheetPopoverPresented)

            let fullScreenNode = makeNode(
                Text("ROOT")
                    .popover(isPresented: .constant(true)) {
                        Text("FULL POPOVER")
                            .presentationCompactAdaptation(
                                horizontal: .none,
                                vertical: .fullScreenCover
                            )
                    }
                    .environment(\.horizontalSizeClass, .compact)
                    .environment(\.verticalSizeClass, .compact),
                size: Size(width: 320, height: 180)
            )
            fullScreenNode.onLayout?(Rect(x: 0, y: 0, width: 320, height: 180))

            XCTAssertEqual(fullScreenNode.children.count, 2)
            guard
                let coverPanel = presentationOverlayChild(
                    in: fullScreenNode,
                    overlayTag: "full-screen-cover-overlay",
                    index: 0
                )
            else {
                return
            }
            XCTAssertTrue(allTexts(in: coverPanel).contains("FULL POPOVER"))
            XCTAssertEqual(coverPanel.frame, Rect(x: 0, y: 0, width: 320, height: 180))

            let noneNode = makeNode(
                Text("ROOT")
                    .frame(width: 200, height: 100)
                    .popover(isPresented: .constant(true), arrowEdge: .bottom) {
                        Text("PLAIN POPOVER")
                            .presentationCompactAdaptation(.none)
                    }
                    .environment(\.horizontalSizeClass, .compact),
                size: Size(width: 320, height: 180)
            )
            noneNode.onLayout?(Rect(x: 0, y: 0, width: 320, height: 180))

            XCTAssertEqual(noneNode.children.count, 2)
            guard
                let plainPopoverPanel = presentationOverlayChild(in: noneNode, overlayTag: "popover-overlay", index: 1)
            else {
                return
            }
            XCTAssertTrue(allTexts(in: plainPopoverPanel).contains("PLAIN POPOVER"))
            XCTAssertNotEqual(plainPopoverPanel.frame, Rect(x: 0, y: 0, width: 320, height: 180))
        }
    }

    func testPresentationDetentAndDismissModifiersPreserveRetainedSheetContent() async {
        await MainActor.run {
            struct SheetContent: View {
                @Environment(\.dismiss) var dismiss

                var body: some View {
                    VStack {
                        Text("DETENT SHEET")
                        Button("DONE") {
                            dismiss()
                        }
                    }
                    .presentationDetents([.medium, .large, .height(320), .fraction(0.4)])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
                }
            }

            var isPresented = true
            var selectedDetent = PresentationDetent.medium
            var didDismiss = false
            let view = Text("ROOT")
                .sheet(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    ),
                    onDismiss: {
                        didDismiss = true
                    }
                ) {
                    SheetContent()
                        .presentationDetents(
                            [.medium, .large],
                            selection: Binding(
                                get: { selectedDetent },
                                set: { selectedDetent = $0 }
                            )
                        )
                }

            let presentedNode = makeNode(view)

            XCTAssertEqual(Set<PresentationDetent>([.medium, .large, .height(320), .fraction(0.4)]).count, 4)
            XCTAssertTrue(allTexts(in: presentedNode).contains("DETENT SHEET"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DONE"))
            guard let sheetPanel = presentationOverlayChild(in: presentedNode, overlayTag: "sheet-overlay", index: 1)
            else {
                return
            }
            XCTAssertEqual(sheetPanel.children.count, 2)
            XCTAssertEqual(sheetPanel.children.first?.children.first?.preferredSize, Size(width: 36, height: 5))
            XCTAssertEqual(sheetPanel.children.first?.children.first?.cornerRadius, 2.5)

            let (_, renderedPresentedNode) = makeRuntimeNode(view, size: Size(width: 800, height: 600))
            guard
                let renderedSheetPanel = presentationOverlayChild(
                    in: renderedPresentedNode,
                    overlayTag: "sheet-overlay",
                    index: 1
                )
            else {
                return
            }
            XCTAssertEqual(
                renderedSheetPanel.frame.size.height,
                276,
                accuracy: 0.001
            )

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertFalse(isPresented)
            XCTAssertTrue(didDismiss)
            XCTAssertEqual(selectedDetent, .medium)

            let hiddenIndicatorNode = makeNode(
                Text("ROOT")
                    .sheet(isPresented: .constant(true)) {
                        Text("NO HANDLE")
                            .presentationDragIndicator(.visible)
                            .presentationDragIndicator(.hidden)
                    }
            )
            guard
                let hiddenIndicatorPanel = presentationOverlayChild(
                    in: hiddenIndicatorNode,
                    overlayTag: "sheet-overlay",
                    index: 1
                )
            else {
                return
            }
            XCTAssertEqual(hiddenIndicatorPanel.children.count, 1)

            let (_, heightDetentNode) = makeRuntimeNode(
                Text("ROOT")
                    .sheet(isPresented: .constant(true)) {
                        Text("HEIGHT")
                            .presentationDetents([.height(320)])
                    },
                size: Size(width: 800, height: 600)
            )
            guard
                let heightDetentPanel = presentationOverlayChild(
                    in: heightDetentNode,
                    overlayTag: "sheet-overlay",
                    index: 1
                )
            else {
                return
            }
            XCTAssertEqual(heightDetentPanel.frame.size.height, 320, accuracy: 0.001)
            XCTAssertEqual(heightDetentPanel.frame.origin.y, 280, accuracy: 0.001)

            let (_, fractionDetentNode) = makeRuntimeNode(
                Text("ROOT")
                    .sheet(isPresented: .constant(true)) {
                        Text("FRACTION")
                            .presentationDetents([.fraction(0.25)])
                    },
                size: Size(width: 800, height: 600)
            )
            guard
                let fractionDetentPanel = presentationOverlayChild(
                    in: fractionDetentNode,
                    overlayTag: "sheet-overlay",
                    index: 1
                )
            else {
                return
            }
            XCTAssertEqual(
                fractionDetentPanel.frame.size.height,
                138,
                accuracy: 0.001
            )
        }
    }

    func testPresentationBackgroundAndCornerRadiusModifiersPreserveRetainedSheetContent() async {
        await MainActor.run {
            struct SheetContent: View {
                @Environment(\.dismiss) var dismiss

                var body: some View {
                    let gradient = LinearGradient(
                        colors: [.red, .blue],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    return VStack {
                        Text("STYLED SHEET")
                        Button("DONE") {
                            dismiss()
                        }
                    }
                    .presentationBackground(Color(red: 0.186, green: 0.186, blue: 0.186, alpha: 1))
                    .presentationBackground(ForegroundStyle.color(.secondary))
                    .presentationBackground(gradient)
                    .presentationBackground(alignment: .top) {
                        Text("PRESENTATION BACKGROUND")
                    }
                    .presentationCornerRadius(22)
                }
            }

            var isPresented = true
            let view = Text("ROOT")
                .sheet(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    )
                ) {
                    SheetContent()
                }

            let presentedNode = makeNode(view)

            XCTAssertTrue(allTexts(in: presentedNode).contains("STYLED SHEET"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DONE"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("PRESENTATION BACKGROUND"))
            guard let sheetPanel = presentationOverlayChild(in: presentedNode, overlayTag: "sheet-overlay", index: 1)
            else {
                return
            }
            XCTAssertNil(sheetPanel.backgroundColor)
            XCTAssertEqual(sheetPanel.backgroundGradient?.startColor, .red)
            XCTAssertEqual(sheetPanel.backgroundGradient?.endColor, .blue)
            XCTAssertEqual(sheetPanel.cornerRadius, 22)

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertFalse(isPresented)

            let resetNode = makeNode(
                Text("ROOT")
                    .sheet(isPresented: .constant(true)) {
                        SheetContent()
                            .presentationBackground(nil as Color?)
                            .presentationCornerRadius(nil)
                    }
            )
            guard let resetSheetPanel = presentationOverlayChild(in: resetNode, overlayTag: "sheet-overlay", index: 1)
            else {
                return
            }
            XCTAssertNil(resetSheetPanel.backgroundColor)
            XCTAssertNil(resetSheetPanel.backgroundGradient)
            XCTAssertEqual(resetSheetPanel.cornerRadius, 14)
        }
    }

    func testPresentationBackgroundAndCornerRadiusApplyToPopoverAndFullScreenCover() async {
        await MainActor.run {
            let popoverColor = Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
            let popoverNode = makeNode(
                Text("ROOT")
                    .popover(isPresented: .constant(true)) {
                        Text("POPOVER")
                            .presentationBackground(popoverColor)
                            .presentationCornerRadius(9)
                            .presentationDragIndicator(.visible)
                    }
            )

            guard let popoverPanel = presentationOverlayChild(in: popoverNode, overlayTag: "popover-overlay", index: 1)
            else {
                return
            }
            XCTAssertEqual(popoverPanel.backgroundColor, popoverColor)
            XCTAssertNil(popoverPanel.backgroundGradient)
            XCTAssertEqual(popoverPanel.cornerRadius, 9)
            XCTAssertEqual(popoverPanel.children.count, 2)

            let coverGradient = LinearGradient(
                colors: [.green, .blue],
                startPoint: .leading,
                endPoint: .trailing
            )
            let coverNode = makeNode(
                Text("ROOT")
                    .fullScreenCover(isPresented: .constant(true)) {
                        Text("COVER")
                            .presentationBackground(coverGradient)
                            .presentationCornerRadius(4)
                            .presentationDragIndicator(.visible)
                    }
            )

            guard
                let coverPanel = presentationOverlayChild(
                    in: coverNode,
                    overlayTag: "full-screen-cover-overlay",
                    index: 0
                )
            else {
                return
            }
            XCTAssertNil(coverPanel.backgroundColor)
            XCTAssertEqual(coverPanel.backgroundGradient?.startColor, .green)
            XCTAssertEqual(coverPanel.backgroundGradient?.endColor, .blue)
            XCTAssertEqual(coverPanel.cornerRadius, 4)
            XCTAssertTrue(coverPanel.clipsToBounds)
            XCTAssertEqual(coverPanel.children.count, 2)
        }
    }

    func testPresentationInteractionAndAdaptationModifiersPreserveRetainedSheetContent() async {
        await MainActor.run {
            struct SheetContent: View {
                @Environment(\.dismiss) var dismiss

                var body: some View {
                    VStack {
                        Text("ADAPTIVE SHEET")
                        Button("DONE") {
                            dismiss()
                        }
                    }
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(120)))
                    .presentationBackgroundInteraction(.disabled)
                    .presentationContentInteraction(.scrolls)
                    .presentationContentInteraction(.resizes)
                    .presentationCompactAdaptation(.none)
                    .presentationCompactAdaptation(horizontal: .popover, vertical: .fullScreenCover)
                }
            }

            var isPresented = true
            let interactions: Set<PresentationBackgroundInteraction> = [
                .automatic,
                .disabled,
                .enabled,
                .enabled(upThrough: .medium),
            ]
            let adaptations: Set<PresentationAdaptation> = [
                .automatic,
                .none,
                .popover,
                .sheet,
                .fullScreenCover,
            ]
            let contentInteractions: Set<PresentationContentInteraction> = [
                .automatic,
                .resizes,
                .scrolls,
            ]
            let view = Text("ROOT")
                .sheet(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    )
                ) {
                    SheetContent()
                }

            let presentedNode = makeNode(view)

            XCTAssertEqual(interactions.count, 4)
            XCTAssertEqual(adaptations.count, 5)
            XCTAssertEqual(contentInteractions.count, 3)
            XCTAssertTrue(allTexts(in: presentedNode).contains("ADAPTIVE SHEET"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DONE"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertFalse(isPresented)
        }
    }

    func testFullScreenCoverIsPresentedComposesRetainedCoverAndDismisses() async {
        await MainActor.run {
            struct FullScreenCoverContent: View {
                @Environment(\.dismiss) var dismiss
                @Environment(\.isPresented) var isPresented

                var body: some View {
                    VStack {
                        Text(isPresented ? "FULL COVER" : "ROOT")
                        Button("DONE") {
                            dismiss()
                        }
                    }
                }
            }

            var isPresented = true
            var dismissCount = 0
            var didInvalidate = false
            let view = Text("ROOT")
                .frame(width: 240, height: 140)
                .fullScreenCover(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    ),
                    onDismiss: {
                        dismissCount += 1
                    }
                ) {
                    FullScreenCoverContent()
                }

            let presentedNode = makeNode(
                view,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            guard case .absolute = presentedNode.layoutMode else {
                return XCTFail("Expected fullScreenCover to use retained absolute overlay layout")
            }
            XCTAssertEqual(presentedNode.children.count, 2)
            XCTAssertTrue(allTexts(in: presentedNode).contains("ROOT"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("FULL COVER"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DONE"))

            presentedNode.onLayout?(Rect(x: 0, y: 0, width: 240, height: 140))
            XCTAssertEqual(presentedNode.children[1].frame, Rect(x: 0, y: 0, width: 240, height: 140))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertFalse(isPresented)
            XCTAssertEqual(dismissCount, 1)
            XCTAssertTrue(didInvalidate)

            let rootNode = makeNode(view)
            XCTAssertTrue(allTexts(in: rootNode).contains("ROOT"))
            XCTAssertFalse(allTexts(in: rootNode).contains("FULL COVER"))
        }
    }

    func testFullScreenCoverItemRendersSelectedItemAndClearsOnDismiss() async {
        await MainActor.run {
            struct ItemFullScreenCoverContent: View {
                let id: String
                @Environment(\.dismiss) var dismiss

                var body: some View {
                    VStack {
                        Text(id)
                        Button("CLOSE") {
                            dismiss()
                        }
                    }
                }
            }

            var selectedItem: NavigationDestinationItem? = NavigationDestinationItem(id: "FULL DETAIL")
            var didDismiss = false
            let view = Text("ROOT")
                .fullScreenCover(
                    item: Binding(
                        get: { selectedItem },
                        set: { selectedItem = $0 }
                    ),
                    onDismiss: {
                        didDismiss = true
                    }
                ) { item in
                    ItemFullScreenCoverContent(id: item.id)
                }

            let presentedNode = makeNode(view)

            XCTAssertTrue(allTexts(in: presentedNode).contains("FULL DETAIL"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("CLOSE"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertNil(selectedItem)
            XCTAssertTrue(didDismiss)

            let rootNode = makeNode(view)
            XCTAssertEqual(rootNode.text, "ROOT")
        }
    }

    func testPopoverIsPresentedComposesRetainedFloatingPanelAndDismisses() async {
        await MainActor.run {
            struct PopoverContent: View {
                @Environment(\.dismiss) var dismiss
                @Environment(\.isPresented) var isPresented

                var body: some View {
                    VStack {
                        Text(isPresented ? "POPOVER" : "ROOT")
                        Button("CLOSE") {
                            dismiss()
                        }
                    }
                }
            }

            var isPresented = true
            var didInvalidate = false
            let view = Text("ROOT")
                .frame(width: 200, height: 100)
                .popover(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    ),
                    attachmentAnchor: .point(.top),
                    arrowEdge: .bottom
                ) {
                    PopoverContent()
                }

            let presentedNode = makeNode(
                view,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            guard case .absolute = presentedNode.layoutMode else {
                return XCTFail("Expected popover presentation to use retained absolute overlay layout")
            }
            XCTAssertEqual(presentedNode.children.count, 2)
            XCTAssertTrue(allTexts(in: presentedNode).contains("ROOT"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("POPOVER"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("CLOSE"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertFalse(isPresented)
            XCTAssertTrue(didInvalidate)

            let rootNode = makeNode(view)
            XCTAssertTrue(allTexts(in: rootNode).contains("ROOT"))
            XCTAssertFalse(allTexts(in: rootNode).contains("POPOVER"))
        }
    }

    func testPopoverAttachmentAnchorPositionsRetainedFloatingPanel() async {
        await MainActor.run {
            let topLeadingNode = makeNode(
                Text("ROOT")
                    .frame(width: 120, height: 80)
                    .popover(
                        isPresented: .constant(true),
                        attachmentAnchor: .point(.topLeading),
                        arrowEdge: .top
                    ) {
                        Text("TOP")
                            .frame(width: 80, height: 40)
                    },
                size: Size(width: 320, height: 200)
            )
            topLeadingNode.onLayout?(Rect(x: 0, y: 0, width: 320, height: 200))

            guard let topLeadingPopover = topLeadingNode.children.last else {
                return XCTFail("Expected top-leading retained popover")
            }
            XCTAssertEqual(topLeadingPopover.frame.origin.x, 0, accuracy: 0.001)
            XCTAssertEqual(topLeadingPopover.frame.origin.y, 0, accuracy: 0.001)

            let bottomTrailingNode = makeNode(
                Text("ROOT")
                    .frame(width: 120, height: 80)
                    .popover(
                        isPresented: .constant(true),
                        attachmentAnchor: .rect(.bottomTrailing),
                        arrowEdge: .bottom
                    ) {
                        Text("BOTTOM")
                            .frame(width: 80, height: 40)
                    },
                size: Size(width: 320, height: 200)
            )
            bottomTrailingNode.onLayout?(Rect(x: 0, y: 0, width: 320, height: 200))

            guard let bottomTrailingPopover = bottomTrailingNode.children.last else {
                return XCTFail("Expected bottom-trailing retained popover")
            }
            XCTAssertEqual(
                bottomTrailingPopover.frame.origin.x + bottomTrailingPopover.frame.size.width,
                320,
                accuracy: 0.001
            )
            XCTAssertEqual(
                bottomTrailingPopover.frame.origin.y + bottomTrailingPopover.frame.size.height,
                200,
                accuracy: 0.001
            )
            XCTAssertTrue(allTexts(in: bottomTrailingPopover).contains("BOTTOM"))
        }
    }

    func testPopoverItemRendersSelectedItemAndClearsOnDismiss() async {
        await MainActor.run {
            struct ItemPopoverContent: View {
                let id: String
                @Environment(\.dismiss) var dismiss

                var body: some View {
                    VStack {
                        Text(id)
                        Button("CLOSE") {
                            dismiss()
                        }
                    }
                }
            }

            var selectedItem: NavigationDestinationItem? = NavigationDestinationItem(id: "POPOVER DETAIL")
            let view = Text("ROOT")
                .popover(
                    item: Binding(
                        get: { selectedItem },
                        set: { selectedItem = $0 }
                    ),
                    arrowEdge: .trailing
                ) { item in
                    ItemPopoverContent(id: item.id)
                }

            let presentedNode = makeNode(view)

            XCTAssertTrue(allTexts(in: presentedNode).contains("POPOVER DETAIL"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("CLOSE"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertNil(selectedItem)

            let rootNode = makeNode(view)
            XCTAssertEqual(rootNode.text, "ROOT")
        }
    }

    func testAlertIsPresentedComposesRetainedModalAndDismissesActionButton() async {
        await MainActor.run {
            var isPresented = true
            var didConfirm = false
            var didInvalidate = false
            let view = Text("ROOT")
                .frame(width: 240, height: 120)
                .alert(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    )
                ) {
                    Alert(
                        title: Text("DELETE ITEM"),
                        message: Text("THIS CANNOT BE UNDONE"),
                        primaryButton: .destructive(Text("DELETE")) {
                            didConfirm = true
                        },
                        secondaryButton: .cancel(Text("CANCEL"))
                    )
                }

            let (runtime, presentedNode) = makeRuntimeNode(
                view,
                onInvalidate: {
                    didInvalidate = true
                }
            )
            defer { withExtendedLifetime(runtime) {} }

            guard case .absolute = presentedNode.layoutMode else {
                return XCTFail("Expected alert presentation to use retained absolute overlay layout")
            }
            XCTAssertEqual(presentedNode.children.count, 2)
            XCTAssertEqual(presentedNode.children.last?.nodeTag, "alert-overlay")
            XCTAssertTrue(allTexts(in: presentedNode).contains("ROOT"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DELETE ITEM"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("THIS CANNOT BE UNDONE"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DELETE"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("CANCEL"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertTrue(didConfirm)
            XCTAssertFalse(isPresented)
            XCTAssertTrue(didInvalidate)

            let rootNode = makeNode(view)
            XCTAssertTrue(allTexts(in: rootNode).contains("ROOT"))
            XCTAssertFalse(allTexts(in: rootNode).contains("DELETE ITEM"))
        }
    }

    func testAlertItemRendersSelectedItemAndClearsOnDismiss() async {
        await MainActor.run {
            var selectedItem: NavigationDestinationItem? = NavigationDestinationItem(id: "ALERT DETAIL")
            let view = Text("ROOT")
                .alert(
                    item: Binding(
                        get: { selectedItem },
                        set: { selectedItem = $0 }
                    )
                ) { item in
                    Alert(
                        title: Text(item.id),
                        dismissButton: .default(Text("OK"))
                    )
                }

            let (runtime, presentedNode) = makeRuntimeNode(view)
            defer { withExtendedLifetime(runtime) {} }

            XCTAssertTrue(allTexts(in: presentedNode).contains("ALERT DETAIL"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("OK"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertNil(selectedItem)

            let rootNode = makeNode(view)
            XCTAssertEqual(allTexts(in: rootNode), ["ROOT"])
        }
    }

    func testBuilderAlertProvidesPresentationEnvironmentAndDefaultDismissButton() async {
        await MainActor.run {
            struct AlertMessage: View {
                @Environment(\.isPresented) var isPresented

                var body: some View {
                    Text(isPresented ? "PRESENTED MESSAGE" : "HIDDEN MESSAGE")
                }
            }

            var isPresented = true
            let view = Text("ROOT")
                .alert(
                    "NETWORK ERROR",
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    ),
                    actions: {}
                ) {
                    AlertMessage()
                }

            let (runtime, presentedNode) = makeRuntimeNode(view)
            defer { withExtendedLifetime(runtime) {} }

            XCTAssertTrue(allTexts(in: presentedNode).contains("NETWORK ERROR"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("PRESENTED MESSAGE"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("OK"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertFalse(isPresented)

            let rootNode = makeNode(view)
            XCTAssertEqual(allTexts(in: rootNode), ["ROOT"])
        }
    }

    func testActionSheetIsPresentedComposesRetainedDialogAndDismissesButton() async {
        await MainActor.run {
            var isPresented = true
            var didDelete = false
            var didInvalidate = false
            let view = Text("ROOT")
                .frame(width: 240, height: 120)
                .actionSheet(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    )
                ) {
                    ActionSheet(
                        title: Text("FILE ACTIONS"),
                        message: Text("CHOOSE ONE"),
                        buttons: [
                            .destructive(Text("DELETE")) {
                                didDelete = true
                            },
                            .cancel(Text("KEEP")),
                        ]
                    )
                }

            let presentedNode = makeNode(
                view,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            guard case .absolute = presentedNode.layoutMode else {
                return XCTFail("Expected actionSheet to use retained absolute overlay layout")
            }
            XCTAssertEqual(presentedNode.children.count, 2)
            XCTAssertEqual(presentedNode.children.last?.nodeTag, "confirmation-dialog-overlay")
            XCTAssertTrue(allTexts(in: presentedNode).contains("ROOT"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("FILE ACTIONS"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("CHOOSE ONE"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DELETE"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("KEEP"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertTrue(didDelete)
            XCTAssertFalse(isPresented)
            XCTAssertTrue(didInvalidate)

            let rootNode = makeNode(view)
            XCTAssertTrue(allTexts(in: rootNode).contains("ROOT"))
            XCTAssertFalse(allTexts(in: rootNode).contains("FILE ACTIONS"))
        }
    }

    func testActionSheetItemRendersSelectedItemAndClearsOnDismiss() async {
        await MainActor.run {
            var selectedItem: NavigationDestinationItem? = NavigationDestinationItem(id: "SHEET DETAIL")
            let view = Text("ROOT")
                .actionSheet(
                    item: Binding(
                        get: { selectedItem },
                        set: { selectedItem = $0 }
                    )
                ) { item in
                    ActionSheet(
                        title: Text(item.id),
                        buttons: [.default(Text("OPEN"))]
                    )
                }

            let presentedNode = makeNode(view)

            XCTAssertTrue(allTexts(in: presentedNode).contains("SHEET DETAIL"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("OPEN"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertNil(selectedItem)

            let rootNode = makeNode(view)
            XCTAssertEqual(rootNode.text, "ROOT")
        }
    }

    func testConfirmationDialogComposesRetainedDialogAndDefaultCancelDismisses() async {
        await MainActor.run {
            struct DialogMessage: View {
                @Environment(\.isPresented) var isPresented

                var body: some View {
                    Text(isPresented ? "DIALOG PRESENTED" : "DIALOG HIDDEN")
                }
            }

            var isPresented = true
            var didInvalidate = false
            let view = Text("ROOT")
                .frame(width: 260, height: 140)
                .confirmationDialog(
                    "DISCARD CHANGES",
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    ),
                    actions: {},
                    message: {
                        DialogMessage()
                    }
                )

            let presentedNode = makeNode(
                view,
                onInvalidate: {
                    didInvalidate = true
                }
            )

            guard case .absolute = presentedNode.layoutMode else {
                return XCTFail("Expected confirmation dialog to use retained absolute overlay layout")
            }
            XCTAssertEqual(presentedNode.children.count, 2)
            XCTAssertEqual(presentedNode.children.last?.nodeTag, "confirmation-dialog-overlay")
            XCTAssertTrue(allTexts(in: presentedNode).contains("ROOT"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DISCARD CHANGES"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("DIALOG PRESENTED"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("Cancel"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertFalse(isPresented)
            XCTAssertTrue(didInvalidate)

            let rootNode = makeNode(view)
            XCTAssertTrue(allTexts(in: rootNode).contains("ROOT"))
            XCTAssertFalse(allTexts(in: rootNode).contains("DISCARD CHANGES"))
        }
    }

    func testConfirmationDialogPresentingRendersDataAndCanHideTitle() async {
        await MainActor.run {
            struct DismissDialogButton: View {
                @Environment(\.dismiss) var dismiss
                let title: String
                let action: @MainActor () -> Void

                var body: some View {
                    Button(title, role: .destructive) {
                        action()
                        dismiss()
                    }
                }
            }

            var isPresented = true
            var didArchive = false
            let item = NavigationDestinationItem(id: "ALERT DETAIL")
            let view = Text("ROOT")
                .confirmationDialog(
                    "ACTIONS",
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    ),
                    presenting: item,
                    titleVisibility: .hidden
                ) { presentedItem in
                    DismissDialogButton(title: "ARCHIVE \(presentedItem.id)") {
                        didArchive = true
                    }
                } message: { presentedItem in
                    Text("MESSAGE \(presentedItem.id)")
                }

            let presentedNode = makeNode(view)

            XCTAssertTrue(allTexts(in: presentedNode).contains("ROOT"))
            XCTAssertFalse(allTexts(in: presentedNode).contains("ACTIONS"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("MESSAGE ALERT DETAIL"))
            XCTAssertTrue(allTexts(in: presentedNode).contains("ARCHIVE ALERT DETAIL"))

            firstFocusable(in: presentedNode)?.onActivate?()

            XCTAssertTrue(didArchive)
            XCTAssertFalse(isPresented)

            let rootNode = makeNode(view)
            XCTAssertEqual(rootNode.text, "ROOT")
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

            itemNode.children[0].children[0].children[0].onActivate?()

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

    func testForEachRetainsDynamicDeleteAndMoveActionsForListRows() async {
        await MainActor.run {
            var deletedOffsets: [[Int]] = []
            var movedOffsets: [([Int], Int)] = []

            let node = makeNode(
                List {
                    ForEach(["ONE", "TWO", "THREE"], id: \.self) { title in
                        Text(title)
                    }
                    .onDelete { offsets in
                        deletedOffsets.append(Array(offsets))
                    }
                    .onMove { offsets, destination in
                        movedOffsets.append((Array(offsets), destination))
                    }
                }
            )

            XCTAssertEqual(listRows(of: node).count, 3)
            XCTAssertEqual(listRows(of: node)[0].dynamicContentIndex, 0)
            XCTAssertEqual(listRows(of: node)[1].dynamicContentIndex, 1)
            XCTAssertEqual(listRows(of: node)[2].dynamicContentIndex, 2)
            XCTAssertNotNil(listRows(of: node)[1].onDeleteRows)
            XCTAssertNotNil(listRows(of: node)[1].onMoveRows)

            listRows(of: node)[1].onDeleteRows?(IndexSet(integer: listRows(of: node)[1].dynamicContentIndex ?? -1))
            listRows(of: node)[2].onMoveRows?(IndexSet(integer: listRows(of: node)[2].dynamicContentIndex ?? -1), 0)

            XCTAssertEqual(deletedOffsets, [[1]])
            XCTAssertEqual(movedOffsets.count, 1)
            XCTAssertEqual(movedOffsets.first?.0, [2])
            XCTAssertEqual(movedOffsets.first?.1, 0)
        }
    }

    func testForEachNilDeleteAndMoveActionsClearRetainedListRowActions() async {
        await MainActor.run {
            let node = makeNode(
                List {
                    ForEach(["ONE"], id: \.self) { title in
                        Text(title)
                    }
                    .onDelete { _ in }
                    .onMove { _, _ in }
                    .onDelete(perform: nil)
                    .onMove(perform: nil)
                }
            )

            XCTAssertEqual(listRows(of: node)[0].dynamicContentIndex, 0)
            XCTAssertNil(listRows(of: node)[0].onDeleteRows)
            XCTAssertNil(listRows(of: node)[0].onMoveRows)
        }
    }

    func testForEachRetainsDynamicInsertActionsForListRows() async {
        await MainActor.run {
            var insertedOffsets: [Int] = []
            var insertedProviderCounts: [Int] = []
            let provider = NSItemProvider(object: "payload")

            let node = makeNode(
                List {
                    ForEach(["ONE", "TWO"], id: \.self) { title in
                        Text(title)
                    }
                    .onInsert(of: [.plainText, .url]) { offset, providers in
                        insertedOffsets.append(offset)
                        insertedProviderCounts.append(providers.count)
                    }
                }
            )

            XCTAssertEqual(listRows(of: node)[0].dynamicInsertContentTypes, ["public.plain-text", "public.url"])
            XCTAssertEqual(listRows(of: node)[1].dynamicInsertContentTypes, ["public.plain-text", "public.url"])
            XCTAssertNotNil(listRows(of: node)[0].onInsertRows)

            listRows(of: node)[0].onInsertRows?(1, [provider])

            XCTAssertEqual(insertedOffsets, [1])
            XCTAssertEqual(insertedProviderCounts, [1])
        }
    }

    func testForEachRetainsDeprecatedStringInsertIdentifiers() async {
        await MainActor.run {
            var insertedOffsets: [Int] = []

            let node = makeNode(
                List {
                    ForEach(["ONE"], id: \.self) { title in
                        Text(title)
                    }
                    .onInsert(of: ["public.text"]) { offset, _ in
                        insertedOffsets.append(offset)
                    }
                }
            )

            XCTAssertEqual(listRows(of: node)[0].dynamicInsertContentTypes, ["public.text"])
            listRows(of: node)[0].onInsertRows?(0, [NSItemProvider()])

            XCTAssertEqual(insertedOffsets, [0])
        }
    }

    func testForEachRetainsDynamicDropDestinationForListRows() async {
        await MainActor.run {
            struct DropPayload: Transferable, Equatable {
                let value: String
            }

            var droppedPayloads: [[DropPayload]] = []
            var droppedOffsets: [Int] = []

            let node = makeNode(
                List {
                    ForEach(["ONE"], id: \.self) { title in
                        Text(title)
                    }
                    .dropDestination(for: DropPayload.self) { payloads, offset in
                        droppedPayloads.append(payloads)
                        droppedOffsets.append(offset)
                    }
                }
            )

            XCTAssertEqual(listRows(of: node)[0].dynamicDropPayloadType, String(reflecting: DropPayload.self))
            XCTAssertNotNil(listRows(of: node)[0].onDropRows)

            listRows(of: node)[0].onDropRows?([DropPayload(value: "one"), "ignored"], 2)

            XCTAssertEqual(droppedPayloads, [[DropPayload(value: "one")]])
            XCTAssertEqual(droppedOffsets, [2])
        }
    }

    func testItemProviderAndOnDragRetainDragSourceMetadata() async {
        await MainActor.run {
            var itemProviderCalls = 0
            let itemProviderNode = makeNode(
                Text("DRAG")
                    .itemProvider {
                        itemProviderCalls += 1
                        let provider = NSItemProvider(object: "payload")
                        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier)
                        return provider
                    }
            )

            XCTAssertTrue(itemProviderNode.isHitTestVisible)
            XCTAssertEqual(itemProviderNode.dragItemProviderTypeIdentifiers, [])
            XCTAssertNotNil(itemProviderNode.onMakeDragItemProvider)
            XCTAssertEqual(
                (itemProviderNode.onMakeDragItemProvider?() as? NSItemProvider)?.registeredTypeIdentifiers,
                [UTType.plainText.identifier]
            )

            itemProviderNode.onDragStart?(Point(x: 1, y: 2))
            XCTAssertEqual(itemProviderCalls, 2)

            var onDragCalls = 0
            let onDragNode = makeNode(
                Text("SOURCE")
                    .onDrag {
                        onDragCalls += 1
                        return NSItemProvider(object: "drag")
                    } preview: {
                        Text("PREVIEW")
                    }
            )

            XCTAssertEqual(onDragNode.dragItemProviderTypeIdentifiers, [UTType.data.identifier])
            XCTAssertEqual(onDragNode.hasDragPreview, true)
            onDragNode.onDragStart?(Point(x: 3, y: 4))

            XCTAssertEqual(onDragCalls, 1)
        }
    }

    func testDraggableRetainsTransferablePayloadMetadata() async {
        await MainActor.run {
            struct DragPayload: Transferable, Equatable {
                let value: String
            }

            var payloadCalls = 0
            func makePayload() -> DragPayload {
                payloadCalls += 1
                return DragPayload(value: "one")
            }
            let node = makeNode(
                Text("DRAG")
                    .draggable(makePayload()) {
                        Text("PREVIEW")
                    }
            )

            XCTAssertTrue(node.isHitTestVisible)
            XCTAssertEqual(node.dragPayloadType, String(reflecting: DragPayload.self))
            XCTAssertEqual(node.hasDragPreview, true)
            XCTAssertEqual(node.onMakeDragPayload?() as? DragPayload, DragPayload(value: "one"))

            node.onDragStart?(Point(x: 5, y: 6))

            XCTAssertEqual(payloadCalls, 2)
        }
    }

    func testContainerDraggableRetainsItemAndNamespaceMetadata() async {
        await MainActor.run {
            struct DragPayload: Transferable, Identifiable, Equatable {
                let id: String
                let value: String
            }

            let namespaceID = Namespace().wrappedValue
            var payloadCalls = 0
            let node = makeNode(
                Text("DRAG")
                    .draggable(DragPayload.self, containerNamespace: namespaceID) {
                        payloadCalls += 1
                        return DragPayload(id: "row-1", value: "one")
                    }
            )

            XCTAssertEqual(node.dragPayloadType, String(reflecting: DragPayload.self))
            XCTAssertEqual(node.dragContainerNamespaceID, namespaceID.description)
            XCTAssertEqual(node.onMakeDragPayload?() as? DragPayload, DragPayload(id: "row-1", value: "one"))
            node.onDragStart?(Point(x: 7, y: 8))
            XCTAssertEqual(payloadCalls, 2)

            let keyedNode = makeNode(
                Text("KEYED")
                    .draggable(DragPayload.self, id: \.value, containerNamespace: namespaceID) {
                        DragPayload(id: "row-2", value: "two")
                    }
            )
            XCTAssertEqual(keyedNode.dragPayloadType, String(reflecting: DragPayload.self))
            XCTAssertEqual(keyedNode.dragContainerNamespaceID, namespaceID.description)
            XCTAssertEqual(keyedNode.onMakeDragPayload?() as? DragPayload, DragPayload(id: "row-2", value: "two"))

            let lazyNode = makeNode(
                Text("LAZY")
                    .draggable(containerItemID: "row-3", containerNamespace: namespaceID)
            )
            XCTAssertEqual(lazyNode.dragContainerItemID, AnyHashable("row-3"))
            XCTAssertEqual(lazyNode.dragContainerNamespaceID, namespaceID.description)
            XCTAssertNotNil(lazyNode.onDragStart)
        }
    }

    func testOnDropRetainsProviderDestinationAndTargetBinding() async {
        await MainActor.run {
            var isTargeted = false
            var droppedCounts: [Int] = []
            var droppedLocations: [Point] = []
            let targetedBinding = Binding<Bool>(
                get: { isTargeted },
                set: { isTargeted = $0 }
            )
            let provider = NSItemProvider(object: "payload")
            provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier)

            let node = makeNode(
                Text("DROP")
                    .onDrop(of: [.plainText], isTargeted: targetedBinding) { providers, location in
                        droppedCounts.append(providers.count)
                        droppedLocations.append(location)
                        return true
                    }
            )

            XCTAssertTrue(node.isHitTestVisible)
            XCTAssertEqual(node.dropAcceptedContentTypes, [UTType.plainText.identifier])
            XCTAssertEqual(node.isDropDestinationEnabled, true)

            node.onDropEntered?([provider], Point(x: 1, y: 2))
            XCTAssertEqual(isTargeted, true)
            XCTAssertEqual(node.onDropProviders?([provider, "ignored"], Point(x: 3, y: 4)), true)
            node.onDropExited?()

            XCTAssertEqual(isTargeted, false)
            XCTAssertEqual(droppedCounts, [1])
            XCTAssertEqual(droppedLocations, [Point(x: 3, y: 4)])
        }
    }

    func testOnDropDelegateReceivesDropInfoLifecycle() async {
        await MainActor.run {
            final class DelegateBox {
                var events: [String] = []
            }

            struct ProbeDelegate: DropDelegate {
                let box: DelegateBox

                func validateDrop(info: DropInfo) -> Bool {
                    box.events.append("validate:\(info.hasItemsConforming(to: [.plainText]))")
                    return true
                }

                func dropEntered(info: DropInfo) {
                    box.events.append("entered:\(Int(info.location.x))")
                }

                func dropUpdated(info: DropInfo) -> DropProposal? {
                    box.events.append("updated:\(Int(info.location.y))")
                    return DropProposal(operation: .move)
                }

                func dropExited(info: DropInfo) {
                    box.events.append("exited")
                }

                func performDrop(info: DropInfo) -> Bool {
                    box.events.append("perform:\(info.itemProviders(for: [.plainText]).count)")
                    return true
                }
            }

            let box = DelegateBox()
            let provider = NSItemProvider(object: "payload")
            provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier)
            let node = makeNode(
                Text("DROP")
                    .onDrop(of: [.plainText], delegate: ProbeDelegate(box: box))
            )

            XCTAssertEqual(node.dropAcceptedContentTypes, [UTType.plainText.identifier])
            XCTAssertEqual(node.onValidateDrop?([provider], Point(x: 1, y: 2)), true)
            node.onDropEntered?([provider], Point(x: 3, y: 4))
            XCTAssertEqual((node.onDropUpdated?([provider], Point(x: 5, y: 6)) as? DropProposal)?.operation, .move)
            node.onDropExited?()
            XCTAssertEqual(node.onDropProviders?([provider], Point(x: 7, y: 8)), true)

            XCTAssertEqual(
                box.events,
                [
                    "validate:true",
                    "entered:3",
                    "updated:6",
                    "exited",
                    "perform:1",
                ]
            )
        }
    }

    func testDropDestinationRetainsTransferablePayloadHandlers() async {
        await MainActor.run {
            struct DropPayload: Transferable, Equatable {
                let value: String
            }

            var targetedValues: [Bool] = []
            var receivedPayloads: [[DropPayload]] = []
            var receivedLocations: [Point] = []
            let node = makeNode(
                Text("DROP")
                    .dropDestination(for: DropPayload.self) { payloads, location in
                        receivedPayloads.append(payloads)
                        receivedLocations.append(location)
                        return true
                    } isTargeted: { isTargeted in
                        targetedValues.append(isTargeted)
                    }
            )

            XCTAssertTrue(node.isHitTestVisible)
            XCTAssertEqual(node.dropPayloadType, String(reflecting: DropPayload.self))
            node.onDropEntered?([DropPayload(value: "one")], Point(x: 1, y: 2))
            XCTAssertEqual(node.onDropPayloads?([DropPayload(value: "one"), "ignored"], Point(x: 9, y: 10)), true)
            node.onDropExited?()

            XCTAssertEqual(targetedValues, [true, false])
            XCTAssertEqual(receivedPayloads, [[DropPayload(value: "one")]])
            XCTAssertEqual(receivedLocations, [Point(x: 9, y: 10)])
        }
    }

    func testModernDropDestinationRetainsSessionAndDisabledState() async {
        await MainActor.run {
            struct DropPayload: Transferable, Equatable {
                let value: String
            }

            var receivedPayloads: [[DropPayload]] = []
            var sessionLocations: [Point] = []
            let node = makeNode(
                Text("DROP")
                    .dropDestination(for: DropPayload.self, isEnabled: true) { payloads, session in
                        receivedPayloads.append(payloads)
                        sessionLocations.append(session.location)
                    }
            )

            XCTAssertEqual(node.dropPayloadType, String(reflecting: DropPayload.self))
            XCTAssertEqual(node.isDropDestinationEnabled, true)
            XCTAssertEqual(node.onDropPayloads?([DropPayload(value: "one")], Point(x: 4, y: 5)), true)
            XCTAssertEqual(receivedPayloads, [[DropPayload(value: "one")]])
            XCTAssertEqual(sessionLocations, [Point(x: 4, y: 5)])

            let disabledNode = makeNode(
                Text("DROP")
                    .dropDestination(for: DropPayload.self, isEnabled: false) { _, _ in
                        XCTFail("disabled drop destination should not run")
                    }
            )
            XCTAssertEqual(disabledNode.dropPayloadType, String(reflecting: DropPayload.self))
            XCTAssertEqual(disabledNode.isDropDestinationEnabled, false)
            XCTAssertNil(disabledNode.onDropPayloads)
        }
    }

    func testDropConfigurationRetainsSessionConfigurationFactory() async {
        await MainActor.run {
            var sessionLocations: [Point] = []
            var suggestedOperations: [Set<DropOperation>] = []
            let provider = NSItemProvider(object: "payload")
            let node = makeNode(
                Text("DROP")
                    .dropConfiguration { session in
                        sessionLocations.append(session.location)
                        suggestedOperations.append(session.suggestedOperations)
                        return DropConfiguration(operation: .move, acceptedItemCount: 1)
                    }
            )

            XCTAssertEqual(node.hasDropConfiguration, true)
            let configuration = node.onMakeDropConfiguration?([provider], Point(x: 12, y: 14)) as? DropConfiguration

            XCTAssertEqual(configuration, DropConfiguration(operation: .move, acceptedItemCount: 1))
            XCTAssertEqual(sessionLocations, [Point(x: 12, y: 14)])
            XCTAssertEqual(suggestedOperations, [[.copy]])
        }
    }

    func testDropPreviewFormationAndSpringLoadingRetainMetadata() async {
        await MainActor.run {
            let node = makeNode(
                Text("DROP")
                    .dropPreviewsFormation(.stack)
                    .springLoadingBehavior(.enabled)
            )

            XCTAssertEqual(node.dragDropPreviewsFormation, DragDropPreviewsFormation.stack.description)
            XCTAssertEqual(node.springLoadingBehavior, SpringLoadingBehavior.enabled.description)
        }
    }

    func testForEachBindingCollectionFeedsRetainedControls() async {
        await MainActor.run {
            struct Item: Identifiable {
                let id: Int
                var title: String
                var isEnabled: Bool
            }

            var items = [
                Item(id: 1, title: "FIRST", isEnabled: false),
                Item(id: 2, title: "SECOND", isEnabled: true),
            ]
            let itemsBinding = Binding(
                get: { items },
                set: { items = $0 }
            )

            let node = makeNode(
                VStack {
                    ForEach(itemsBinding) { item in
                        Toggle(item.wrappedValue.title, isOn: item.isEnabled)
                        TextField("TITLE", text: item.title)
                    }
                }
            )
            let controls = focusableNodes(in: node)

            controls[0].onActivate?()
            controls[3].onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertTrue(items[0].isEnabled)
            XCTAssertEqual(items[1].title, "SECONDz")
            XCTAssertEqual(node.children[0].nodeTag, "1#0")
            XCTAssertEqual(node.children[2].nodeTag, "2#0")
        }
    }

    func testForEachBindingCollectionSupportsExplicitIDKeyPath() async {
        await MainActor.run {
            struct Item {
                let key: String
                var title: String
            }

            var items = [
                Item(key: "alpha", title: "ALPHA"),
                Item(key: "beta", title: "BETA"),
            ]
            let itemsBinding = Binding(
                get: { items },
                set: { items = $0 }
            )

            let node = makeNode(
                VStack {
                    ForEach(itemsBinding, id: \.key) { item in
                        TextField("TITLE", text: item.title)
                    }
                }
            )

            firstFocusable(in: node)?.onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertEqual(items[0].title, "ALPHAz")
            XCTAssertEqual(node.children[0].nodeTag, "alpha#0")
            XCTAssertEqual(node.children[1].nodeTag, "beta#0")
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

    func testToggleImageAndSystemImageInitializersComposeLabel() async {
        await MainActor.run {
            let imageResource = ImageResource(name: "wifi", bundle: .main)
            let namedImageNode = makeNode(
                Toggle("AIRPLANE", image: "plane", isOn: .constant(false))
            )
            let resourceImageNode = makeNode(
                Toggle(LocalizedStringKey("HOTSPOT"), image: imageResource, isOn: .constant(true))
            )
            let systemImageNode = makeNode(
                Toggle("WIFI", systemImage: "wifi", isOn: .constant(true))
            )

            XCTAssertTrue(allTexts(in: namedImageNode).contains("AIRPLANE"))
            XCTAssertTrue(allTexts(in: resourceImageNode).contains("HOTSPOT"))
            XCTAssertTrue(allTexts(in: systemImageNode).contains("WIFI"))
            XCTAssertGreaterThanOrEqual(namedImageNode.children[0].children.count, 2)
            XCTAssertGreaterThanOrEqual(resourceImageNode.children[0].children.count, 2)
            XCTAssertGreaterThanOrEqual(systemImageNode.children[0].children.count, 2)
        }
    }

    func testToggleSourcesInitializerWritesAllSourceBindings() async {
        await MainActor.run {
            struct ToggleSource {
                var isOn: Binding<Bool>
            }

            var first = true
            var second = false
            var third = false
            var didInvalidate = false
            let sources = [
                ToggleSource(
                    isOn: Binding(
                        get: { first },
                        set: { first = $0 }
                    )
                ),
                ToggleSource(
                    isOn: Binding(
                        get: { second },
                        set: { second = $0 }
                    )
                ),
                ToggleSource(
                    isOn: Binding(
                        get: { third },
                        set: { third = $0 }
                    )
                ),
            ]

            let mixedNode = makeNode(
                Toggle("ALARMS", sources: sources, isOn: \.isOn),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(allTexts(in: mixedNode).contains("ALARMS"))

            firstFocusable(in: mixedNode)?.onActivate?()

            XCTAssertTrue(first)
            XCTAssertTrue(second)
            XCTAssertTrue(third)
            XCTAssertTrue(didInvalidate)

            let allOnNode = makeNode(
                Toggle(sources: sources, isOn: \.isOn) {
                    Label("ALL", systemImage: "bell")
                }
                .toggleStyle(ButtonToggleStyle())
            )

            XCTAssertTrue(allTexts(in: allOnNode).contains("ALL"))

            firstFocusable(in: allOnNode)?.onActivate?()

            XCTAssertFalse(first)
            XCTAssertFalse(second)
            XCTAssertFalse(third)
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
                .toggleStyle(CheckboxToggleStyle())
                .tint(tint),
                onInvalidate: {
                    didInvalidate = true
                }
            )
            let buttonNode = makeNode(
                Toggle("FILTER", isOn: .constant(true))
                    .toggleStyle(ButtonToggleStyle())
                    .tint(tint)
            )
            let switchNode = makeNode(
                Toggle("WIRELESS", isOn: .constant(false))
                    .toggleStyle(SwitchToggleStyle())
            )
            let defaultNode = makeNode(
                Toggle("DEFAULT", isOn: .constant(false))
                    .toggleStyle(DefaultToggleStyle())
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
            XCTAssertEqual(checkboxNode.children[0].cornerRadius, MacOSControlMetrics.Radius.sm)
            XCTAssertEqual(checkboxNode.children[0].backgroundColor, ControlPalette.opaque(tint))
            XCTAssertTrue(allTexts(in: checkboxNode).contains("ENABLED"))

            checkboxNode.onActivate?()

            XCTAssertFalse(checkboxValue)
            XCTAssertTrue(didInvalidate)
            XCTAssertEqual(buttonNode.backgroundColor, tint.opacity(0.82))
            XCTAssertTrue(buttonNode.isFocusable)
            XCTAssertEqual(switchNode.children.count, 2)
            XCTAssertEqual(defaultNode.children.count, 2)
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

    func testBindingDynamicMemberProjectionReadsWritesNestedValues() async {
        await MainActor.run {
            struct Settings {
                var isEnabled: Bool
                var title: String
            }

            var settings = Settings(isEnabled: false, title: "ALPHA")
            let settingsBinding = Binding(
                get: { settings },
                set: { settings = $0 }
            )

            XCTAssertFalse(settingsBinding.isEnabled.wrappedValue)
            XCTAssertEqual(settingsBinding.title.wrappedValue, "ALPHA")

            settingsBinding.isEnabled.wrappedValue = true
            settingsBinding.title.animation(.linear).wrappedValue = "BETA"

            XCTAssertTrue(settings.isEnabled)
            XCTAssertEqual(settings.title, "BETA")
        }
    }

    func testBindingDynamicMemberProjectionFeedsRetainedControls() async {
        await MainActor.run {
            struct Settings {
                var isEnabled: Bool
                var title: String
            }

            struct SettingsEditor: View {
                @Binding var settings: Settings

                var body: some View {
                    VStack {
                        Toggle("ENABLED", isOn: $settings.isEnabled)
                        TextField("TITLE", text: $settings.title.transaction(Transaction()))
                    }
                }
            }

            var settings = Settings(isEnabled: false, title: "ALPHA")
            let node = makeNode(
                SettingsEditor(
                    settings: Binding(
                        get: { settings },
                        set: { settings = $0 }
                    )
                )
            )

            firstFocusable(in: node)?.onActivate?()
            let textInput = focusableNodes(in: node).last
            textInput?.onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertTrue(settings.isEnabled)
            XCTAssertEqual(settings.title, "ALPHAz")
        }
    }

    func testBindingCollectionSubscriptReadsWritesElements() async {
        await MainActor.run {
            struct Settings {
                var isEnabled: Bool
                var title: String
            }

            var settings = [
                Settings(isEnabled: false, title: "ALPHA"),
                Settings(isEnabled: true, title: "BETA"),
            ]
            let settingsBinding = Binding(
                get: { settings },
                set: { settings = $0 }
            )

            XCTAssertEqual(settingsBinding[1].title.wrappedValue, "BETA")

            settingsBinding[0].isEnabled.wrappedValue = true
            settingsBinding[1].title.wrappedValue = "GAMMA"

            XCTAssertTrue(settings[0].isEnabled)
            XCTAssertEqual(settings[1].title, "GAMMA")
        }
    }

    func testBindingCollectionSubscriptFeedsRetainedControls() async {
        await MainActor.run {
            struct Settings {
                var isEnabled: Bool
                var title: String
            }

            var settings = [
                Settings(isEnabled: false, title: "ALPHA"),
                Settings(isEnabled: true, title: "BETA"),
            ]
            let settingsBinding = Binding(
                get: { settings },
                set: { settings = $0 }
            )

            let node = makeNode(
                VStack {
                    Toggle("FIRST", isOn: settingsBinding[0].isEnabled)
                    TextField("SECOND", text: settingsBinding[1].title)
                }
            )
            let controls = focusableNodes(in: node)

            controls.first?.onActivate?()
            controls.last?.onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertTrue(settings[0].isEnabled)
            XCTAssertEqual(settings[1].title, "BETAz")
        }
    }

    func testBindingOptionalPromotionReadsAndWritesNonNilValues() async {
        await MainActor.run {
            var title = "ALPHA"
            let titleBinding = Binding(
                get: { title },
                set: { title = $0 }
            )

            let optionalBinding = Binding<String?>(titleBinding)

            XCTAssertEqual(optionalBinding.wrappedValue, "ALPHA")

            optionalBinding.wrappedValue = "BETA"
            XCTAssertEqual(title, "BETA")

            optionalBinding.wrappedValue = nil
            XCTAssertEqual(title, "BETA")
        }
    }

    func testBindingOptionalUnwrapFeedsRetainedControlsWhenValueExists() async {
        await MainActor.run {
            var title: String? = "ALPHA"
            let optionalTitle = Binding<String?>(
                get: { title },
                set: { title = $0 }
            )

            guard let titleBinding = Binding<String>(optionalTitle) else {
                XCTFail("Expected a binding when the optional has a value")
                return
            }

            let node = makeNode(TextField("TITLE", text: titleBinding))
            firstFocusable(in: node)?.onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertEqual(title, "ALPHAz")

            title = nil
            XCTAssertEqual(Binding<String>(optionalTitle)?.wrappedValue, nil)
            XCTAssertEqual(titleBinding.wrappedValue, "ALPHA")
        }
    }

    func testDynamicPropertyProtocolAcceptsWinSwiftUIWrappers() async {
        await MainActor.run {
            final class DynamicModel: ObservableObject {
                @Published var value = 0
            }

            @MainActor
            func acceptDynamicProperty<Property: DynamicProperty>(_ property: Property) {
                var property = property
                property.update()
            }

            let model = DynamicModel()
            let suiteName = "WinSwiftUITests.DynamicProperty.\(UUID().uuidString)"
            guard let store = UserDefaults(suiteName: suiteName) else {
                return XCTFail("Expected test UserDefaults suite")
            }
            defer {
                store.removePersistentDomain(forName: suiteName)
            }

            acceptDynamicProperty(ObservedObject(wrappedValue: model))
            acceptDynamicProperty(Environment(\.colorScheme))
            acceptDynamicProperty(EnvironmentObject<DynamicModel>())
            acceptDynamicProperty(FocusedValue(\.testFocusedLabel))
            acceptDynamicProperty(FocusedBinding(\.testFocusedBinding))
            acceptDynamicProperty(FocusedObject<DynamicModel>())
            acceptDynamicProperty(StateObject(wrappedValue: model))
            acceptDynamicProperty(Binding.constant(1))
            acceptDynamicProperty(State(wrappedValue: 1))
            acceptDynamicProperty(AppStorage(wrappedValue: 1, "count", store: store))
            acceptDynamicProperty(SceneStorage(wrappedValue: "value", "dynamicProperty"))
            acceptDynamicProperty(ScaledMetric(wrappedValue: 1.0))
            acceptDynamicProperty(FocusState<Bool>())
            acceptDynamicProperty(GestureState(wrappedValue: false))
            acceptDynamicProperty(Namespace())
        }
    }

    func testAppStorageReadsWritesUserDefaultsAndProvidesBinding() async {
        await MainActor.run {
            struct AppStorageReaderView: View {
                @AppStorage private var flag: Bool
                @AppStorage private var title: String

                init(store: UserDefaults) {
                    _flag = AppStorage(wrappedValue: false, "flag", store: store)
                    _title = AppStorage(wrappedValue: "DEFAULT", "title", store: store)
                }

                var body: some View {
                    VStack {
                        Button(flag ? "ON" : "OFF") {
                            flag.toggle()
                        }
                        TextField("TITLE", text: $title)
                    }
                }
            }

            let suiteName = "WinSwiftUITests.AppStorage.\(UUID().uuidString)"
            guard let store = UserDefaults(suiteName: suiteName) else {
                return XCTFail("Expected test UserDefaults suite")
            }
            defer {
                store.removePersistentDomain(forName: suiteName)
            }

            store.set(true, forKey: "flag")
            store.set("STORED", forKey: "title")

            let node = makeNode(AppStorageReaderView(store: store))

            XCTAssertTrue(allTexts(in: node).contains("ON"))
            XCTAssertTrue(allTexts(in: node).contains("STORED"))

            node.children[0].onActivate?()

            XCTAssertFalse(store.bool(forKey: "flag"))
        }
    }

    func testDefaultAppStorageProvidesStoreForAppStorageAndEnvironmentReads() async {
        await MainActor.run {
            struct DefaultStoreAppStorageView: View {
                @Environment(\.defaultAppStorage) private var defaultStore
                @AppStorage private var title: String

                init() {
                    _title = AppStorage(wrappedValue: "DEFAULT", "title")
                }

                var body: some View {
                    VStack {
                        Text(defaultStore.string(forKey: "environmentTitle") ?? "NO ENV")
                        Button(title) {
                            title = "WRITTEN"
                        }
                    }
                }
            }

            struct ExplicitStoreAppStorageView: View {
                @AppStorage private var title: String

                init(store: UserDefaults) {
                    _title = AppStorage(wrappedValue: "DEFAULT", "title", store: store)
                }

                var body: some View {
                    Button(title) {
                        title = "EXPLICIT WRITTEN"
                    }
                }
            }

            let defaultSuiteName = "WinSwiftUITests.DefaultAppStorage.\(UUID().uuidString)"
            let explicitSuiteName = "WinSwiftUITests.DefaultAppStorageExplicit.\(UUID().uuidString)"
            guard let defaultStore = UserDefaults(suiteName: defaultSuiteName),
                let explicitStore = UserDefaults(suiteName: explicitSuiteName)
            else {
                return XCTFail("Expected test UserDefaults suites")
            }
            defer {
                defaultStore.removePersistentDomain(forName: defaultSuiteName)
                explicitStore.removePersistentDomain(forName: explicitSuiteName)
            }

            defaultStore.set("ENVIRONMENT", forKey: "environmentTitle")
            defaultStore.set("INHERITED", forKey: "title")
            explicitStore.set("EXPLICIT", forKey: "title")

            let inheritedNode = makeNode(DefaultStoreAppStorageView().defaultAppStorage(defaultStore))

            XCTAssertTrue(allTexts(in: inheritedNode).contains("ENVIRONMENT"))
            XCTAssertTrue(allTexts(in: inheritedNode).contains("INHERITED"))

            firstFocusable(in: inheritedNode)?.onActivate?()

            XCTAssertEqual(defaultStore.string(forKey: "title"), "WRITTEN")
            XCTAssertEqual(explicitStore.string(forKey: "title"), "EXPLICIT")

            let explicitNode = makeNode(
                ExplicitStoreAppStorageView(store: explicitStore)
                    .defaultAppStorage(defaultStore)
            )

            XCTAssertTrue(allTexts(in: explicitNode).contains("EXPLICIT"))

            explicitNode.onActivate?()

            XCTAssertEqual(explicitStore.string(forKey: "title"), "EXPLICIT WRITTEN")
            XCTAssertEqual(defaultStore.string(forKey: "title"), "WRITTEN")
        }
    }

    func testAppStorageWriteTriggersInvalidation() async {
        await MainActor.run {
            struct AppStorageWriterView: View {
                @AppStorage private var count: Int

                init(store: UserDefaults) {
                    _count = AppStorage(wrappedValue: 0, "count", store: store)
                }

                var body: some View {
                    Text("\(count)")
                }

                func increment() {
                    count += 1
                }
            }

            let suiteName = "WinSwiftUITests.AppStorageInvalidation.\(UUID().uuidString)"
            guard let store = UserDefaults(suiteName: suiteName) else {
                return XCTFail("Expected test UserDefaults suite")
            }
            defer {
                store.removePersistentDomain(forName: suiteName)
            }

            var invalidationCount = 0
            let view = AppStorageWriterView(store: store)
            let node = makeNode(
                view,
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertEqual(firstText(in: node), "0")
            view.increment()

            XCTAssertEqual(store.integer(forKey: "count"), 1)
            XCTAssertEqual(invalidationCount, 1)
        }
    }

    func testAppStorageStringRawRepresentableReadsWritesUserDefaultsAndProvidesBinding() async {
        await MainActor.run {
            enum DisplayMode: String {
                case compact
                case expanded
            }

            struct AppStorageEnumView: View {
                @AppStorage private var mode: DisplayMode

                init(store: UserDefaults) {
                    _mode = AppStorage(wrappedValue: .compact, "mode", store: store)
                }

                var body: some View {
                    Button(mode == .expanded ? "EXPANDED" : "COMPACT") {
                        mode = .expanded
                    }
                }
            }

            let suiteName = "WinSwiftUITests.AppStorageRawString.\(UUID().uuidString)"
            guard let store = UserDefaults(suiteName: suiteName) else {
                return XCTFail("Expected test UserDefaults suite")
            }
            defer {
                store.removePersistentDomain(forName: suiteName)
            }

            store.set("expanded", forKey: "mode")
            let expandedNode = makeNode(AppStorageEnumView(store: store))

            XCTAssertTrue(allTexts(in: expandedNode).contains("EXPANDED"))

            store.set("unknown", forKey: "mode")
            let defaultNode = makeNode(AppStorageEnumView(store: store))

            XCTAssertTrue(allTexts(in: defaultNode).contains("COMPACT"))

            defaultNode.onActivate?()

            XCTAssertEqual(store.string(forKey: "mode"), "expanded")
        }
    }

    func testAppStorageIntRawRepresentableFeedsRetainedControls() async {
        await MainActor.run {
            enum Level: Int {
                case low = 1
                case high = 2
            }

            struct AppStorageIntEnumView: View {
                @AppStorage private var level: Level

                init(store: UserDefaults) {
                    _level = AppStorage(wrappedValue: .low, "level", store: store)
                }

                var body: some View {
                    VStack {
                        Toggle(
                            "HIGH",
                            isOn: Binding(
                                get: { level == .high },
                                set: { level = $0 ? .high : .low }
                            ))
                        Text(level == .high ? "HIGH VALUE" : "LOW VALUE")
                    }
                }
            }

            let suiteName = "WinSwiftUITests.AppStorageRawInt.\(UUID().uuidString)"
            guard let store = UserDefaults(suiteName: suiteName) else {
                return XCTFail("Expected test UserDefaults suite")
            }
            defer {
                store.removePersistentDomain(forName: suiteName)
            }

            store.set(1, forKey: "level")
            let node = makeNode(AppStorageIntEnumView(store: store))

            firstFocusable(in: node)?.onActivate?()

            XCTAssertEqual(store.integer(forKey: "level"), 2)

            store.set(99, forKey: "level")
            let fallbackNode = makeNode(AppStorageIntEnumView(store: store))

            XCTAssertTrue(allTexts(in: fallbackNode).contains("LOW VALUE"))
        }
    }

    func testAppStorageOptionalValuesReadWriteAndRemoveUserDefaults() async {
        await MainActor.run {
            struct AppStorageOptionalView: View {
                @AppStorage private var title: String?

                init(store: UserDefaults) {
                    _title = AppStorage("title", store: store)
                }

                var body: some View {
                    Button(title ?? "MISSING") {
                        title = title == nil ? "STORED" : nil
                    }
                }
            }

            let suiteName = "WinSwiftUITests.AppStorageOptional.\(UUID().uuidString)"
            guard let store = UserDefaults(suiteName: suiteName) else {
                return XCTFail("Expected test UserDefaults suite")
            }
            defer {
                store.removePersistentDomain(forName: suiteName)
            }

            let optionalFlag = AppStorage<Bool?>("flag", store: store)
            let optionalCount = AppStorage<Int?>("count", store: store)
            let optionalScale = AppStorage<Double?>("scale", store: store)
            let optionalData = AppStorage<Data?>("data", store: store)
            let optionalURL = AppStorage<URL?>("url", store: store)
            let appURL = URL(string: "https://example.com/app")!

            XCTAssertNil(optionalFlag.wrappedValue)
            XCTAssertNil(optionalCount.wrappedValue)
            XCTAssertNil(optionalScale.wrappedValue)
            XCTAssertNil(optionalData.wrappedValue)
            XCTAssertNil(optionalURL.wrappedValue)

            optionalFlag.wrappedValue = true
            optionalCount.wrappedValue = 7
            optionalScale.wrappedValue = 1.5
            optionalData.wrappedValue = Data([1, 2, 3])
            optionalURL.wrappedValue = appURL

            XCTAssertEqual(store.bool(forKey: "flag"), true)
            XCTAssertEqual(store.integer(forKey: "count"), 7)
            XCTAssertEqual(store.double(forKey: "scale"), 1.5)
            XCTAssertEqual(store.data(forKey: "data"), Data([1, 2, 3]))
            XCTAssertEqual(store.string(forKey: "url"), appURL.absoluteString)
            XCTAssertEqual(optionalURL.wrappedValue, appURL)

            optionalFlag.wrappedValue = nil
            optionalCount.wrappedValue = nil
            optionalScale.wrappedValue = nil
            optionalData.wrappedValue = nil
            optionalURL.wrappedValue = nil

            XCTAssertNil(store.object(forKey: "flag"))
            XCTAssertNil(store.object(forKey: "count"))
            XCTAssertNil(store.object(forKey: "scale"))
            XCTAssertNil(store.object(forKey: "data"))
            XCTAssertNil(store.object(forKey: "url"))

            store.set("READY", forKey: "title")
            let readyNode = makeNode(AppStorageOptionalView(store: store))
            XCTAssertTrue(allTexts(in: readyNode).contains("READY"))

            readyNode.onActivate?()
            XCTAssertNil(store.object(forKey: "title"))

            let missingNode = makeNode(AppStorageOptionalView(store: store))
            XCTAssertTrue(allTexts(in: missingNode).contains("MISSING"))

            missingNode.onActivate?()
            XCTAssertEqual(store.string(forKey: "title"), "STORED")
        }
    }

    func testAppStorageOptionalRawRepresentableReadsWritesAndRemovesUserDefaults() async {
        await MainActor.run {
            enum Mode: String {
                case compact
                case expanded
            }

            enum Level: Int {
                case low = 1
                case high = 2
            }

            struct AppStorageOptionalEnumView: View {
                @AppStorage private var mode: Mode?

                init(store: UserDefaults) {
                    _mode = AppStorage("mode", store: store)
                }

                var body: some View {
                    Button(mode == .expanded ? "EXPANDED" : "NONE") {
                        mode = mode == nil ? .expanded : nil
                    }
                }
            }

            let suiteName = "WinSwiftUITests.AppStorageOptionalRaw.\(UUID().uuidString)"
            guard let store = UserDefaults(suiteName: suiteName) else {
                return XCTFail("Expected test UserDefaults suite")
            }
            defer {
                store.removePersistentDomain(forName: suiteName)
            }

            let optionalMode = AppStorage<Mode?>("mode", store: store)
            let optionalLevel = AppStorage<Level?>(wrappedValue: .low, "level", store: store)

            XCTAssertNil(optionalMode.wrappedValue)
            XCTAssertEqual(optionalLevel.wrappedValue, .low)

            store.set("expanded", forKey: "mode")
            store.set(2, forKey: "level")

            XCTAssertEqual(optionalMode.wrappedValue, .expanded)
            XCTAssertEqual(optionalLevel.wrappedValue, .high)

            store.set("unknown", forKey: "mode")
            store.set(99, forKey: "level")

            XCTAssertNil(optionalMode.wrappedValue)
            XCTAssertEqual(optionalLevel.wrappedValue, .low)

            optionalMode.wrappedValue = .compact
            optionalLevel.wrappedValue = .high

            XCTAssertEqual(store.string(forKey: "mode"), "compact")
            XCTAssertEqual(store.integer(forKey: "level"), 2)

            optionalMode.wrappedValue = nil
            optionalLevel.wrappedValue = nil

            XCTAssertNil(store.object(forKey: "mode"))
            XCTAssertNil(store.object(forKey: "level"))

            let emptyNode = makeNode(AppStorageOptionalEnumView(store: store))
            XCTAssertTrue(allTexts(in: emptyNode).contains("NONE"))

            emptyNode.onActivate?()
            XCTAssertEqual(store.string(forKey: "mode"), "expanded")

            let expandedNode = makeNode(AppStorageOptionalEnumView(store: store))
            XCTAssertTrue(allTexts(in: expandedNode).contains("EXPANDED"))

            expandedNode.onActivate?()
            XCTAssertNil(store.object(forKey: "mode"))
        }
    }

    func testSceneStoragePersistsValuesAcrossViewInstancesAndProvidesBinding() async {
        await MainActor.run {
            struct SceneStorageReaderView: View {
                @SceneStorage private var title: String

                init(key: String) {
                    _title = SceneStorage(wrappedValue: "", key)
                }

                var body: some View {
                    TextField("TITLE", text: $title)
                }
            }

            let key = "WinSwiftUITests.SceneStorage.\(UUID().uuidString)"
            let firstNode = makeNode(SceneStorageReaderView(key: key))
            XCTAssertTrue(allTexts(in: firstNode).contains("TITLE"))

            firstNode.onKeyDown?(KeyboardEvent(keyCode: 0x41))

            let secondNode = makeNode(SceneStorageReaderView(key: key))
            XCTAssertTrue(allTexts(in: secondNode).contains("a"))
        }
    }

    func testSceneStorageWriteTriggersInvalidation() async {
        await MainActor.run {
            struct SceneStorageWriterView: View {
                @SceneStorage private var count: Int

                init(key: String) {
                    _count = SceneStorage(wrappedValue: 0, key)
                }

                var body: some View {
                    Text("\(count)")
                }

                func increment() {
                    count += 1
                }
            }

            var invalidationCount = 0
            let key = "WinSwiftUITests.SceneStorageInvalidation.\(UUID().uuidString)"
            let view = SceneStorageWriterView(key: key)
            let node = makeNode(
                view,
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertEqual(firstText(in: node), "0")
            view.increment()

            XCTAssertEqual(firstText(in: makeNode(SceneStorageWriterView(key: key))), "1")
            XCTAssertEqual(invalidationCount, 1)
        }
    }

    func testSceneStorageStringRawRepresentablePersistsRawValues() async {
        await MainActor.run {
            enum Mode: String {
                case compact
                case expanded
            }

            struct SceneStorageEnumView: View {
                @SceneStorage private var mode: Mode

                init(key: String) {
                    _mode = SceneStorage(wrappedValue: .compact, key)
                }

                var body: some View {
                    Button(mode == .expanded ? "EXPANDED" : "COMPACT") {
                        mode = .expanded
                    }
                }
            }

            let key = "WinSwiftUITests.SceneStorageRawString.\(UUID().uuidString)"
            let rawStorage = SceneStorage(wrappedValue: "", key)

            rawStorage.wrappedValue = "expanded"
            let expandedNode = makeNode(SceneStorageEnumView(key: key))

            XCTAssertTrue(allTexts(in: expandedNode).contains("EXPANDED"))

            rawStorage.wrappedValue = "unknown"
            let defaultNode = makeNode(SceneStorageEnumView(key: key))

            XCTAssertTrue(allTexts(in: defaultNode).contains("COMPACT"))

            defaultNode.onActivate?()

            XCTAssertEqual(rawStorage.wrappedValue, "expanded")
        }
    }

    func testSceneStorageIntRawRepresentableFeedsRetainedControls() async {
        await MainActor.run {
            enum Level: Int {
                case low = 1
                case high = 2
            }

            struct SceneStorageIntEnumView: View {
                @SceneStorage private var level: Level

                init(key: String) {
                    _level = SceneStorage(wrappedValue: .low, key)
                }

                var body: some View {
                    VStack {
                        Toggle(
                            "HIGH",
                            isOn: Binding(
                                get: { level == .high },
                                set: { level = $0 ? .high : .low }
                            ))
                        Text(level == .high ? "HIGH VALUE" : "LOW VALUE")
                    }
                }
            }

            let key = "WinSwiftUITests.SceneStorageRawInt.\(UUID().uuidString)"
            let rawStorage = SceneStorage(wrappedValue: 1, key)

            rawStorage.wrappedValue = 1
            let node = makeNode(SceneStorageIntEnumView(key: key))

            firstFocusable(in: node)?.onActivate?()

            XCTAssertEqual(rawStorage.wrappedValue, 2)

            rawStorage.wrappedValue = 99
            let fallbackNode = makeNode(SceneStorageIntEnumView(key: key))

            XCTAssertTrue(allTexts(in: fallbackNode).contains("LOW VALUE"))
        }
    }

    func testSceneStorageOptionalValuesReadWriteAndRemoveRetainedState() async {
        await MainActor.run {
            struct SceneStorageOptionalView: View {
                @SceneStorage private var count: Int?

                init(key: String) {
                    _count = SceneStorage(key)
                }

                var body: some View {
                    Button(count.map { "\($0)" } ?? "EMPTY") {
                        count = count == nil ? 5 : nil
                    }
                }
            }

            let keyPrefix = "WinSwiftUITests.SceneStorageOptional.\(UUID().uuidString)"
            let optionalFlag = SceneStorage<Bool?>("\(keyPrefix).flag")
            let optionalCount = SceneStorage<Int?>("\(keyPrefix).count")
            let optionalScale = SceneStorage<Double?>("\(keyPrefix).scale")
            let optionalTitle = SceneStorage<String?>("\(keyPrefix).title")
            let optionalData = SceneStorage<Data?>("\(keyPrefix).data")
            let optionalURL = SceneStorage<URL?>("\(keyPrefix).url")

            XCTAssertNil(optionalFlag.wrappedValue)
            XCTAssertNil(optionalCount.wrappedValue)
            XCTAssertNil(optionalScale.wrappedValue)
            XCTAssertNil(optionalTitle.wrappedValue)
            XCTAssertNil(optionalData.wrappedValue)
            XCTAssertNil(optionalURL.wrappedValue)

            optionalFlag.wrappedValue = true
            optionalCount.wrappedValue = 7
            optionalScale.wrappedValue = 1.5
            optionalTitle.wrappedValue = "READY"
            optionalData.wrappedValue = Data([1, 2, 3])
            optionalURL.wrappedValue = URL(string: "https://example.com/scene")

            XCTAssertEqual(SceneStorage<Bool?>("\(keyPrefix).flag").wrappedValue, true)
            XCTAssertEqual(SceneStorage<Int?>("\(keyPrefix).count").wrappedValue, 7)
            XCTAssertEqual(SceneStorage<Double?>("\(keyPrefix).scale").wrappedValue, 1.5)
            XCTAssertEqual(SceneStorage<String?>("\(keyPrefix).title").wrappedValue, "READY")
            XCTAssertEqual(SceneStorage<Data?>("\(keyPrefix).data").wrappedValue, Data([1, 2, 3]))
            XCTAssertEqual(
                SceneStorage<URL?>("\(keyPrefix).url").wrappedValue, URL(string: "https://example.com/scene"))

            optionalFlag.wrappedValue = nil
            optionalCount.wrappedValue = nil
            optionalScale.wrappedValue = nil
            optionalTitle.wrappedValue = nil
            optionalData.wrappedValue = nil
            optionalURL.wrappedValue = nil

            XCTAssertNil(SceneStorage<Bool?>("\(keyPrefix).flag").wrappedValue)
            XCTAssertNil(SceneStorage<Int?>("\(keyPrefix).count").wrappedValue)
            XCTAssertNil(SceneStorage<Double?>("\(keyPrefix).scale").wrappedValue)
            XCTAssertNil(SceneStorage<String?>("\(keyPrefix).title").wrappedValue)
            XCTAssertNil(SceneStorage<Data?>("\(keyPrefix).data").wrappedValue)
            XCTAssertNil(SceneStorage<URL?>("\(keyPrefix).url").wrappedValue)

            let countKey = "\(keyPrefix).buttonCount"
            let emptyNode = makeNode(SceneStorageOptionalView(key: countKey))
            XCTAssertTrue(allTexts(in: emptyNode).contains("EMPTY"))

            emptyNode.onActivate?()
            let filledNode = makeNode(SceneStorageOptionalView(key: countKey))
            XCTAssertTrue(allTexts(in: filledNode).contains("5"))

            filledNode.onActivate?()
            let removedNode = makeNode(SceneStorageOptionalView(key: countKey))
            XCTAssertTrue(allTexts(in: removedNode).contains("EMPTY"))
        }
    }

    func testSceneStorageOptionalRawRepresentableReadsWritesAndRemovesRetainedState() async {
        await MainActor.run {
            enum Mode: String {
                case compact
                case expanded
            }

            enum Level: Int {
                case low = 1
                case high = 2
            }

            struct SceneStorageOptionalEnumView: View {
                @SceneStorage private var mode: Mode?

                init(key: String) {
                    _mode = SceneStorage(key)
                }

                var body: some View {
                    Button(mode == .expanded ? "EXPANDED" : "NONE") {
                        mode = mode == nil ? .expanded : nil
                    }
                }
            }

            let keyPrefix = "WinSwiftUITests.SceneStorageOptionalRaw.\(UUID().uuidString)"
            let modeKey = "\(keyPrefix).mode"
            let levelKey = "\(keyPrefix).level"
            let optionalMode = SceneStorage<Mode?>(modeKey)
            let optionalLevel = SceneStorage<Level?>(wrappedValue: .low, levelKey)
            let rawMode = SceneStorage<String?>(modeKey)
            let rawLevel = SceneStorage<Int?>(levelKey)

            XCTAssertNil(optionalMode.wrappedValue)
            XCTAssertEqual(optionalLevel.wrappedValue, .low)

            rawMode.wrappedValue = "expanded"
            rawLevel.wrappedValue = 2

            XCTAssertEqual(optionalMode.wrappedValue, .expanded)
            XCTAssertEqual(optionalLevel.wrappedValue, .high)

            rawMode.wrappedValue = "unknown"
            rawLevel.wrappedValue = 99

            XCTAssertNil(optionalMode.wrappedValue)
            XCTAssertEqual(optionalLevel.wrappedValue, .low)

            optionalMode.wrappedValue = .compact
            optionalLevel.wrappedValue = .high

            XCTAssertEqual(rawMode.wrappedValue, "compact")
            XCTAssertEqual(rawLevel.wrappedValue, 2)

            optionalMode.wrappedValue = nil
            optionalLevel.wrappedValue = nil

            XCTAssertNil(rawMode.wrappedValue)
            XCTAssertNil(rawLevel.wrappedValue)

            let emptyNode = makeNode(SceneStorageOptionalEnumView(key: modeKey))
            XCTAssertTrue(allTexts(in: emptyNode).contains("NONE"))

            emptyNode.onActivate?()
            XCTAssertEqual(rawMode.wrappedValue, "expanded")

            let expandedNode = makeNode(SceneStorageOptionalEnumView(key: modeKey))
            XCTAssertTrue(allTexts(in: expandedNode).contains("EXPANDED"))

            expandedNode.onActivate?()
            XCTAssertNil(rawMode.wrappedValue)
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

    func testPickerCurrentValueLabelInitializerComposesHeaderAndKeepsSelectionBehavior() async {
        await MainActor.run {
            var selection = "compact"
            var didInvalidate = false

            let node = makeNode(
                Picker(
                    selection: Binding(
                        get: { selection },
                        set: { selection = $0 }
                    )
                ) {
                    Text("COMPACT").tag("compact")
                    Text("EXPANDED").tag("expanded")
                } label: {
                    Text("MODE")
                } currentValueLabel: {
                    Text("COMPACT")
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(firstText(in: node.children[0].children[0]), "MODE")
            XCTAssertEqual(firstText(in: node.children[0].children[1]), "COMPACT")
            XCTAssertTrue(allTexts(in: node.children[1].children[0]).contains("COMPACT"))

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

    func testPickerStyleSupportingTypesMapToRetainedPickerChrome() async {
        await MainActor.run {
            var selection = "compact"
            let binding = Binding(
                get: { selection },
                set: { selection = $0 }
            )

            @MainActor
            func picker() -> Picker<String> {
                Picker("MODE", selection: binding) {
                    Text("COMPACT").tag("compact")
                    Text("EXPANDED").tag("expanded")
                }
            }

            let inlineNode = makeNode(VStack { picker().pickerStyle(InlinePickerStyle()) })
            let wheelNode = makeNode(VStack { picker().pickerStyle(.wheel) })
            let paletteNode = makeNode(VStack { picker().pickerStyle(PalettePickerStyle()) })
            let radioNode = makeNode(VStack { picker().pickerStyle(RadioGroupPickerStyle()) })
            let navigationNode = makeNode(VStack { picker().pickerStyle(NavigationLinkPickerStyle()) })
            let menuNode = makeNode(VStack { picker().pickerStyle(MenuPickerStyle()) })

            XCTAssertEqual(
                allTexts(in: inlineNode.children[0].children[1]),
                [SymbolIcon.checkmark.rawValue, "COMPACT", "EXPANDED"])
            XCTAssertEqual(inlineNode.children[0].children[1].cornerRadius, 10)
            XCTAssertEqual(allTexts(in: wheelNode.children[0].children[1]), ["COMPACT", "EXPANDED"])
            XCTAssertEqual(allTexts(in: paletteNode.children[0].children[1]), ["COMPACT", "EXPANDED"])
            XCTAssertEqual(allTexts(in: radioNode.children[0].children[1]), ["COMPACT", "EXPANDED"])
            XCTAssertEqual(firstText(in: navigationNode.children[0].children[1].children[0]), "COMPACT")
            XCTAssertEqual(navigationNode.children[0].children[1].cornerRadius, 10)
            XCTAssertEqual(firstText(in: menuNode.children[0].children[1].children[0]), "COMPACT")
        }
    }

    func testPickerStyleInlineUsesRetainedInlineRowsAndWritesSelection() async {
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
                    Text("EXPANDED").tag("expanded")
                }
                .pickerStyle(.inline),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            let inlineNode = node.children[1]
            XCTAssertEqual(inlineNode.children.count, 2)
            XCTAssertEqual(inlineNode.borderWidth, 1)
            XCTAssertEqual(inlineNode.cornerRadius, 10)
            XCTAssertEqual(allTexts(in: inlineNode), [SymbolIcon.checkmark.rawValue, "COMPACT", "EXPANDED"])
            XCTAssertEqual(inlineNode.children[0].borderWidth, 1)
            XCTAssertEqual(inlineNode.children[1].borderWidth, 0)

            inlineNode.children[1].onActivate?()

            XCTAssertEqual(selection, "expanded")
            XCTAssertTrue(didInvalidate)
        }
    }

    func testPickerStyleNavigationLinkUsesRetainedDisclosureRowAndWritesSelection() async {
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
                    Text("EXPANDED").tag("expanded")
                }
                .pickerStyle(.navigationLink),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            let navigationNode = node.children[1]
            XCTAssertEqual(navigationNode.children.count, 2)
            XCTAssertEqual(navigationNode.borderWidth, 1)
            XCTAssertEqual(navigationNode.cornerRadius, 10)
            XCTAssertEqual(
                navigationNode.preferredSize,
                Size(width: 224, height: ControlSize.regular.pickerMenuPreferredSize.height + 4))
            XCTAssertEqual(firstText(in: navigationNode.children[0]), "COMPACT")
            XCTAssertTrue(navigationNode.children[1].isHidden)

            navigationNode.onActivate?()
            XCTAssertFalse(navigationNode.children[1].isHidden)
            navigationNode.children[1].children[1].onActivate?()

            XCTAssertEqual(selection, "expanded")
            XCTAssertTrue(didInvalidate)
        }
    }

    func testPickerStyleRadioGroupUsesRetainedRadioButtonsAndWritesSelection() async {
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
                    Text("EXPANDED").tag("expanded")
                }
                .pickerStyle(.radioGroup),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            let radioGroupNode = node.children[1]
            XCTAssertEqual(radioGroupNode.children.count, 2)
            XCTAssertEqual(allTexts(in: radioGroupNode), ["COMPACT", "EXPANDED"])
            XCTAssertEqual(radioGroupNode.children[0].children[0].children.count, 1)
            XCTAssertTrue(radioGroupNode.children[1].children[0].children.isEmpty)

            radioGroupNode.children[1].onActivate?()

            XCTAssertEqual(selection, "expanded")
            XCTAssertTrue(didInvalidate)
        }
    }

    func testPickerStyleWheelUsesRetainedWheelRowsAndDefaultItemHeight() async {
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
                    Text("EXPANDED").tag("expanded")
                }
                .pickerStyle(.wheel)
                .defaultWheelPickerItemHeight(44),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            let wheelNode = node.children[1]
            XCTAssertEqual(wheelNode.children.count, 2)
            XCTAssertEqual(allTexts(in: wheelNode), ["COMPACT", "EXPANDED"])
            XCTAssertEqual(wheelNode.children[0].layoutConstraints?.minHeight, 44)
            XCTAssertEqual(wheelNode.children[1].layoutConstraints?.minHeight, 44)
            XCTAssertNotNil(wheelNode.children[0].backgroundColor)
            XCTAssertEqual(wheelNode.children[0].borderWidth, 1)
            XCTAssertEqual(wheelNode.children[1].borderWidth, 0)

            wheelNode.children[1].onActivate?()

            XCTAssertEqual(selection, "expanded")
            XCTAssertTrue(didInvalidate)
        }
    }

    func testPickerStylePaletteUsesCompactRetainedButtonsAndWritesSelection() async {
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
                    Text("EXPANDED").tag("expanded")
                }
                .pickerStyle(.palette)
                .controlSize(.large),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            let paletteNode = node.children[1]
            XCTAssertEqual(paletteNode.children.count, 2)
            XCTAssertEqual(allTexts(in: paletteNode), ["COMPACT", "EXPANDED"])
            // Palette swatches derive from the pop-up button height, which
            // is now the macOS reference plus the Windows pointer delta.
            let paletteItemHeight = ControlSize.large.pickerMenuPreferredSize.height
            let paletteItemWidth = max(44, paletteItemHeight * 1.45)
            XCTAssertEqual(paletteNode.children[0].preferredSize?.height, paletteItemHeight)
            XCTAssertEqual(paletteNode.children[1].preferredSize?.height, paletteItemHeight)
            XCTAssertEqual(paletteNode.children[0].preferredSize?.width ?? 0, paletteItemWidth, accuracy: 0.001)
            XCTAssertEqual(paletteNode.children[1].preferredSize?.width ?? 0, paletteItemWidth, accuracy: 0.001)
            XCTAssertEqual(paletteNode.children[0].borderWidth, 2)
            XCTAssertEqual(paletteNode.children[1].borderWidth, 1)

            paletteNode.children[1].onActivate?()

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
            let localizedNode = makeNode(
                DatePicker("FR", selection: .constant(date), displayedComponents: .all)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 3_600)!)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
            )
            let environmentReaderNode = makeNode(
                DateEnvironmentReaderView()
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 3_600)!)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
            )
            var localizedCalendar = Calendar(identifier: .gregorian)
            localizedCalendar.timeZone = TimeZone(secondsFromGMT: 3_600)!
            let localizedFormatter = DateFormatter()
            localizedFormatter.calendar = localizedCalendar
            localizedFormatter.timeZone = localizedCalendar.timeZone
            localizedFormatter.locale = Locale(identifier: "fr_FR")
            localizedFormatter.dateStyle = .medium
            localizedFormatter.timeStyle = .short

            XCTAssertEqual(allTexts(in: dateNode), ["START", "2026-05-10"])
            XCTAssertTrue(allTexts(in: timeNode).contains("WINDOW"))
            XCTAssertTrue(allTexts(in: timeNode).contains("14:38"))
            XCTAssertEqual(allTexts(in: rangedNode), ["DUE", "2026-05-10 14:38"])
            XCTAssertEqual(allTexts(in: partialRangeNode), ["AFTER", "2026-05-10"])
            XCTAssertEqual(allTexts(in: throughRangeNode), ["BEFORE", "14:38"])
            XCTAssertEqual(allTexts(in: upToRangeNode), ["UNTIL", "2026-05-10"])
            XCTAssertEqual(allTexts(in: timeZoneNode), ["LOCAL", "15:38"])
            XCTAssertEqual(allTexts(in: localizedNode), ["FR", localizedFormatter.string(from: date)])
            XCTAssertEqual(environmentReaderNode.text, "DATEENV")
            XCTAssertEqual(dateNode.children[0].layoutPriority, 1)
        }
    }

    func testDatePickerStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct DatePickerStyleReaderView: View {
                @Environment(\.datePickerStyle) var datePickerStyle

                var body: some View {
                    Text(
                        datePickerStyle == .compact
                            ? "COMPACT"
                            : datePickerStyle == .graphical
                                ? "GRAPHICAL"
                                : datePickerStyle == .wheel
                                    ? "WHEEL"
                                    : datePickerStyle == .automatic
                                        ? "AUTOMATIC"
                                        : "OTHER"
                    )
                }
            }

            let compactNode = makeNode(DatePickerStyleReaderView().datePickerStyle(CompactDatePickerStyle()))
            let graphicalNode = makeNode(DatePickerStyleReaderView().datePickerStyle(.graphical))
            let wheelNode = makeNode(DatePickerStyleReaderView().datePickerStyle(WheelDatePickerStyle()))
            let automaticNode = makeNode(DatePickerStyleReaderView().datePickerStyle(DefaultDatePickerStyle()))
            let fieldNode = makeNode(DatePickerStyleReaderView().datePickerStyle(FieldDatePickerStyle()))
            let stepperFieldNode = makeNode(DatePickerStyleReaderView().datePickerStyle(StepperFieldDatePickerStyle()))

            XCTAssertEqual(compactNode.text, "COMPACT")
            XCTAssertEqual(graphicalNode.text, "GRAPHICAL")
            XCTAssertEqual(wheelNode.text, "WHEEL")
            XCTAssertEqual(automaticNode.text, "AUTOMATIC")
            XCTAssertEqual(fieldNode.text, "OTHER")
            XCTAssertEqual(stepperFieldNode.text, "OTHER")
        }
    }

    func testDatePickerStylesUseRetainedStyleChrome() async {
        await MainActor.run {
            let date = Date(timeIntervalSince1970: 1_778_423_880)

            let compactNode = makeNode(
                DatePicker("COMPACT", selection: .constant(date), displayedComponents: .date)
                    .datePickerStyle(CompactDatePickerStyle())
            )
            let fieldNode = makeNode(
                DatePicker("FIELD", selection: .constant(date), displayedComponents: .date)
                    .datePickerStyle(FieldDatePickerStyle())
            )
            let stepperNode = makeNode(
                DatePicker("STEPPER", selection: .constant(date), displayedComponents: .date)
                    .datePickerStyle(StepperFieldDatePickerStyle())
            )
            let wheelNode = makeNode(
                DatePicker("WHEEL", selection: .constant(date), displayedComponents: .date)
                    .datePickerStyle(WheelDatePickerStyle())
            )
            let graphicalNode = makeNode(
                DatePicker("GRAPHICAL", selection: .constant(date), displayedComponents: .date)
                    .datePickerStyle(GraphicalDatePickerStyle())
            )

            let compactControl = compactNode.children[1]
            XCTAssertEqual(compactControl.children.count, 2)
            XCTAssertEqual(compactControl.borderWidth, 1)
            XCTAssertEqual(compactControl.cornerRadius, 8)
            XCTAssertEqual(
                compactControl.preferredSize,
                Size(width: 220, height: ControlSize.regular.singleLineTextInputSize.height))
            XCTAssertTrue(allTexts(in: compactControl).contains("2026-05-10"))

            let fieldControl = fieldNode.children[1]
            XCTAssertEqual(fieldControl.children.count, 1)
            XCTAssertEqual(fieldControl.borderWidth, 1)
            XCTAssertEqual(fieldControl.cornerRadius, 3)
            XCTAssertEqual(
                fieldControl.preferredSize,
                Size(width: 220, height: ControlSize.regular.singleLineTextInputSize.height))

            let stepperControl = stepperNode.children[1]
            XCTAssertEqual(stepperControl.children.count, 2)
            XCTAssertEqual(stepperControl.borderWidth, 1)
            XCTAssertEqual(stepperControl.cornerRadius, 7)
            XCTAssertEqual(
                stepperControl.preferredSize,
                Size(width: 250, height: ControlSize.regular.singleLineTextInputSize.height))
            XCTAssertEqual(allTexts(in: stepperControl.children[1]), ["+", "-"])

            let wheelControl = wheelNode.children[1]
            XCTAssertEqual(wheelControl.children.count, 3)
            XCTAssertEqual(wheelControl.borderWidth, 1)
            XCTAssertEqual(wheelControl.cornerRadius, 10)
            XCTAssertEqual(wheelControl.preferredSize, Size(width: 220, height: 64))
            XCTAssertEqual(allTexts(in: wheelControl), ["2026-05-10"])

            let graphicalControl = graphicalNode.children[1]
            XCTAssertEqual(graphicalControl.children.count, 3)
            XCTAssertEqual(graphicalControl.borderWidth, 1)
            XCTAssertEqual(graphicalControl.cornerRadius, 12)
            XCTAssertEqual(graphicalControl.preferredSize, Size(width: 220, height: 78))
            XCTAssertEqual(graphicalControl.children[2].children.count, 5)
            XCTAssertTrue(allTexts(in: graphicalControl).contains("2026-05-10"))
        }
    }

    func testDatePickerWritesBindingFromKeyboardWithinRange() async {
        await MainActor.run {
            var selectedDate = Date(timeIntervalSince1970: 1_778_400_000)
            let nextDay = selectedDate.addingTimeInterval(86_400)
            var invalidationCount = 0
            let binding = Binding<Date>(
                get: { selectedDate },
                set: { selectedDate = $0 }
            )
            let node = makeNode(
                DatePicker("START", selection: binding, in: selectedDate...nextDay, displayedComponents: .date),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertTrue(node.isFocusable)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            XCTAssertEqual(selectedDate, nextDay)
            XCTAssertEqual(invalidationCount, 1)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            XCTAssertEqual(selectedDate, nextDay)
            XCTAssertEqual(invalidationCount, 1)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertEqual(selectedDate, Date(timeIntervalSince1970: 1_778_400_000))
            XCTAssertEqual(invalidationCount, 2)
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

            // NSColorWell shows a 34x22 well with a hairline ring and an
            // inner gutter — never the 8-digit RGBA readout this used to
            // print beside it. The hex string survives as the well's
            // accessible value.
            XCTAssertEqual(allTexts(in: titledNode), ["ACCENT"])
            XCTAssertEqual(titledNode.children[1].accessibilityValue, "#33669980")
            let titledWell = titledNode.children[1].children[0]
            XCTAssertEqual(titledWell.children[0].backgroundColor, color)
            XCTAssertEqual(titledWell.preferredSize, Size(width: 34, height: 22))
            XCTAssertEqual(titledNode.children[0].layoutPriority, 1)
            XCTAssertEqual(allTexts(in: noOpacityNode), ["BRAND"])
            XCTAssertEqual(noOpacityNode.children[1].accessibilityValue, "#336699")
            XCTAssertTrue(allTexts(in: builderNode).contains("TINT"))
            let builderWell = builderNode.children[1].children[0]
            XCTAssertEqual(builderWell.children[0].backgroundColor, .orange)
            XCTAssertEqual(builderWell.preferredSize, Size(width: 40, height: 34))
        }
    }

    func testColorPickerWritesBindingFromKeyboardPaletteAndOpacity() async {
        await MainActor.run {
            var selectedColor = Color.blue.opacity(0.5)
            var invalidationCount = 0
            let binding = Binding<Color>(
                get: { selectedColor },
                set: { selectedColor = $0 }
            )
            let node = makeNode(
                ColorPicker("ACCENT", selection: binding),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertTrue(node.isFocusable)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            XCTAssertEqual(selectedColor, Color.indigo.opacity(0.5))
            XCTAssertEqual(invalidationCount, 1)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
            XCTAssertEqual(selectedColor, Color.blue.opacity(0.5))
            XCTAssertEqual(invalidationCount, 2)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            XCTAssertEqual(selectedColor, Color.blue.opacity(0.6))
            XCTAssertEqual(invalidationCount, 3)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertEqual(selectedColor, Color.blue.opacity(0.5))
            XCTAssertEqual(invalidationCount, 4)
        }
    }

    func testColorPickerWithoutOpacityWritesOpaquePaletteColors() async {
        await MainActor.run {
            var selectedColor = Color.blue.opacity(0.5)
            var invalidationCount = 0
            let binding = Binding<Color>(
                get: { selectedColor },
                set: { selectedColor = $0 }
            )
            let node = makeNode(
                ColorPicker("ACCENT", selection: binding, supportsOpacity: false),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            XCTAssertEqual(selectedColor, Color.blue.opacity(0.5))
            XCTAssertEqual(invalidationCount, 0)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            XCTAssertEqual(selectedColor, .indigo)
            XCTAssertEqual(invalidationCount, 1)
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

            // The bezel alone: [increment][seam rule][decrement].
            XCTAssertEqual(stepperNode.children.count, 3)
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
            // A colour well paints no text at all — the hex readout moved
            // to the well's accessible value.
            XCTAssertEqual(allTexts(in: colorPickerNode), [])
            XCTAssertEqual(colorPickerNode.accessibilityValue, "#007AFF")
            XCTAssertEqual(colorPickerNode.children[0].children[0].backgroundColor, .blue)
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

            // Heights are the macOS reference plus the single named
            // Windows pointer delta, scaled per control size.
            XCTAssertEqual(
                textFieldNode.preferredSize,
                Size(width: 200, height: ControlSize.small.singleLineTextInputSize.height))
            XCTAssertEqual(textEditorNode.preferredSize, Size(width: 300, height: 144))
            // The switch is the one control sized outside the pointer-padding
            // rule: `Toggle.largeSize` plus the node's own 4pt gutter.
            XCTAssertEqual(toggleNode.children[1].preferredSize, Size(width: 56, height: 34))
            XCTAssertEqual(
                pickerNode.children[1].preferredSize,
                Size(width: 232, height: ControlSize.large.pickerMenuPreferredSize.height))
            // The stepper is one bezel holding two halves split by a
            // hairline, not two siblings.
            let stepperBezel = stepperNode.children[1]
            XCTAssertEqual(stepperBezel.children.count, 3)
            for half in stepperBezel.children where !half.isSeparatorRule {
                XCTAssertEqual(half.preferredSize, ControlSize.small.stepperButtonPreferredSize)
            }
            XCTAssertEqual(sliderNode.preferredSize, Size(width: 240, height: 34))
            XCTAssertEqual(
                progressNode.preferredSize,
                Size(width: 280, height: ControlSize.extraLarge.progressPreferredSize.height))
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

            stepperIncrement(of: node).onActivate?()
            XCTAssertEqual(value, 6.0, accuracy: 0.001)
            XCTAssertTrue(didInvalidate)
            XCTAssertEqual(editingChanges, [true, false])

            stepperDecrement(of: node).onActivate?()
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
            XCTAssertTrue(stepperDecrement(of: node).isFocusable)
            XCTAssertFalse(stepperIncrement(of: node).isFocusable)

            stepperIncrement(of: node).onActivate?()
            XCTAssertEqual(value, 1)
            stepperDecrement(of: node).onActivate?()
            XCTAssertEqual(value, 0)
        }
    }

    func testStepperGenericStrideableValueWritesBinding() async {
        await MainActor.run {
            var value: Float = 0.25
            var editingChanges: [Bool] = []

            let node = makeNode(
                Stepper(
                    LocalizedStringKey("VOLUME"),
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    ),
                    in: 0.0...1.0,
                    step: 0.25,
                    onEditingChanged: { isEditing in
                        editingChanges.append(isEditing)
                    }
                )
            )

            XCTAssertEqual(firstText(in: node.children[0]), "VOLUME")

            stepperIncrement(of: node).onActivate?()
            XCTAssertEqual(value, 0.5, accuracy: 0.001)
            stepperDecrement(of: node).onActivate?()
            stepperDecrement(of: node).onActivate?()

            XCTAssertEqual(value, 0.0, accuracy: 0.001)
            XCTAssertEqual(editingChanges, [true, false, true, false, true, false])

            let clampedNode = makeNode(
                Stepper(
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    ),
                    in: 0.0...1.0,
                    step: 0.25
                ) {
                    Text("FLOAT")
                }
            )

            XCTAssertFalse(stepperDecrement(of: clampedNode).isFocusable)
            XCTAssertTrue(stepperIncrement(of: clampedNode).isFocusable)
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
            XCTAssertFalse(stepperDecrement(of: node).isFocusable)
            XCTAssertTrue(stepperIncrement(of: node).isFocusable)

            stepperDecrement(of: node).onActivate?()
            XCTAssertEqual(decrements, 0)

            stepperIncrement(of: node).onActivate?()
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
            XCTAssertTrue(stepperDecrement(of: builderNode).isFocusable)
            XCTAssertFalse(stepperIncrement(of: builderNode).isFocusable)

            stepperDecrement(of: builderNode).onActivate?()
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
            node.onDragChange?(Point(x: 92, y: 0), Point(x: 92, y: 0))

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
            node.onDragChange?(Point(x: 92, y: 0), Point(x: 92, y: 0))
            node.onDragEnd?(Point(x: 92, y: 0), Point(x: 92, y: 0))

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

    func testSliderGenericBinaryFloatingPointBindingWritesThroughDoubleRetainedSlider() async {
        await MainActor.run {
            var value: Float = 0.0
            var editingChanges: [Bool] = []

            let node = makeNode(
                Slider(
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    ),
                    in: Float(0)...Float(1),
                    step: Float(0.25),
                    onEditingChanged: { isEditing in
                        editingChanges.append(isEditing)
                    }
                )
            )

            node.onDragStart?(Point(x: 0, y: 0))
            node.onDragChange?(Point(x: 92, y: 0), Point(x: 92, y: 0))
            node.onDragEnd?(Point(x: 92, y: 0), Point(x: 92, y: 0))

            XCTAssertEqual(value, 0.5, accuracy: 0.001)
            XCTAssertEqual(editingChanges, [true, false])

            let labeledNode = makeNode(
                Slider(
                    value: Binding(
                        get: { value },
                        set: { value = $0 }
                    ),
                    in: Float(0)...Float(1),
                    step: Float(0.25)
                ) {
                    Text("LEVEL")
                } minimumValueLabel: {
                    Text("MIN")
                } maximumValueLabel: {
                    Text("MAX")
                }
            )

            XCTAssertTrue(allTexts(in: labeledNode.children[0]).contains("LEVEL"))
            XCTAssertTrue(allTexts(in: labeledNode.children[1]).contains("MIN"))
            XCTAssertTrue(allTexts(in: labeledNode.children[1]).contains("MAX"))
        }
    }

    func testSliderCurrentLabelInitializerComposesLabelAndKeepsBindingBehavior() async {
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
                    step: 2
                ) {
                    Label("GAIN", systemImage: "slider.horizontal.3")
                } onEditingChanged: { isEditing in
                    editingChanges.append(isEditing)
                }
            )

            XCTAssertTrue(allTexts(in: node.children[0]).contains("GAIN"))

            let sliderNode = node.children[1].children[0]
            // Mid-track: half of (200pt slider - 16pt macOS thumb). A
            // half-way drag lands on 5.0 and the step-2 snap rounds it up.
            sliderNode.onDragStart?(Point(x: 0, y: 0))
            sliderNode.onDragChange?(Point(x: 92, y: 0), Point(x: 92, y: 0))
            sliderNode.onDragEnd?(Point(x: 92, y: 0), Point(x: 92, y: 0))

            XCTAssertEqual(value, 6.0, accuracy: 0.001)
            XCTAssertEqual(editingChanges, [true, false])
        }
    }

    func testSliderCurrentLabelMinimumMaximumInitializerComposesLabels() async {
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
                    step: 2
                ) {
                    Text("GAIN")
                } minimumValueLabel: {
                    Text("LOW")
                } maximumValueLabel: {
                    Text("HIGH")
                } onEditingChanged: { isEditing in
                    editingChanges.append(isEditing)
                }
            )

            XCTAssertEqual(firstText(in: node.children[0]), "GAIN")
            XCTAssertEqual(firstText(in: node.children[1].children[0]), "LOW")
            XCTAssertEqual(firstText(in: node.children[1].children[2]), "HIGH")

            let sliderNode = node.children[1].children[1]
            XCTAssertEqual(sliderNode.preferredSize?.width, 100)
            sliderNode.onDragStart?(Point(x: 0, y: 0))
            sliderNode.onDragChange?(Point(x: 42, y: 0), Point(x: 42, y: 0))
            sliderNode.onDragEnd?(Point(x: 42, y: 0), Point(x: 42, y: 0))

            XCTAssertEqual(value, 6.0, accuracy: 0.001)
            XCTAssertEqual(editingChanges, [true, false])
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
            // Labeled sliders cap the track at 100pt preferred width, so the
            // usable drag track is 100 - 18 (thumb) = 82pt; x=49 lands at
            // 49/82 * 10 ≈ 5.98, which snaps to 6.0 with step 2.
            sliderNode.onDragStart?(Point(x: 0, y: 0))
            sliderNode.onDragChange?(Point(x: 49, y: 0), Point(x: 49, y: 0))
            sliderNode.onDragEnd?(Point(x: 49, y: 0), Point(x: 49, y: 0))

            XCTAssertEqual(value, 6.0, accuracy: 0.001)
            XCTAssertEqual(editingChanges, [true, false])
        }
    }

    func testProgressViewMapsToProgressBarNode() async {
        await MainActor.run {
            let node = makeNode(ProgressView(value: 0.25, total: 1.0))

            XCTAssertEqual(
                node.preferredSize,
                Size(width: 200, height: ControlSize.regular.progressPreferredSize.height))
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

    func testProgressViewBinaryFloatingPointInitializersMapToProgressBarNode() async {
        await MainActor.run {
            let value: Float? = 0.5
            let plainNode = makeNode(ProgressView(value: value, total: Float(2.0)))
            let titleNode = makeNode(ProgressView(LocalizedStringKey("UPLOAD"), value: Float(1.5), total: Float(3.0)))
            let currentValueNode = makeNode(
                ProgressView(value: Float(0.25), total: Float(1.0)) {
                    Text("SYNC")
                } currentValueLabel: {
                    Text("25%")
                }
            )
            let indeterminateNode = makeNode(ProgressView(value: Optional<Float>.none, total: Float(1.0)))

            XCTAssertEqual(plainNode.children[1].frame.size.width, 50)
            XCTAssertEqual(firstText(in: titleNode.children[0]), "UPLOAD")
            XCTAssertEqual(titleNode.children[1].children[1].frame.size.width, 100)
            XCTAssertEqual(firstText(in: currentValueNode.children[0].children[0]), "SYNC")
            XCTAssertEqual(firstText(in: currentValueNode.children[0].children[1]), "25%")
            XCTAssertEqual(currentValueNode.children[1].children[1].frame.size.width, 50)
            XCTAssertEqual(indeterminateNode.children[1].frame.size.width, 0)
        }
    }

    func testProgressViewTimerIntervalInitializerMapsElapsedProgress() async {
        await MainActor.run {
            let pastInterval = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 10)
            let futureStart = Date(timeIntervalSince1970: 4_102_444_800)
            let futureInterval = futureStart...futureStart.addingTimeInterval(10)

            let elapsedNode = makeNode(ProgressView(timerInterval: pastInterval, countsDown: false))
            let elapsedCountdownNode = makeNode(ProgressView(timerInterval: pastInterval))
            let futureNode = makeNode(ProgressView(timerInterval: futureInterval, countsDown: false))
            let futureCountdownNode = makeNode(ProgressView(timerInterval: futureInterval))

            XCTAssertEqual(elapsedNode.children[1].frame.size.width, 200)
            XCTAssertEqual(elapsedCountdownNode.children[1].frame.size.width, 0)
            XCTAssertEqual(futureNode.children[1].frame.size.width, 0)
            XCTAssertEqual(futureCountdownNode.children[1].frame.size.width, 200)
        }
    }

    func testProgressViewTimerIntervalLabelInitializersComposeLabels() async {
        await MainActor.run {
            let interval = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 10)
            let labelNode = makeNode(
                ProgressView(timerInterval: interval, countsDown: false) {
                    Text("SYNC")
                }
            )
            let currentValueNode = makeNode(
                ProgressView(timerInterval: interval, countsDown: false) {
                    Text("SYNC")
                } currentValueLabel: {
                    Text("DONE")
                }
            )

            XCTAssertEqual(firstText(in: labelNode.children[0]), "SYNC")
            XCTAssertEqual(labelNode.children[1].children[1].frame.size.width, 200)
            XCTAssertEqual(firstText(in: currentValueNode.children[0].children[0]), "SYNC")
            XCTAssertEqual(firstText(in: currentValueNode.children[0].children[1]), "DONE")
            XCTAssertEqual(currentValueNode.children[1].children[1].frame.size.width, 200)
        }
    }

    func testProgressViewStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct ProgressViewStyleReaderView: View {
                @Environment(\.progressViewStyle) var progressViewStyle

                var body: some View {
                    Text(
                        progressViewStyle == .circular
                            ? "CIRCULAR"
                            : progressViewStyle == .linear
                                ? "LINEAR"
                                : progressViewStyle == .automatic
                                    ? "AUTOMATIC"
                                    : "OTHER"
                    )
                }
            }

            let readerNode = makeNode(ProgressViewStyleReaderView().progressViewStyle(CircularProgressViewStyle()))
            let linearReaderNode = makeNode(ProgressViewStyleReaderView().progressViewStyle(LinearProgressViewStyle()))
            let automaticReaderNode = makeNode(
                ProgressViewStyleReaderView().progressViewStyle(DefaultProgressViewStyle()))
            let inheritedNode = makeNode(
                VStack {
                    ProgressView(value: 0.25, total: 1.0)
                    ProgressView(value: 0.75, total: 1.0)
                }
                .progressViewStyle(LinearProgressViewStyle())
            )

            XCTAssertEqual(readerNode.text, "CIRCULAR")
            XCTAssertEqual(linearReaderNode.text, "LINEAR")
            XCTAssertEqual(automaticReaderNode.text, "AUTOMATIC")
            XCTAssertEqual(inheritedNode.children[0].children[1].frame.size.width, 50)
            XCTAssertEqual(inheritedNode.children[1].children[1].frame.size.width, 150)
        }
    }

    func testCircularProgressViewStyleUsesRetainedCircularSegments() async {
        await MainActor.run {
            let tint = Color(red: 0.15, green: 0.70, blue: 0.50, alpha: 1)
            let track = Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0)
            let node = makeNode(
                ProgressView(value: 0.5, total: 1.0)
                    .progressViewStyle(CircularProgressViewStyle())
                    .controlSize(.large)
                    .tint(tint)
            )
            let labeledNode = makeNode(
                ProgressView("SYNC", value: 0.25, total: 1.0)
                    .progressViewStyle(.circular)
                    .tint(tint)
            )
            let indeterminateNode = makeNode(
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(tint)
            )

            XCTAssertEqual(node.preferredSize?.width, 34)
            XCTAssertEqual(node.preferredSize?.height, 34)
            XCTAssertEqual(node.children.count, 12)
            XCTAssertEqual(node.children[0].backgroundColor, tint)
            XCTAssertEqual(node.children[5].backgroundColor, tint)
            XCTAssertEqual(node.children[6].backgroundColor, track)

            XCTAssertEqual(firstText(in: labeledNode.children[0]), "SYNC")
            XCTAssertEqual(labeledNode.children[1].children.count, 12)
            XCTAssertEqual(labeledNode.children[1].children[0].backgroundColor, tint)
            XCTAssertEqual(labeledNode.children[1].children[3].backgroundColor, track)

            XCTAssertEqual(indeterminateNode.children.count, 12)
            XCTAssertEqual(indeterminateNode.children[0].backgroundColor, tint)
            XCTAssertEqual(indeterminateNode.children[1].backgroundColor, tint.multipliedAlpha(by: 0.72))
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

    func testGaugeBinaryFloatingPointInitializersMapToRetainedProgressBar() async {
        await MainActor.run {
            let builderNode = makeNode(
                Gauge(value: Float(0.25), in: Float(0)...Float(1)) {
                    Text("FLOAT")
                } currentValueLabel: {
                    Text("25%")
                }
            )
            let titleNode = makeNode(Gauge("TEMPERATURE", value: Float(2.5), in: Float(0)...Float(5)))
            let keyNode = makeNode(Gauge(LocalizedStringKey("LOAD"), value: Float(3), in: Float(0)...Float(6)))
            let boundsNode = makeNode(
                Gauge(value: Float(2), in: Float(0)...Float(4)) {
                    Text("CAPACITY")
                } currentValueLabel: {
                    Text("HALF")
                } minimumValueLabel: {
                    Text("EMPTY")
                } maximumValueLabel: {
                    Text("FULL")
                }
            )

            XCTAssertEqual(firstText(in: builderNode.children[0].children[0]), "FLOAT")
            XCTAssertEqual(firstText(in: builderNode.children[0].children[1]), "25%")
            XCTAssertEqual(builderNode.children[1].children[1].frame.size.width, 50)

            XCTAssertTrue(allTexts(in: titleNode.children[0]).contains("TEMPERATURE"))
            XCTAssertEqual(titleNode.children[1].children[1].frame.size.width, 100)

            XCTAssertTrue(allTexts(in: keyNode.children[0]).contains("LOAD"))
            XCTAssertEqual(keyNode.children[1].children[1].frame.size.width, 100)

            XCTAssertTrue(allTexts(in: boundsNode.children[0]).contains("CAPACITY"))
            XCTAssertTrue(allTexts(in: boundsNode.children[0]).contains("HALF"))
            XCTAssertEqual(boundsNode.children[1].children[1].frame.size.width, 100)
            XCTAssertEqual(firstText(in: boundsNode.children[2].children[0]), "EMPTY")
            XCTAssertEqual(firstText(in: boundsNode.children[2].children[2]), "FULL")
        }
    }

    func testGaugeMarkedValueLabelInitializersPreserveRetainedGaugeChrome() async {
        await MainActor.run {
            let markedNode = makeNode(
                Gauge(value: 0.5, in: 0...1) {
                    Text("CPU")
                } currentValueLabel: {
                    Text("50%")
                } markedValueLabels: {
                    Text("25%")
                    Text("75%")
                }
            )
            let boundsNode = makeNode(
                Gauge(value: Float(0.75), in: Float(0)...Float(1)) {
                    Text("MEMORY")
                } currentValueLabel: {
                    Text("75%")
                } minimumValueLabel: {
                    Text("LOW")
                } maximumValueLabel: {
                    Text("HIGH")
                } markedValueLabels: {
                    Text("MID")
                }
            )

            XCTAssertTrue(allTexts(in: markedNode.children[0]).contains("CPU"))
            XCTAssertTrue(allTexts(in: markedNode.children[0]).contains("50%"))
            XCTAssertTrue(allTexts(in: markedNode.children[2]).contains("25%"))
            XCTAssertTrue(allTexts(in: markedNode.children[2]).contains("75%"))
            XCTAssertEqual(markedNode.children[1].children[1].frame.size.width, 100)

            XCTAssertTrue(allTexts(in: boundsNode.children[0]).contains("MEMORY"))
            XCTAssertTrue(allTexts(in: boundsNode.children[0]).contains("75%"))
            XCTAssertEqual(boundsNode.children[1].children[1].frame.size.width, 150)
            XCTAssertTrue(allTexts(in: boundsNode.children[2]).contains("MID"))
            XCTAssertEqual(firstText(in: boundsNode.children[3].children[0]), "LOW")
            XCTAssertEqual(firstText(in: boundsNode.children[3].children[2]), "HIGH")
        }
    }

    func testGaugeStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct GaugeStyleReaderView: View {
                @Environment(\.gaugeStyle) var gaugeStyle

                var body: some View {
                    Text(
                        gaugeStyle == .accessoryCircularCapacity
                            ? "CIRCULAR"
                            : gaugeStyle == .linearCapacity
                                ? "LINEARCAP"
                                : gaugeStyle == .accessoryLinear
                                    ? "ACCESSORY"
                                    : gaugeStyle == .automatic
                                        ? "AUTOMATIC"
                                        : "OTHER"
                    )
                }
            }

            let tint = Color(red: 0.15, green: 0.7, blue: 0.5, alpha: 1)
            let readerNode = makeNode(GaugeStyleReaderView().gaugeStyle(AccessoryCircularCapacityGaugeStyle()))
            let linearCapacityReaderNode = makeNode(GaugeStyleReaderView().gaugeStyle(LinearCapacityGaugeStyle()))
            let accessoryReaderNode = makeNode(GaugeStyleReaderView().gaugeStyle(AccessoryLinearGaugeStyle()))
            let automaticReaderNode = makeNode(GaugeStyleReaderView().gaugeStyle(DefaultGaugeStyle()))
            let circularTintNode = makeNode(
                Gauge(value: 0.5, in: 0...1) {
                    Text("BATTERY")
                }
                .gaugeStyle(CircularGaugeStyle(tint: tint))
            )
            let inheritedNode = makeNode(
                VStack {
                    Gauge(value: 0.25, in: 0...1) {
                        Text("CPU")
                    }
                    Gauge(value: Float(0.75), in: Float(0)...Float(1)) {
                        Text("MEMORY")
                    }
                }
                .gaugeStyle(AccessoryLinearCapacityGaugeStyle())
            )

            XCTAssertEqual(readerNode.text, "CIRCULAR")
            XCTAssertEqual(linearCapacityReaderNode.text, "LINEARCAP")
            XCTAssertEqual(accessoryReaderNode.text, "ACCESSORY")
            XCTAssertEqual(automaticReaderNode.text, "AUTOMATIC")
            XCTAssertEqual(circularTintNode.children[1].children.count, 12)
            XCTAssertEqual(circularTintNode.children[1].children[0].backgroundColor, tint)
            XCTAssertEqual(circularTintNode.children[1].children[5].backgroundColor, tint)
            XCTAssertEqual(
                circularTintNode.children[1].children[6].backgroundColor,
                Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0))
            XCTAssertEqual(inheritedNode.children[0].children[1].children[1].frame.size.width, 50)
            XCTAssertEqual(inheritedNode.children[1].children[1].children[1].frame.size.width, 150)
        }
    }

    func testAccessoryCircularGaugeStylesUseRetainedCircularSegments() async {
        await MainActor.run {
            let tint = Color(red: 0.35, green: 0.55, blue: 0.95, alpha: 1)
            let node = makeNode(
                VStack {
                    Gauge(value: 0.25, in: 0...1) {
                        Text("CPU")
                    }
                    .gaugeStyle(AccessoryCircularGaugeStyle())

                    Gauge(value: Float(0.75), in: Float(0)...Float(1)) {
                        Text("MEMORY")
                    }
                    .gaugeStyle(AccessoryCircularCapacityGaugeStyle())
                }
                .tint(tint)
            )

            let firstGauge = node.children[0].children[1]
            let secondGauge = node.children[1].children[1]
            XCTAssertEqual(firstGauge.children.count, 12)
            XCTAssertEqual(secondGauge.children.count, 12)
            XCTAssertEqual(firstGauge.children[0].backgroundColor, tint)
            XCTAssertEqual(firstGauge.children[2].backgroundColor, tint)
            XCTAssertEqual(
                firstGauge.children[3].backgroundColor, Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0))
            XCTAssertEqual(secondGauge.children[8].backgroundColor, tint)
            XCTAssertEqual(
                secondGauge.children[9].backgroundColor, Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0))
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

    func testBlendModeModifierMapsSupportedModesToRetainedFrameCommands() async {
        await MainActor.run {
            let directNode = makeNode(Rectangle().fill(.red).blendMode(.screen))
            let additiveNode = makeNode(Rectangle().fill(.red).blendMode(.plusLighter))
            let fallbackNode = makeNode(Rectangle().fill(.red).blendMode(.color))
            let inherited = makeRuntimeNode(
                VStack {
                    Rectangle()
                        .fill(.red)
                        .frame(width: 20, height: 10)
                }
                .blendMode(.multiply),
                size: Size(width: 100, height: 80)
            )
            let inheritedFrame = inherited.runtime.renderFrame()

            let fillBlendModes = inheritedFrame.commands.compactMap { command -> SwiftWindowsGraphics.BlendMode? in
                guard case .fillRect(let fill) = command, fill.color == .red else {
                    return nil
                }

                return fill.blendMode
            }

            XCTAssertEqual(directNode.blendMode, SwiftWindowsGraphics.BlendMode.screen)
            XCTAssertEqual(additiveNode.blendMode, SwiftWindowsGraphics.BlendMode.additive)
            XCTAssertEqual(fallbackNode.blendMode, SwiftWindowsGraphics.BlendMode.normal)
            XCTAssertTrue(fillBlendModes.contains(.multiply))
        }
    }

    func testCompositingAndDrawingGroupStoreRetainedMetadata() async {
        await MainActor.run {
            let compositingNode = makeNode(Text("GROUP").compositingGroup())
            let defaultDrawingNode = makeNode(Text("DRAW").drawingGroup())
            let linearDrawingNode = makeNode(Text("LINEAR").drawingGroup(opaque: true, colorMode: .linear))
            let extendedDrawingNode = makeNode(Text("EXTENDED").drawingGroup(colorMode: .extendedLinear))

            XCTAssertTrue(compositingNode.isCompositingGroup)
            XCTAssertNil(compositingNode.drawingGroup)
            XCTAssertTrue(defaultDrawingNode.isCompositingGroup)
            XCTAssertEqual(defaultDrawingNode.drawingGroup, RetainedDrawingGroup(opaque: false, colorMode: .nonLinear))
            XCTAssertTrue(linearDrawingNode.isCompositingGroup)
            XCTAssertEqual(linearDrawingNode.drawingGroup, RetainedDrawingGroup(opaque: true, colorMode: .linear))
            XCTAssertEqual(extendedDrawingNode.drawingGroup?.colorMode, .extendedLinear)
        }
    }

    func testColorFilterModifiersStoreRetainedMetadata() async {
        await MainActor.run {
            let multiplyColor = Color(red: 0.5, green: 0.25, blue: 0.75, alpha: 1)
            let node = makeNode(
                Text("FILTER")
                    .brightness(0.15)
                    .contrast(1.25)
                    .colorInvert()
                    .colorMultiply(multiplyColor)
                    .saturation(0.6)
                    .grayscale(0.35)
                    .hueRotation(.degrees(90))
                    .luminanceToAlpha()
            )

            XCTAssertEqual(
                node.colorEffects,
                [
                    .brightness(0.15),
                    .contrast(1.25),
                    .colorInvert,
                    .colorMultiply(multiplyColor),
                    .saturation(0.6),
                    .grayscale(0.35),
                    .hueRotation(.pi / 2),
                    .luminanceToAlpha,
                ]
            )
        }
    }

    func testShaderEffectModifiersStoreRetainedMetadata() async {
        await MainActor.run {
            let colorShader = ShaderLibrary.default.tint(.float(0.25), .color(.red))
            let distortionShader = ShaderLibrary.default.wave(amount: .float(2.0))
            let layerShader = Shader("manualLayer", arguments: [.size(CGSize(width: 3, height: 4))])
            let expectedColorShaderDescription =
                "default.tint(float:0.25;color:red:\(Color.red.red),green:\(Color.red.green),blue:\(Color.red.blue),alpha:\(Color.red.alpha))"
            let node = makeNode(
                Text("SHADER")
                    .colorEffect(colorShader)
                    .distortionEffect(
                        distortionShader,
                        maxSampleOffset: CGSize(width: 8, height: 6),
                        isEnabled: false
                    )
                    .layerEffect(layerShader, maxSampleOffset: CGSize(width: 2, height: 1))
            )

            XCTAssertEqual(colorShader.description, expectedColorShaderDescription)
            XCTAssertEqual(distortionShader.description, "default.wave(amount:float:2.0)")
            XCTAssertEqual(
                node.visualEffects,
                [
                    "colorEffect(shader:\(expectedColorShaderDescription),enabled:true)",
                    "distortionEffect(shader:default.wave(amount:float:2.0),maxSampleOffset:8.0,6.0,enabled:false)",
                    "layerEffect(shader:manualLayer(size:3.0,4.0),maxSampleOffset:2.0,1.0,enabled:true)",
                ]
            )
        }
    }

    func testMaskModifierStoresRetainedMetadataAndMaskSource() async {
        await MainActor.run {
            let centeredNode = makeNode(
                Text("BASE")
                    .mask {
                        Rectangle()
                            .frame(width: 24, height: 12)
                    }
            )
            let alignedNode = makeNode(
                Text("BASE")
                    .mask(alignment: .topTrailing) {
                        Text("MASK")
                    }
            )

            XCTAssertEqual(centeredNode.viewMask, RetainedViewMask())
            XCTAssertEqual(centeredNode.children.count, 2)
            XCTAssertEqual(centeredNode.children[0].text, "BASE")
            XCTAssertTrue(centeredNode.children[1].isHidden)
            XCTAssertEqual(
                alignedNode.viewMask,
                RetainedViewMask(horizontal: .trailing, vertical: .top)
            )
            XCTAssertEqual(alignedNode.children.count, 2)
            XCTAssertEqual(alignedNode.children[1].text, "MASK")
            XCTAssertTrue(alignedNode.children[1].isHidden)
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

    func testFocusStateBoolBindingSynchronizesRetainedFocus() async {
        await MainActor.run {
            let focusState = FocusState<Bool>()
            let node = makeNode(Text("FOCUS").focused(focusState.projectedValue))
            let runtime = RetainedViewRuntime(root: ViewNode())

            XCTAssertTrue(node.isFocusable)
            XCTAssertTrue(node.isHitTestVisible)
            XCTAssertFalse(focusState.wrappedValue)

            runtime.requestFocus(node)

            XCTAssertTrue(node.isFocused)
            XCTAssertTrue(focusState.wrappedValue)

            runtime.keyboardFocusDidLeaveWindow()

            XCTAssertFalse(node.isFocused)
            XCTAssertFalse(focusState.wrappedValue)

            let initiallyFocused = FocusState<Bool>(wrappedValue: true)
            let focusedNode = makeNode(Text("AUTO").focused(initiallyFocused.projectedValue))

            XCTAssertTrue(focusedNode.isFocused)
            XCTAssertTrue(initiallyFocused.wrappedValue)
        }
    }

    func testFocusStateOptionalBindingSynchronizesRetainedFocus() async {
        enum Field: Hashable {
            case name
            case email
        }

        await MainActor.run {
            let focusState = FocusState<Field?>(wrappedValue: .name)
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 800, height: 600) },
                invalidateHandler: {}
            )
            let nameNode = Text("NAME")
                .focused(focusState.projectedValue, equals: Field.name)
                .makeComponent(context: context)
                .makeNode(runtime: runtime)
            let emailNode = Text("EMAIL")
                .focused(focusState.projectedValue, equals: Field.email)
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            XCTAssertTrue(nameNode.isFocused)
            XCTAssertFalse(emailNode.isFocused)
            XCTAssertEqual(focusState.wrappedValue, .name)

            runtime.requestFocus(emailNode)

            XCTAssertFalse(nameNode.isFocused)
            XCTAssertTrue(emailNode.isFocused)
            XCTAssertEqual(focusState.wrappedValue, .email)

            runtime.keyboardFocusDidLeaveWindow()

            XCTAssertNil(focusState.wrappedValue)
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

    func testFocusEnvironmentValuesCanBeReadAndOverridden() async {
        await MainActor.run {
            struct FocusEnvironmentReader: View {
                @Environment(\.isFocused) var isFocused
                @Environment(\.isFocusEffectEnabled) var isFocusEffectEnabled

                var body: some View {
                    Text(
                        "\(isFocused ? "FOCUSED" : "UNFOCUSED") "
                            + "\(isFocusEffectEnabled ? "FOCUSFX" : "NOFOCUSFX")"
                    )
                }
            }

            let defaultNode = makeNode(FocusEnvironmentReader())
            let focusedNode = makeNode(
                FocusEnvironmentReader()
                    .environment(\.isFocused, true)
            )
            let disabledEffectNode = makeNode(
                VStack {
                    FocusEnvironmentReader()
                    FocusEnvironmentReader()
                        .focusEffectDisabled()
                    FocusEnvironmentReader()
                        .focusEffectDisabled(false)
                }
            )

            XCTAssertEqual(defaultNode.text, "UNFOCUSED FOCUSFX")
            XCTAssertEqual(focusedNode.text, "FOCUSED FOCUSFX")
            XCTAssertEqual(disabledEffectNode.children[0].text, "UNFOCUSED FOCUSFX")
            XCTAssertEqual(disabledEffectNode.children[1].text, "UNFOCUSED NOFOCUSFX")
            XCTAssertEqual(disabledEffectNode.children[2].text, "UNFOCUSED FOCUSFX")
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

    func testOnDeleteCommandHandlesBackspaceAndForwardDelete() async {
        await MainActor.run {
            var deleteCount = 0
            var forwardedKeys: [KeyboardKey?] = []
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onDeleteCommand {
                    deleteCount += 1
                }
            )

            XCTAssertTrue(node.isFocusable)
            XCTAssertTrue(node.isHitTestVisible)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.deleteForward.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(deleteCount, 2)
            XCTAssertEqual(forwardedKeys, [.enter])
        }
    }

    func testOnMoveCommandMapsArrowKeysAndPreservesOtherKeys() async {
        await MainActor.run {
            var directions: [MoveCommandDirection] = []
            var forwardedKeys: [KeyboardKey?] = []
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onMoveCommand { direction in
                    directions.append(direction)
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))

            XCTAssertEqual(directions, [.up, .down, .left, .right])
            XCTAssertEqual(forwardedKeys, [.space])
        }
    }

    func testOnExitCommandHandlesEscapeAndPreservesOtherKeys() async {
        await MainActor.run {
            var exitCount = 0
            var forwardedKeys: [KeyboardKey?] = []
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onExitCommand {
                    exitCount += 1
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(exitCount, 1)
            XCTAssertEqual(forwardedKeys, [.enter])

            runtime.root.addChild(node)
            runtime.requestFocus(node)
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))

            XCTAssertEqual(exitCount, 2)
        }
    }

    func testPageCommandStepsIntegerBindingWithinBounds() async {
        await MainActor.run {
            var page = 2
            var forwardedKeys: [KeyboardKey?] = []
            let binding = Binding<Int>(
                get: { page },
                set: { page = $0 }
            )
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .pageCommand(value: binding, in: 0...4, step: 2)
            )

            XCTAssertTrue(node.isFocusable)
            XCTAssertTrue(node.isHitTestVisible)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.pageDown.rawValue))
            XCTAssertEqual(page, 4)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.pageDown.rawValue))
            XCTAssertEqual(page, 4)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.pageUp.rawValue))
            XCTAssertEqual(page, 2)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.pageUp.rawValue))
            XCTAssertEqual(page, 0)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.pageUp.rawValue))
            XCTAssertEqual(page, 0)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            XCTAssertEqual(forwardedKeys, [.enter])
        }
    }

    func testOnPlayPauseCommandHandlesMediaKeyAndPreservesOtherKeys() async {
        await MainActor.run {
            var playPauseCount = 0
            var forwardedKeys: [KeyboardKey?] = []
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onPlayPauseCommand {
                    playPauseCount += 1
                }
            )

            XCTAssertTrue(node.isFocusable)
            XCTAssertTrue(node.isHitTestVisible)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.mediaPlayPause.rawValue))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))

            XCTAssertEqual(playPauseCount, 1)
            XCTAssertEqual(forwardedKeys, [.space])
        }
    }

    func testAccessibilityModifiersMapToRetainedMetadata() async {
        await MainActor.run {
            var actions: [String] = []
            let node = makeNode(
                Text("SAVE")
                    .accessibilityLabel(Text("Save changes"))
                    .accessibilityValue(LocalizedStringKey("Ready"))
                    .accessibilityHint("Writes the current document")
                    .accessibilityIdentifier("save-button")
                    .accessibilityAddTraits([.isButton, .isHeader, .isSelected])
                    .accessibilityRemoveTraits(.isHeader)
                    .accessibilityElement(children: .combine)
                    .accessibilitySortPriority(4.5)
                    .accessibilityAction(.magicTap) { actions.append("magic") }
                    .accessibilityAction(named: Text("Archive")) { actions.append("archive") }
                    .accessibilityAction(named: LocalizedStringKey("Flag")) { actions.append("flag") }
                    .accessibilityHidden(true)
                    .accessibilityPrefersCrossFadeTransitions()
                    .accessibilityShowLargeContentViewer()
            )

            XCTAssertEqual(node.accessibilityLabel, "Save changes")
            XCTAssertEqual(node.accessibilityValue, "Ready")
            XCTAssertEqual(node.accessibilityHint, "Writes the current document")
            XCTAssertEqual(node.accessibilityIdentifier, "save-button")
            XCTAssertEqual(node.accessibilityTraits, [.isButton, .isSelected])
            XCTAssertEqual(node.accessibilityChildBehavior, .combine)
            XCTAssertEqual(node.accessibilitySortPriority, 4.5)
            XCTAssertEqual(node.accessibilityActions.count, 3)
            XCTAssertEqual(node.accessibilityActions[0].kind, .magicTap)
            XCTAssertNil(node.accessibilityActions[0].name)
            XCTAssertEqual(node.accessibilityActions[1].name, "Archive")
            XCTAssertNil(node.accessibilityActions[1].kind)
            XCTAssertEqual(node.accessibilityActions[2].name, "Flag")
            XCTAssertTrue(node.isAccessibilityHidden)
            XCTAssertEqual(node.accessibilityPrefersCrossFadeTransitions, true)
            XCTAssertEqual(node.accessibilityShowLargeContentViewer, true)

            for action in node.accessibilityActions {
                action.handler()
            }
            XCTAssertEqual(actions, ["magic", "archive", "flag"])

            let defaultElementNode = makeNode(Text("ROW").accessibilityElement())
            XCTAssertEqual(defaultElementNode.accessibilityChildBehavior, .ignore)

            var defaultActionCount = 0
            let defaultActionNode = makeNode(
                Text("GO")
                    .accessibilityAction {
                        defaultActionCount += 1
                    }
            )
            XCTAssertEqual(defaultActionNode.accessibilityActions.first?.kind, .default)
            defaultActionNode.accessibilityActions.first?.handler()
            XCTAssertEqual(defaultActionCount, 1)
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
            XCTAssertEqual(node.clipFillStyle, RetainedClipFillStyle(eoFill: false, antialiased: true))
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
            XCTAssertEqual(rectangleNode.clipFillStyle, RetainedClipFillStyle(eoFill: false, antialiased: true))
            XCTAssertEqual(rectangleNode.children[0].text, "RECT")
            XCTAssertTrue(roundedNode.clipsToBounds)
            XCTAssertEqual(roundedNode.cornerRadius, 6)
            XCTAssertEqual(roundedNode.clipFillStyle, RetainedClipFillStyle(eoFill: true, antialiased: false))
            XCTAssertEqual(roundedNode.children[0].text, "ROUND")
        }
    }

    func testClipShapeFallsBackToRectangularClipForCustomShape() async {
        struct CustomClipShape: Shape {
            func path(in rect: Rect) -> Path {
                var p = Path()
                p.addRect(rect)
                return p
            }
        }

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
        struct CustomContentShape: Shape {
            func path(in rect: Rect) -> Path {
                var p = Path()
                p.addRect(rect)
                return p
            }
        }

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
            XCTAssertEqual(
                plainNode.contentShapes,
                [
                    RetainedContentShape(
                        kinds: .interaction,
                        style: .rectangle
                    )
                ]
            )
            XCTAssertTrue(gestureNode.isHitTestVisible)
            XCTAssertEqual(gestureNode.text, "TAP")
            XCTAssertEqual(
                gestureNode.contentShapes,
                [
                    RetainedContentShape(
                        kinds: .interaction,
                        style: .ellipse,
                        eoFill: true
                    )
                ]
            )
            XCTAssertTrue(kindNode.isHitTestVisible)
            XCTAssertEqual(kindNode.text, "KIND")
            XCTAssertEqual(
                kindNode.contentShapes,
                [
                    RetainedContentShape(
                        kinds: [.interaction, .hoverEffect, .accessibility],
                        style: .capsule,
                        eoFill: true
                    )
                ]
            )
            XCTAssertEqual(customNode.text, "CUSTOM")
            XCTAssertEqual(
                customNode.contentShapes,
                [
                    RetainedContentShape(
                        kinds: .dragPreview,
                        style: .rectangle
                    )
                ]
            )
        }
    }

    func testContentShapeInteractionConstrainsRetainedPointerHitTesting() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 120, height: 120) },
                invalidateHandler: {}
            )
            var tapCount = 0

            let node = Text("TAP")
                .frame(width: 80, height: 80)
                .contentShape(Circle())
                .onTapGesture {
                    tapCount += 1
                }
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 120, height: 120))
            _ = runtime.renderFrame()

            runtime.pointerDown(at: Point(x: 0, y: 0))
            runtime.pointerUp(at: Point(x: 0, y: 0))
            XCTAssertEqual(tapCount, 0)

            runtime.pointerDown(at: Point(x: 40, y: 40))
            runtime.pointerUp(at: Point(x: 40, y: 40))
            XCTAssertEqual(tapCount, 1)
        }
    }

    func testCornerRadiusAcceptsAntialiasedArgumentAndClipsBounds() async {
        await MainActor.run {
            let node = makeNode(Text("ROUND").cornerRadius(5, antialiased: false))

            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.cornerRadius, 5)
            XCTAssertEqual(node.clipFillStyle, RetainedClipFillStyle(eoFill: false, antialiased: false))
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
            XCTAssertNil(storedColorNode.borderGradient)
            XCTAssertEqual(storedColorNode.borderWidth, 3)
            XCTAssertEqual(storedColorNode.cornerRadius, 7)
            XCTAssertEqual(storedColorNode.children[0].text, "BORDER")

            XCTAssertEqual(storedGradientNode.borderColor, gradient.startColor)
            XCTAssertEqual(storedGradientNode.borderGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
            XCTAssertEqual(storedGradientNode.borderWidth, 4)
            XCTAssertEqual(storedGradientNode.cornerRadius, 9)
            XCTAssertEqual(storedGradientNode.children[0].text, "GRADIENT")

            XCTAssertEqual(gradientNode.borderColor, gradient.startColor)
            XCTAssertEqual(gradientNode.borderGradient, .linear(SwiftWindowsGraphics.LinearGradient(gradient)))
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

    func testNamespaceAndMatchedGeometryEffectMapToRetainedMetadata() async {
        await MainActor.run {
            struct MatchedGeometryView: View {
                @Namespace private var namespace

                var body: some View {
                    Text("CARD")
                        .matchedGeometryEffect(
                            id: "card",
                            in: namespace,
                            properties: .position,
                            anchor: .topLeading,
                            isSource: false
                        )
                }
            }

            let node = makeNode(MatchedGeometryView())
            let effect = node.matchedGeometryEffect

            XCTAssertNotNil(effect)
            XCTAssertEqual(effect?.elementID, "card")
            XCTAssertEqual(effect?.properties, MatchedGeometryProperties.position.rawValue)
            XCTAssertEqual(effect?.anchor, Point(x: 0, y: 0))
            XCTAssertEqual(effect?.isSource, false)
            XCTAssertFalse(effect?.namespaceID.isEmpty ?? true)
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

    func testFlipsForRightToLeftLayoutDirectionMapsToRetainedTransform() async {
        await MainActor.run {
            let leftToRightNode = makeNode(
                Image(systemName: "chevron.right")
                    .flipsForRightToLeftLayoutDirection(true)
                    .environment(\.layoutDirection, .leftToRight)
            )
            let rightToLeftNode = makeNode(
                Image(systemName: "chevron.right")
                    .flipsForRightToLeftLayoutDirection(true)
                    .environment(\.layoutDirection, .rightToLeft)
            )
            let disabledNode = makeNode(
                Image(systemName: "chevron.right")
                    .flipsForRightToLeftLayoutDirection(false)
                    .environment(\.layoutDirection, .rightToLeft)
            )
            let scaledRightToLeftNode = makeNode(
                Image(systemName: "chevron.right")
                    .scaleEffect(2)
                    .flipsForRightToLeftLayoutDirection(true)
                    .environment(\.layoutDirection, .rightToLeft)
            )

            XCTAssertEqual(leftToRightNode.transform, .identity)
            XCTAssertEqual(rightToLeftNode.transform, Transform2D.scale(x: -1, y: 1))
            XCTAssertEqual(disabledNode.transform, .identity)
            XCTAssertEqual(scaledRightToLeftNode.transform, Transform2D.scale(x: -2, y: 2))
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

    func testProjectionAndAnchoredTransformEffectsMapToRetainedTransform() async {
        await MainActor.run {
            let translation = CGAffineTransform(translationX: 8, y: 10)
            let projection = ProjectionTransform(CGAffineTransform(scaleX: 2, y: 3))
            let scaledFrom2DAnchor = makeNode(Text("SCALE").scaleEffect(1.5, anchor: UnitPoint.topLeading))
            let scaledFrom3DAnchor = makeNode(Text("DEPTH").scaleEffect(x: 2, y: 3, z: 4, anchor: .front))
            let rotatedFromAnchor = makeNode(Text("TURN").rotationEffect(.degrees(180), anchor: .bottomTrailing))
            let rotatedFrom3DRotation = makeNode(
                Text("ROTATION3D")
                    .rotation3DEffect(Rotation3D(angle: .degrees(45), axis: .z), anchor: .back)
            )
            let transformed3DNode = makeNode(
                Text("TRANSFORM3D")
                    .transform3DEffect(AffineTransform3D(translation: Size3D(width: 1, height: 2, depth: 3)))
            )
            let affineNode = makeNode(Text("MOVE").transformEffect(translation))
            let projectionNode = makeNode(Text("PROJECT").projectionEffect(projection))

            XCTAssertEqual(translation.translatedBy(x: 1, y: 2), CGAffineTransform(translationX: 9, y: 12))
            XCTAssertEqual(translation.scaledBy(x: 2, y: 2).tx, 16)
            XCTAssertEqual(CGAffineTransform(), .identity)
            XCTAssertEqual(CGAffineTransform.identity, CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
            XCTAssertEqual(ProjectionTransform().affineTransform, .identity)
            XCTAssertEqual(UnitPoint3D(.topLeading, z: 0.25), UnitPoint3D(x: 0, y: 0, z: 0.25))
            XCTAssertEqual(scaledFrom2DAnchor.transform, Transform2D.scale(x: 1.5, y: 1.5))
            XCTAssertEqual(scaledFrom3DAnchor.transform, Transform2D.scale(x: 2, y: 3))
            XCTAssertEqual(rotatedFromAnchor.transform, Transform2D(rotation: .pi))
            XCTAssertEqual(rotatedFrom3DRotation.transform, Transform2D(rotation: .pi / 4))
            XCTAssertEqual(
                transformed3DNode.visualEffects,
                ["transform3DEffect(translation:1.0,2.0,3.0,scale:1.0,1.0,1.0,rotation:nil)"])
            XCTAssertEqual(affineNode.transform, Transform2D.translation(x: 8, y: 10))
            XCTAssertEqual(projectionNode.transform, Transform2D.scale(x: 2, y: 3))
        }
    }

    func testRotation3DEffectUsesRetainedZAxisFallback() async {
        await MainActor.run {
            let tupleZNode = makeNode(
                Text("Z")
                    .rotation3DEffect(
                        .degrees(90),
                        axis: (x: 0, y: 0, z: 1),
                        anchor: .center,
                        anchorZ: 2,
                        perspective: 0.5
                    )
            )
            let namedZNode = makeNode(
                Text("NAMED")
                    .rotation3DEffect(.degrees(45), axis: .z, anchor: .center)
            )
            let invertedZNode = makeNode(
                Text("INVERTED")
                    .rotation3DEffect(.degrees(90), axis: RotationAxis3D(x: 0, y: 0, z: -1))
            )
            let xAxisNode = makeNode(
                Text("X")
                    .rotation3DEffect(.degrees(90), axis: .x)
            )
            let perspectiveZNode = makeNode(
                Text("PERSPECTIVE")
                    .perspectiveRotationEffect(
                        .degrees(90),
                        axis: (x: 0, y: 0, z: 1),
                        anchor: .center,
                        anchorZ: 2,
                        perspective: 0.5
                    )
            )
            let perspectiveXAxisNode = makeNode(
                Text("PERSPECTIVE X")
                    .perspectiveRotationEffect(.degrees(90), axis: (x: 1, y: 0, z: 0))
            )

            XCTAssertEqual(tupleZNode.transform, Transform2D(rotation: .pi / 2))
            XCTAssertEqual(namedZNode.transform, Transform2D(rotation: .pi / 4))
            XCTAssertEqual(invertedZNode.transform, Transform2D(rotation: -.pi / 2))
            XCTAssertEqual(xAxisNode.transform, .identity)
            XCTAssertEqual(perspectiveZNode.transform, Transform2D(rotation: .pi / 2))
            XCTAssertEqual(perspectiveXAxisNode.transform, .identity)
        }
    }

    /// `.blur()` is a *content* blur: the subtree renders and the result is
    /// blurred once. It must not land on `blurRadius`, which is the node's
    /// own backdrop effect — that field on a `Text` would blur what is
    /// behind the label and leave the glyphs sharp.
    func testBlurModifierMapsToRetainedNodeContentBlurRadius() async {
        await MainActor.run {
            let blurredNode = makeNode(Text("SOFT").blur(radius: 12, opaque: true))
            let clampedNode = makeNode(Text("SHARP").blur(radius: -3))

            XCTAssertEqual(blurredNode.contentBlurRadius, 12)
            XCTAssertEqual(blurredNode.contentBlurOpaque, true)
            XCTAssertEqual(blurredNode.blurRadius, 0, "a content blur must not become a backdrop blur")
            XCTAssertEqual(clampedNode.contentBlurRadius, 0)
            XCTAssertEqual(clampedNode.contentBlurOpaque, false)
        }
    }

    func testPhaseAnimatorCompatibilityRendersInitialPhaseAndRetainsMetadata() async {
        await MainActor.run {
            let animatedNode = makeNode(
                Text("PHASE")
                    .phaseAnimator(["initial", "expanded"]) { content, phase in
                        content
                            .opacity(phase == "initial" ? 0.4 : 1)
                    } animation: { phase in
                        phase == "initial" ? .linear(duration: 0.2) : .easeInOut(duration: 0.5)
                    }
            )
            let triggeredNode = makeNode(
                Text("TRIGGER")
                    .phaseAnimator([1, 2, 3], trigger: true) { content, phase in
                        content
                            .opacity(Double(phase) / 10)
                    } animation: { _ in
                        nil
                    }
            )
            let emptyNode = makeNode(
                Text("EMPTY")
                    .phaseAnimator([String]()) { content, _ in
                        content.opacity(0.1)
                    }
            )

            XCTAssertEqual(animatedNode.text, "PHASE")
            XCTAssertEqual(animatedNode.opacity, 0.4)
            XCTAssertEqual(
                animatedNode.visualEffects,
                ["phaseAnimator(phase:initial,hasAdditionalPhases:true,animation:linear:0.2)"]
            )
            XCTAssertEqual(triggeredNode.text, "TRIGGER")
            XCTAssertEqual(triggeredNode.opacity, 0.1)
            XCTAssertEqual(
                triggeredNode.visualEffects,
                ["phaseAnimator(phase:1,hasAdditionalPhases:true,trigger:Bool:true,animation:nil)"]
            )
            XCTAssertEqual(emptyNode.text, "EMPTY")
            XCTAssertEqual(emptyNode.opacity, 1)
            XCTAssertEqual(
                emptyNode.visualEffects,
                ["phaseAnimator(phase:nil,hasAdditionalPhases:false,animation:nil)"]
            )
        }
    }

    func testPhaseAnimatorContainerRendersInitialPhaseAndRetainsMetadata() async {
        await MainActor.run {
            let animatedNode = makeNode(
                PhaseAnimator(["small", "large"]) { phase in
                    Text(phase == "small" ? "SMALL" : "LARGE")
                        .opacity(phase == "small" ? 0.3 : 1)
                } animation: { phase in
                    phase == "small" ? .easeOut(duration: 0.15) : nil
                }
            )
            let triggeredNode = makeNode(
                PhaseAnimator([2, 4], trigger: "refresh") { phase in
                    Text("PHASE \(phase)")
                } animation: { _ in
                    .linear(duration: 0.1)
                }
            )
            let emptyNode = makeNode(
                PhaseAnimator([Int]()) { phase in
                    Text("PHASE \(phase)")
                }
            )

            XCTAssertEqual(animatedNode.text, "SMALL")
            XCTAssertEqual(animatedNode.opacity, 0.3)
            XCTAssertEqual(
                animatedNode.visualEffects,
                ["phaseAnimator(phase:small,hasAdditionalPhases:true,animation:easeOut:0.15)"]
            )
            XCTAssertEqual(triggeredNode.text, "PHASE 2")
            XCTAssertEqual(
                triggeredNode.visualEffects,
                ["phaseAnimator(phase:2,hasAdditionalPhases:true,trigger:String:refresh,animation:linear:0.1)"]
            )
            XCTAssertNil(emptyNode.text)
            XCTAssertEqual(
                emptyNode.visualEffects,
                ["phaseAnimator(phase:nil,hasAdditionalPhases:false,animation:nil)"]
            )
        }
    }

    func testPhaseAnimatorAdvancesPhaseOnRebuildAfterDurationElapsed() async {
        await MainActor.run {
            let view = PhaseAnimator(["a", "b", "c"]) { phase in
                Text(phase)
            } animation: { _ in
                .linear(duration: 0.1)
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )

            let firstNode = view.makeComponent(context: context).makeNode(runtime: runtime)
            firstNode.frame = Rect(origin: .zero, size: Size(width: 200, height: 400))
            runtime.root.addChild(firstNode)
            XCTAssertEqual(firstNode.text, "a")
            XCTAssertEqual(firstNode.phaseAnimatorState?.currentPhaseIndex, 0)

            guard var state = firstNode.phaseAnimatorState else {
                return XCTFail("Expected phase animator state")
            }
            state.phaseStartTime = Win32Window.currentTimestampSeconds() - 0.15
            firstNode.phaseAnimatorState = state

            let secondNode = view.makeComponent(context: context).makeNode(runtime: runtime)
            secondNode.frame = Rect(origin: .zero, size: Size(width: 200, height: 400))
            runtime.root.addChild(secondNode)
            XCTAssertEqual(secondNode.text, "b")
            XCTAssertEqual(secondNode.phaseAnimatorState?.currentPhaseIndex, 1)
        }
    }

    func testPhaseAnimatorTriggerChangeResetsPhaseIndex() async {
        await MainActor.run {
            let view = PhaseAnimator([1, 2], trigger: "old") { phase in
                Text("\(phase)")
            } animation: { _ in
                .linear(duration: 0.2)
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )

            let firstNode = view.makeComponent(context: context).makeNode(runtime: runtime)
            firstNode.frame = Rect(origin: .zero, size: Size(width: 200, height: 400))
            runtime.root.addChild(firstNode)
            firstNode.phaseAnimatorState?.currentPhaseIndex = 1
            firstNode.phaseAnimatorState?.previousTrigger = "old"

            let newView = PhaseAnimator([1, 2], trigger: "new") { phase in
                Text("\(phase)")
            } animation: { _ in
                .linear(duration: 0.2)
            }

            let secondNode = newView.makeComponent(context: context).makeNode(runtime: runtime)
            secondNode.frame = Rect(origin: .zero, size: Size(width: 200, height: 400))
            runtime.root.addChild(secondNode)
            XCTAssertEqual(secondNode.text, "1")
            XCTAssertEqual(secondNode.phaseAnimatorState?.currentPhaseIndex, 0)
        }
    }

    func testPhaseAnimatorEmptyPhasesRendersNoContent() async {
        await MainActor.run {
            let view = PhaseAnimator([String]()) { phase in
                Text(phase)
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )

            let node = view.makeComponent(context: context).makeNode(runtime: runtime)
            XCTAssertEqual(node.children.count, 0)
            if case .absolute = node.layoutMode {
                // expected
            } else {
                XCTFail("Expected absolute layout mode, got \(node.layoutMode)")
            }
        }
    }

    func testAnyTransitionCompatibilityModifierPreservesRenderedContent() async {
        await MainActor.run {
            let combined = AnyTransition.opacity
                .combined(with: .move(edge: .leading))
            let asymmetric = AnyTransition.asymmetric(
                insertion: .push(from: .trailing),
                removal: .offset(x: 12, y: -4)
            )
            let scale = AnyTransition.scale(scale: 0.8, anchor: .topLeading)
            let sizedOffset = AnyTransition.offset(CGSize(width: 3, height: 4))

            let node = makeNode(
                VStack {
                    Text("FADE").transition(combined)
                    Text("SWAP").transition(asymmetric)
                    Text("GROW").transition(scale)
                    Text("SHIFT").transition(sizedOffset)
                    Text("STAY").transition(.identity)
                    Text("SLIDE").transition(.slide)
                    Text("SCALE").transition(.scale)
                }
            )

            XCTAssertNotEqual(combined, .identity)
            XCTAssertEqual(allTexts(in: node), ["FADE", "SWAP", "GROW", "SHIFT", "STAY", "SLIDE", "SCALE"])
        }
    }

    func testAnyTransitionModifierFactoryProducesModifierKind() async {
        await MainActor.run {
            struct TestModifier: ViewModifier {
                func body(content: Content) -> some View {
                    content
                }
            }
            let transition = AnyTransition.modifier(active: TestModifier(), identity: TestModifier())
            if case .modifier(let activeType, let identityType) = transition.kind {
                XCTAssertEqual(activeType, ObjectIdentifier(TestModifier.self))
                XCTAssertEqual(identityType, ObjectIdentifier(TestModifier.self))
            } else {
                XCTFail("Expected .modifier kind")
            }
        }
    }

    func testContentTransitionCompatibilityPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct ContentTransitionReaderView: View {
                @Environment(\.contentTransition) var contentTransition
                @Environment(\.contentTransitionAddsDrawingGroup) var addsDrawingGroup

                var body: some View {
                    Text(
                        contentTransition == .numericText(countsDown: true) && addsDrawingGroup
                            ? "COUNTDOWN"
                            : contentTransition == .interpolate
                                ? "INTERPOLATE"
                                : contentTransition == .symbolEffect
                                    ? "SYMBOL"
                                    : contentTransition == .identity
                                        ? "IDENTITY"
                                        : "OTHER"
                    )
                }
            }

            let defaultNode = makeNode(ContentTransitionReaderView())
            let countdownNode = makeNode(
                ContentTransitionReaderView()
                    .contentTransition(.numericText(countsDown: true))
                    .contentTransitionAddsDrawingGroup(true)
            )
            let interpolateNode = makeNode(ContentTransitionReaderView().contentTransition(.interpolate))
            let symbolNode = makeNode(ContentTransitionReaderView().contentTransition(.symbolEffect))
            let valueNode = makeNode(Text("42").contentTransition(.numericText(value: 42)))
            let opacityNode = makeNode(Text("FADE").contentTransition(.opacity))

            XCTAssertEqual(defaultNode.text, "IDENTITY")
            XCTAssertEqual(countdownNode.text, "COUNTDOWN")
            XCTAssertEqual(interpolateNode.text, "INTERPOLATE")
            XCTAssertEqual(symbolNode.text, "SYMBOL")
            XCTAssertEqual(valueNode.text, "42")
            XCTAssertEqual(opacityNode.text, "FADE")
        }
    }

    func testSymbolEffectCompatibilityModifiersPreserveRenderedContent() async {
        await MainActor.run {
            let pulse = PulseSymbolEffect().wholeSymbol
            let variableColor = VariableColorSymbolEffect().reversing
            let options =
                SymbolEffectOptions
                .repeat(3)
                .speed(1.4)
            let contentTransition = ContentTransition.symbolEffect(.replace, options: .nonRepeating)

            let node = makeNode(
                VStack {
                    Label("WIFI", systemImage: "wifi")
                        .symbolEffect(variableColor, options: .repeating, isActive: true)
                    Image(systemName: "bell")
                        .symbolEffect(pulse, options: options, value: 2)
                    Label("QUIET", systemImage: "bell.slash")
                        .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic), value: true)
                        .symbolEffectsRemoved(false)
                    Text("REPLACE")
                        .contentTransition(contentTransition)
                }
            )

            XCTAssertEqual(pulse.configuration.effect, .pulse)
            XCTAssertEqual(pulse.configuration.scope, .wholeSymbol)
            XCTAssertEqual(variableColor.configuration.effect, .variableColor)
            XCTAssertTrue(variableColor.configuration.reverses)
            XCTAssertEqual(options.repeatPreference, .count(3))
            XCTAssertEqual(options.speedMultiplier, 1.4)
            XCTAssertTrue(allTexts(in: node).contains("WIFI"))
            XCTAssertTrue(allTexts(in: node).contains("QUIET"))
            XCTAssertTrue(allTexts(in: node).contains("REPLACE"))
        }
    }

    func testSensoryFeedbackCompatibilityModifiersPreserveRenderedContent() async {
        await MainActor.run {
            let impact = SensoryFeedback.impact(weight: .heavy, intensity: 0.8)
            let flexibleImpact = SensoryFeedback.impact(flexibility: .soft, intensity: 0.4)
            let press = SensoryFeedback.press(.depth)
            let release = SensoryFeedback.release(.stop)
            let selection = SensoryFeedback.selection(.maximum)

            let node = makeNode(
                VStack {
                    Text("SAVE").sensoryFeedback(.success, trigger: 1)
                    Text("WARN").sensoryFeedback(.warning, trigger: false) { old, new in old != new }
                    Text("ERROR").sensoryFeedback(trigger: "error") { old, new in
                        old == new ? nil : .error
                    }
                    Text("IMPACT").sensoryFeedback(impact, trigger: 2)
                    Text("FLEX").sensoryFeedback(flexibleImpact, trigger: 3)
                    Text("PRESS").sensoryFeedback(press, trigger: 4)
                    Text("RELEASE").sensoryFeedback(release, trigger: 5)
                    Text("SELECT").sensoryFeedback(selection, trigger: 6)
                }
            )

            XCTAssertEqual(SensoryFeedback.Flexibility.soft, .soft)
            XCTAssertEqual(SensoryFeedback.Weight.heavy, .heavy)
            XCTAssertEqual(SensoryFeedback.PressFeedback.depth, .depth)
            XCTAssertEqual(SensoryFeedback.ReleaseFeedback.stop, .stop)
            XCTAssertEqual(SensoryFeedback.SelectionFeedback.maximum, .maximum)
            XCTAssertEqual(
                allTexts(in: node),
                ["SAVE", "WARN", "ERROR", "IMPACT", "FLEX", "PRESS", "RELEASE", "SELECT"]
            )
        }
    }

    func testTransactionCompatibilityShimsExecuteBodiesAndTransforms() async {
        await MainActor.run {
            var value = 0
            var transaction = Transaction(animation: .easeIn(duration: 0.2))
            transaction.disablesAnimations = true
            transaction.isContinuous = true
            transaction.scrollTargetAnchor = .bottom
            transaction.tracksVelocity = true
            var transactionCompletionCount = 0
            transaction.addAnimationCompletion(criteria: .removed) {
                transactionCompletionCount += 1
            }

            let result = withTransaction(transaction) {
                value = 7
                return value + 1
            }

            let anchoredResult = withTransaction(\.scrollTargetAnchor, .top) {
                value += 2
                return value
            }

            var animationCompletionCount = 0
            let animationResult = withAnimation(.easeOut(duration: 0.15), completionCriteria: .removed) {
                XCTAssertEqual(currentTransaction?.animation?.duration, 0.15)
                withAnimation(nil) {
                    XCTAssertNotNil(currentTransaction, "an explicit nil animation is still a transaction")
                    XCTAssertNil(currentTransaction?.animation)
                    XCTAssertNil(currentAnimationTransaction)
                }
                XCTAssertEqual(currentTransaction?.animation?.duration, 0.15)
                value += 3
                return value
            } completion: {
                animationCompletionCount += 1
            }

            var didTransform = false
            var transformedAnchor: UnitPoint?
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            host.setContent(
                Text("TX")
                    .transaction { transaction in
                        transaction.disablesAnimations = true
                        transaction.isContinuous = true
                        transaction.scrollTargetAnchor = .center
                        transaction.tracksVelocity = true
                        transformedAnchor = transaction.scrollTargetAnchor
                        didTransform = true
                    }
                    .makeComponent(context: context)
            )
            let node = runtime.root.children[0]

            XCTAssertEqual(result, 8)
            XCTAssertEqual(anchoredResult, 9)
            XCTAssertEqual(animationResult, 12)
            XCTAssertEqual(value, 12)
            XCTAssertEqual(transactionCompletionCount, 1)
            XCTAssertEqual(animationCompletionCount, 1)
            XCTAssertTrue(didTransform)
            XCTAssertTrue(transaction.isContinuous)
            XCTAssertEqual(transaction.scrollTargetAnchor, .bottom)
            XCTAssertTrue(transaction.tracksVelocity)
            XCTAssertEqual(transformedAnchor, .center)
            XCTAssertEqual(AnimationCompletionCriteria.logicallyComplete, .logicallyComplete)
            XCTAssertEqual(AnimationCompletionCriteria.removed, .removed)
            XCTAssertNotEqual(AnimationCompletionCriteria.logicallyComplete, .removed)
            XCTAssertEqual(node.text, "TX")
        }
    }

    func testAccessibilityPreferenceEnvironmentValuesCanBeReadAndOverrideAnimation() async {
        await MainActor.run {
            struct AccessibilityPreferenceReaderView: View {
                @Environment(\.accessibilityAssistiveAccessEnabled) var assistiveAccessEnabled
                @Environment(\.accessibilityDimFlashingLights) var dimFlashingLights
                @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
                @Environment(\.accessibilityEnabled) var accessibilityEnabled
                @Environment(\.accessibilityInvertColors) var invertColors
                @Environment(\.accessibilityLargeContentViewerEnabled) var largeContentViewerEnabled
                @Environment(\.accessibilityPlayAnimatedImages) var playAnimatedImages
                @Environment(\.accessibilityPrefersHeadAnchorAlternative) var prefersHeadAnchorAlternative
                @Environment(\.accessibilityQuickActionsEnabled) var quickActionsEnabled
                @Environment(\.accessibilityReduceHighlightingEffects) var reduceHighlightingEffects
                @Environment(\.accessibilityReduceMotion) var reduceMotion
                @Environment(\.accessibilityReduceTransparency) var reduceTransparency
                @Environment(\.accessibilityShowButtonShapes) var showButtonShapes
                @Environment(\.accessibilityShowBorders) var showBorders
                @Environment(\.accessibilitySwitchControlEnabled) var switchControlEnabled
                @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled

                var body: some View {
                    Text(
                        assistiveAccessEnabled
                            && dimFlashingLights
                            && differentiateWithoutColor
                            && accessibilityEnabled
                            && invertColors
                            && largeContentViewerEnabled
                            && !playAnimatedImages
                            && prefersHeadAnchorAlternative
                            && quickActionsEnabled
                            && reduceHighlightingEffects
                            && reduceMotion
                            && reduceTransparency
                            && showButtonShapes
                            && showBorders
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
                    .environment(\.accessibilityAssistiveAccessEnabled, true)
                    .environment(\.accessibilityDimFlashingLights, true)
                    .environment(\.accessibilityDifferentiateWithoutColor, true)
                    .environment(\.accessibilityEnabled, true)
                    .environment(\.accessibilityInvertColors, true)
                    .environment(\.accessibilityLargeContentViewerEnabled, true)
                    .environment(\.accessibilityPlayAnimatedImages, false)
                    .environment(\.accessibilityPrefersHeadAnchorAlternative, true)
                    .environment(\.accessibilityQuickActionsEnabled, true)
                    .environment(\.accessibilityReduceHighlightingEffects, true)
                    .environment(\.accessibilityReduceMotion, true)
                    .environment(\.accessibilityReduceTransparency, true)
                    .environment(\.accessibilityShowButtonShapes, true)
                    .environment(\.accessibilityShowBorders, true)
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
                XCTAssertEqual(
                    stackLayout,
                    .vertical(spacing: MacOSControlMetrics.Layout.defaultStackSpacing, alignment: .trailing)
                )
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

    func testWindowSceneActionsCanForwardTypedPayloadsToInjectedHandlers() async {
        await MainActor.run {
            struct WindowPayloadActionView: View {
                @Environment(\.openWindow) var openWindow
                @Environment(\.dismissWindow) var dismissWindow

                var body: some View {
                    VStack {
                        Button("OPEN PAYLOADS") {
                            openWindow(id: "detail", value: 7)
                            openWindow(value: "payload")
                        }
                        Button("DISMISS PAYLOADS") {
                            dismissWindow(id: "detail", value: 9)
                            dismissWindow(value: "closed")
                        }
                    }
                }
            }

            var opened: [WindowActionPayload] = []
            var dismissed: [WindowActionPayload] = []
            let node = makeNode(
                WindowPayloadActionView()
                    .environment(
                        \.openWindow,
                        OpenWindowAction(payloadHandler: { payload in
                            opened.append(payload)
                        })
                    )
                    .environment(
                        \.dismissWindow,
                        DismissWindowAction(payloadHandler: { payload in
                            dismissed.append(payload)
                        })
                    )
            )

            let focusableNodes = focusableNodes(in: node)
            XCTAssertEqual(focusableNodes.count, 2)

            focusableNodes[0].onActivate?()
            focusableNodes[1].onActivate?()

            XCTAssertEqual(
                opened,
                [
                    WindowActionPayload(id: "detail", value: AnyHashable(7)),
                    WindowActionPayload(value: AnyHashable("payload")),
                ]
            )
            XCTAssertEqual(
                dismissed,
                [
                    WindowActionPayload(id: "detail", value: AnyHashable(9)),
                    WindowActionPayload(value: AnyHashable("closed")),
                ]
            )
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

    func testAdditionalSystemStateEnvironmentValuesCanBeReadAndOverridden() async {
        await MainActor.run {
            struct SystemStateReaderView: View {
                @Environment(\.isLuminanceReduced) var isLuminanceReduced
                @Environment(\.isSceneCaptured) var isSceneCaptured
                @Environment(\.isTabBarShowingSections) var isTabBarShowingSections

                var body: some View {
                    Text(
                        "\(isLuminanceReduced ? "DIM" : "BRIGHT") "
                            + "\(isSceneCaptured ? "CAPTURED" : "PRIVATE") "
                            + "\(isTabBarShowingSections ? "TABSECTIONS" : "TABSFLAT")"
                    )
                }
            }

            let defaultNode = makeNode(SystemStateReaderView())
            let overrideNode = makeNode(
                SystemStateReaderView()
                    .environment(\.isLuminanceReduced, true)
                    .environment(\.isSceneCaptured, true)
                    .environment(\.isTabBarShowingSections, true)
            )

            XCTAssertEqual(defaultNode.text, "BRIGHT PRIVATE TABSFLAT")
            XCTAssertEqual(overrideNode.text, "DIM CAPTURED TABSECTIONS")
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

    func testPreferenceKeyReducesDescendantValuesAndReportsChanges() async {
        await MainActor.run {
            var observedValues: [Int] = []

            @MainActor
            func observedView(first: Bool, second: Bool) -> some View {
                VStack {
                    if first {
                        Text("FIRST")
                            .preference(key: TestSumPreferenceKey.self, value: 2)
                    }
                    if second {
                        Text("SECOND")
                            .preference(key: TestSumPreferenceKey.self, value: 3)
                    }
                }
                .onPreferenceChange(TestSumPreferenceKey.self) { value in
                    observedValues.append(value)
                }
            }

            var first = true
            var second = false
            let host = MountedOnChangeTestHost {
                AnyView(observedView(first: first, second: second))
            }
            defer { host.close() }

            host.reload()
            second = true
            host.reload()
            first = false
            second = false
            host.reload()

            XCTAssertEqual(observedValues, [2, 5, 0])
        }
    }

    func testTransformPreferenceRewritesSubtreeValueBeforeAncestorObservation() async {
        await MainActor.run {
            var observedValues: [Int] = []

            @MainActor
            func observedView(multiplier: Int) -> some View {
                VStack {
                    VStack {
                        Text("FIRST")
                            .preference(key: TestSumPreferenceKey.self, value: 2)
                        Text("SECOND")
                            .preference(key: TestSumPreferenceKey.self, value: 3)
                    }
                    .transformPreference(TestSumPreferenceKey.self) { value in
                        value *= multiplier
                    }

                    Text("OUTSIDE")
                        .preference(key: TestSumPreferenceKey.self, value: 1)
                }
                .onPreferenceChange(TestSumPreferenceKey.self) { value in
                    observedValues.append(value)
                }
            }

            var multiplier = 10
            let host = MountedOnChangeTestHost {
                AnyView(observedView(multiplier: multiplier))
            }
            defer { host.close() }

            host.reload()
            multiplier = 20
            host.reload()

            XCTAssertEqual(observedValues, [51, 101])
        }
    }

    func testStringPreferenceUsesLastReducedValue() async {
        await MainActor.run {
            var observedValues: [String] = []

            @MainActor
            func observedView(_ suffix: String) -> some View {
                VStack {
                    Text("BASE")
                        .preference(key: TestStringPreferenceKey.self, value: "BASE")
                    Text("DETAIL")
                        .preference(key: TestStringPreferenceKey.self, value: "DETAIL-\(suffix)")
                }
                .onPreferenceChange(TestStringPreferenceKey.self) { value in
                    observedValues.append(value)
                }
            }

            var suffix = "A"
            let host = MountedOnChangeTestHost {
                AnyView(observedView(suffix))
            }
            defer { host.close() }

            host.reload()
            suffix = "B"
            host.reload()

            XCTAssertEqual(observedValues, ["DETAIL-A", "DETAIL-B"])
        }
    }

    func testAnchorPreferenceResolvesBoundsThroughGeometryProxy() async {
        await MainActor.run {
            let node = makeNode(
                Text("BASE")
                    .frame(width: 80, height: 24)
                    .anchorPreference(key: TestAnchorListPreferenceKey.self, value: .bounds) { anchor in
                        [anchor]
                    }
                    .overlayPreferenceValue(TestAnchorListPreferenceKey.self) { anchors in
                        if let anchor = anchors.first {
                            GeometryReader { proxy in
                                let bounds = proxy[anchor]
                                Text("\(Int(bounds.size.width))X\(Int(bounds.size.height))")
                            }
                        }
                    }
            )

            XCTAssertTrue(allTexts(in: node).contains("BASE"))
            XCTAssertTrue(allTexts(in: node).contains("80X24"), "\(allTexts(in: node))")
        }
    }

    func testTransformAnchorPreferenceCanAppendContainerAnchor() async {
        await MainActor.run {
            let node = makeNode(
                VStack {
                    Text("CHILD")
                        .frame(width: 40, height: 12)
                        .anchorPreference(key: TestAnchorListPreferenceKey.self, value: .bounds) { anchor in
                            [anchor]
                        }
                }
                .frame(width: 100, height: 50)
                .transformAnchorPreference(key: TestAnchorListPreferenceKey.self, value: .bounds) {
                    anchors, containerAnchor in
                    anchors.append(containerAnchor)
                }
                .overlayPreferenceValue(TestAnchorListPreferenceKey.self) { anchors in
                    Text("ANCHORS \(anchors.count)")
                }
            )

            XCTAssertTrue(allTexts(in: node).contains("CHILD"))
            XCTAssertTrue(allTexts(in: node).contains("ANCHORS 2"))
        }
    }

    func testBackgroundPreferenceValueComposesPreferenceDrivenBackground() async {
        await MainActor.run {
            let node = makeNode(
                Text("BASE")
                    .preference(key: TestStringPreferenceKey.self, value: "BACKGROUND")
                    .backgroundPreferenceValue(TestStringPreferenceKey.self) { value in
                        Text(value)
                    }
            )

            XCTAssertTrue(allTexts(in: node).contains("BASE"))
            XCTAssertTrue(allTexts(in: node).contains("BACKGROUND"))
        }
    }

    func testEnvironmentObjectPropagatesThroughViewContext() async {
        await MainActor.run {
            final class ThemeModel: ObservableObject {
                @Published var label: String

                init(label: String) {
                    self.label = label
                }
            }

            struct EnvironmentObjectReaderView: View {
                @EnvironmentObject var model: ThemeModel

                var body: some View {
                    Text(model.label)
                }
            }

            let outerModel = ThemeModel(label: "OUTER")
            let innerModel = ThemeModel(label: "INNER")
            let node = makeNode(
                VStack {
                    EnvironmentObjectReaderView()
                    EnvironmentObjectReaderView()
                        .environmentObject(innerModel)
                }
                .environmentObject(outerModel)
            )

            XCTAssertEqual(node.children[0].text, "OUTER")
            XCTAssertEqual(node.children[1].text, "INNER")
        }
    }

    func testEnvironmentObjectMutationTriggersInvalidation() async {
        await MainActor.run {
            final class ThemeModel: ObservableObject {
                @Published var label = "MODEL"
            }

            struct EnvironmentObjectReaderView: View {
                @EnvironmentObject var model: ThemeModel

                var body: some View {
                    Text(model.label)
                }
            }

            let model = ThemeModel()
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

            _ = EnvironmentObjectReaderView()
                .environmentObject(model)
                .makeComponent(context: context)
            model.label = "UPDATED"

            XCTAssertEqual(invalidationCount, 1)
        }
    }

    func testEnvironmentObjectManualObjectWillChangeTriggersInvalidation() async {
        await MainActor.run {
            final class ThemeModel: ObservableObject {
                var label = "MODEL"

                func updateLabel(_ value: String) {
                    label = value
                    objectWillChange.send()
                }
            }

            struct EnvironmentObjectReaderView: View {
                @EnvironmentObject var model: ThemeModel

                var body: some View {
                    Text(model.label)
                }
            }

            let model = ThemeModel()
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

            _ = EnvironmentObjectReaderView()
                .environmentObject(model)
                .makeComponent(context: context)
            model.updateLabel("UPDATED")

            XCTAssertEqual(invalidationCount, 1)
        }
    }

    func testEnvironmentObjectDynamicMemberProjectionFeedsRetainedControls() async {
        await MainActor.run {
            final class FormModel: ObservableObject {
                @Published var title = "ALPHA"
            }

            struct EnvironmentObjectEditor: View {
                @EnvironmentObject var model: FormModel

                var body: some View {
                    TextField("TITLE", text: $model.title)
                }
            }

            let model = FormModel()
            let node = makeNode(
                EnvironmentObjectEditor()
                    .environmentObject(model)
            )

            firstFocusable(in: node)?.onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertEqual(model.title, "ALPHAz")
        }
    }

    func testFocusedValuesPropagateThroughViewContext() async {
        await MainActor.run {
            struct FocusedValueReaderView: View {
                @FocusedValue(\.testFocusedLabel) var label

                var body: some View {
                    Text(label ?? "NONE")
                }
            }

            let defaultNode = makeNode(FocusedValueReaderView())
            let focusedNode = makeNode(
                VStack {
                    FocusedValueReaderView()
                    FocusedValueReaderView()
                        .focusedValue(\.testFocusedLabel, "INNER")
                    FocusedValueReaderView()
                        .focusedSceneValue(\.testFocusedLabel, "SCENE")
                }
                .focusedValue(\.testFocusedLabel, "OUTER")
            )

            XCTAssertEqual(defaultNode.text, "NONE")
            XCTAssertEqual(focusedNode.children[0].text, "OUTER")
            XCTAssertEqual(focusedNode.children[1].text, "INNER")
            XCTAssertEqual(focusedNode.children[2].text, "SCENE")
        }
    }

    func testFocusedBindingReadsAndWritesFocusedBindingValues() async {
        await MainActor.run {
            struct FocusedBindingReaderView: View {
                @FocusedBinding(\.testFocusedBinding) var label

                var body: some View {
                    Button(label ?? "NONE") {
                        label = "UPDATED"
                    }
                }
            }

            var storedValue = "BOUND"
            let binding = Binding<String>(
                get: { storedValue },
                set: { storedValue = $0 }
            )
            let node = makeNode(
                FocusedBindingReaderView()
                    .focusedValue(\.testFocusedBinding, binding)
            )

            XCTAssertTrue(allTexts(in: node).contains("BOUND"))
            node.onActivate?()
            XCTAssertEqual(storedValue, "UPDATED")
        }
    }

    func testFocusedObjectValuesPropagateThroughViewContext() async {
        await MainActor.run {
            final class FocusModel: ObservableObject {
                @Published var label: String

                init(label: String) {
                    self.label = label
                }
            }

            struct FocusedObjectReaderView: View {
                @FocusedObject var model: FocusModel?

                var body: some View {
                    Text(model?.label ?? "NONE")
                }
            }

            let defaultNode = makeNode(FocusedObjectReaderView())
            let outerModel = FocusModel(label: "OUTER")
            let innerModel = FocusModel(label: "INNER")
            let sceneModel = FocusModel(label: "SCENE")
            let focusedNode = makeNode(
                VStack {
                    FocusedObjectReaderView()
                    FocusedObjectReaderView()
                        .focusedObject(innerModel)
                    FocusedObjectReaderView()
                        .focusedSceneObject(sceneModel)
                }
                .focusedObject(outerModel)
            )

            XCTAssertEqual(defaultNode.text, "NONE")
            XCTAssertEqual(focusedNode.children[0].text, "OUTER")
            XCTAssertEqual(focusedNode.children[1].text, "INNER")
            XCTAssertEqual(focusedNode.children[2].text, "SCENE")
        }
    }

    func testFocusedObjectMutationTriggersInvalidation() async {
        await MainActor.run {
            final class FocusModel: ObservableObject {
                @Published var label = "MODEL"
            }

            struct FocusedObjectReaderView: View {
                @FocusedObject var model: FocusModel?

                var body: some View {
                    Text(model?.label ?? "NONE")
                }
            }

            let model = FocusModel()
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

            _ = FocusedObjectReaderView()
                .focusedObject(model)
                .makeComponent(context: context)
            model.label = "UPDATED"

            XCTAssertEqual(invalidationCount, 1)
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
            XCTAssertEqual(toggleNode.children[1].preferredSize, Size(width: 56, height: 34))
        }
    }

    func testButtonRepeatBehaviorBridgesThroughEnvironmentValues() async {
        await MainActor.run {
            struct ButtonRepeatBehaviorReaderView: View {
                @Environment(\.buttonRepeatBehavior) var buttonRepeatBehavior

                var body: some View {
                    Text(
                        buttonRepeatBehavior == .enabled
                            ? "ENABLED"
                            : buttonRepeatBehavior == .disabled ? "DISABLED" : "AUTOMATIC"
                    )
                }
            }

            let defaultNode = makeNode(ButtonRepeatBehaviorReaderView())
            let modifierNode = makeNode(
                ButtonRepeatBehaviorReaderView()
                    .buttonRepeatBehavior(.enabled)
            )
            let environmentNode = makeNode(
                ButtonRepeatBehaviorReaderView()
                    .environment(\.buttonRepeatBehavior, .disabled)
            )
            let enabledButtonNode = makeNode(
                Button("REPEAT") {}
                    .buttonRepeatBehavior(.enabled)
            )
            let disabledButtonNode = makeNode(
                Button("REPEAT") {}
                    .buttonRepeatBehavior(.disabled)
            )

            XCTAssertEqual(defaultNode.text, "AUTOMATIC")
            XCTAssertEqual(modifierNode.text, "ENABLED")
            XCTAssertEqual(environmentNode.text, "DISABLED")
            XCTAssertEqual(enabledButtonNode.buttonRepeatBehavior, .enabled)
            XCTAssertEqual(disabledButtonNode.buttonRepeatBehavior, .disabled)
        }
    }

    func testButtonSizingBridgesThroughEnvironmentValuesAndFlexibleButtonsGrow() async {
        await MainActor.run {
            struct ButtonSizingReaderView: View {
                @Environment(\.buttonSizing) var buttonSizing

                var body: some View {
                    Text(buttonSizing == .flexible ? "FLEXIBLE" : buttonSizing == .fitted ? "FITTED" : "AUTOMATIC")
                }
            }

            let defaultNode = makeNode(ButtonSizingReaderView())
            let modifierNode = makeNode(
                ButtonSizingReaderView()
                    .buttonSizing(.flexible)
            )
            let environmentNode = makeNode(
                ButtonSizingReaderView()
                    .environment(\.buttonSizing, .fitted)
            )
            let flexibleButtonNode = makeNode(
                Button("SAVE") {}
                    .buttonSizing(.flexible)
            )
            let fittedButtonNode = makeNode(
                Button("SAVE") {}
                    .buttonSizing(.fitted)
            )

            XCTAssertEqual(defaultNode.text, "AUTOMATIC")
            XCTAssertEqual(modifierNode.text, "FLEXIBLE")
            XCTAssertEqual(environmentNode.text, "FITTED")
            XCTAssertEqual(flexibleButtonNode.layoutPriority, 1)
            XCTAssertEqual(fittedButtonNode.layoutPriority, 0)
        }
    }

    func testAdditionalControlAndScrollEnvironmentValuesCanBeReadAndOverridden() async {
        await MainActor.run {
            struct ControlScrollEnvironmentReaderView: View {
                @Environment(\.menuIndicatorVisibility) var menuIndicatorVisibility
                @Environment(\.defaultWheelPickerItemHeight) var defaultWheelPickerItemHeight
                @Environment(\.scrollDismissesKeyboardMode) var scrollDismissesKeyboardMode

                var body: some View {
                    Text(
                        "\(menuIndicatorVisibility == .hidden ? "HIDDEN" : menuIndicatorVisibility == .visible ? "VISIBLE" : "AUTOMATIC") "
                            + "\(Int(defaultWheelPickerItemHeight)) "
                            + "\(scrollDismissesKeyboardMode == .immediately ? "IMMEDIATE" : scrollDismissesKeyboardMode == .never ? "NEVER" : "AUTO")"
                    )
                }
            }

            let defaultNode = makeNode(ControlScrollEnvironmentReaderView())
            let modifierNode = makeNode(
                ControlScrollEnvironmentReaderView()
                    .menuIndicator(.hidden)
                    .defaultWheelPickerItemHeight(44)
                    .scrollDismissesKeyboard(.immediately)
            )
            let environmentNode = makeNode(
                ControlScrollEnvironmentReaderView()
                    .environment(\.menuIndicatorVisibility, .visible)
                    .environment(\.defaultWheelPickerItemHeight, 52)
                    .environment(\.scrollDismissesKeyboardMode, .never)
            )

            XCTAssertEqual(defaultNode.text, "AUTOMATIC 32 AUTO")
            XCTAssertEqual(modifierNode.text, "HIDDEN 44 IMMEDIATE")
            XCTAssertEqual(environmentNode.text, "VISIBLE 52 NEVER")
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

    func testTaskModifierCancelsWhenRenderedSubtreeDisappears() async {
        let recorder = AsyncTaskLifecycleRecorder()
        var hideAndReload: (@MainActor () -> Void)?

        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var isVisible = true

            host.setComponents {
                guard isVisible else {
                    return []
                }

                return [
                    Text("LOAD")
                        .task {
                            await cancellableTask(id: 0, recorder: recorder)
                        }
                        .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()

            hideAndReload = {
                isVisible = false
                host.reload()
            }
        }

        await waitForTaskStart(recorder, toReach: 1)

        await MainActor.run {
            hideAndReload?()
        }

        await waitForTaskCancellation(recorder, toReach: 1)
        let cancellations = await recorder.cancellations()
        XCTAssertEqual(cancellations, 1)
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

    func testTaskIDModifierCancelsPreviousTaskWhenValueChanges() async {
        let recorder = AsyncTaskLifecycleRecorder()
        var changeIDAndReload: (@MainActor () -> Void)?

        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var taskID = 1

            host.setComponents {
                let currentID = taskID
                return [
                    Text("LOAD")
                        .task(id: currentID) {
                            await cancellableTask(id: currentID, recorder: recorder)
                        }
                        .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()

            changeIDAndReload = {
                taskID = 2
                host.reload()
            }
        }

        await waitForTaskStart(recorder, toReach: 1)

        await MainActor.run {
            changeIDAndReload?()
        }

        await waitForTaskStart(recorder, toReach: 2)
        await waitForTaskCancellation(recorder, toReach: 1)
        let startedIDs = await recorder.startedIDs()
        let cancellations = await recorder.cancellations()
        XCTAssertEqual(startedIDs, [1, 2])
        XCTAssertEqual(cancellations, 1)
    }

    func testRefreshableProvidesRefreshEnvironmentAction() async {
        let counter = AsyncTaskCounter()

        await MainActor.run {
            struct RefreshEnvironmentReaderView: View {
                @Environment(\.refresh) var refresh

                var body: some View {
                    Button(
                        refresh == nil ? "NO REFRESH" : "REFRESH",
                        action: {
                            guard let refresh else {
                                return
                            }

                            Task {
                                await refresh()
                            }
                        })
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

            var value = 1
            let host = MountedOnChangeTestHost { AnyView(observedView(value)) }
            defer { host.close() }
            host.reload()
            value = 3
            host.reload()
            value = 5
            host.reload()

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

            var value = "alpha"
            let host = MountedOnChangeTestHost { AnyView(observedView(value)) }
            defer { host.close() }
            host.reload()
            value = "beta"
            host.reload()

            XCTAssertEqual(values, ["alpha", "beta"])
        }
    }

    func testOnChangeModifierSupportsZeroArgumentModernOverload() async {
        await MainActor.run {
            var changeCount = 0

            @MainActor
            func observedView(_ value: Int) -> some View {
                Text("VALUE")
                    .onChange(of: value, initial: true) {
                        changeCount += 1
                    }
            }

            var value = 1
            let host = MountedOnChangeTestHost { AnyView(observedView(value)) }
            defer { host.close() }
            host.reload()
            value = 2
            host.reload()
            value = 3
            host.reload()

            XCTAssertEqual(changeCount, 3)
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

    func testOnContinuousHoverModifierReportsActiveLocationsAndEndedPhase() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var phases: [HoverPhase] = []

            let node = Text("HOVER")
                .frame(width: 80, height: 24)
                .onContinuousHover(coordinateSpace: .global) { phase in
                    phases.append(phase)
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

            XCTAssertEqual(
                phases,
                [
                    .active(Point(x: 10, y: 10)),
                    .active(Point(x: 12, y: 12)),
                    .ended,
                ]
            )
        }
    }

    func testOnContinuousHoverModifierPreservesExistingPointerHandlers() async {
        await MainActor.run {
            var phases: [HoverPhase] = []
            var moveLocations: [Point] = []
            var exitCount = 0

            let node = makeNode(
                PointerHandlerProbe(
                    onExit: {
                        exitCount += 1
                    },
                    onMove: { point in
                        moveLocations.append(point)
                    }
                )
                .onContinuousHover { phase in
                    phases.append(phase)
                }
            )

            node.onPointerMove?(Point(x: 4, y: 5))
            node.onPointerExit?()

            XCTAssertEqual(moveLocations, [Point(x: 4, y: 5)])
            XCTAssertEqual(exitCount, 1)
            XCTAssertEqual(phases, [.active(Point(x: 4, y: 5)), .ended])
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

    func testSpatialOnTapGestureReportsLocationAndRequiresConsecutiveTaps() async {
        await MainActor.run {
            var locations: [Point] = []
            let node = makeNode(
                Text("TAP")
                    .onTapGesture(count: 2, coordinateSpace: .named("surface")) { location in
                        locations.append(location)
                    }
            )

            XCTAssertTrue(node.isHitTestVisible)

            node.onPointerUpInsideAt?(Point(x: 4, y: 5))
            XCTAssertEqual(locations, [])

            node.onPointerUpOutside?()
            node.onPointerUpInsideAt?(Point(x: 6, y: 7))
            node.onPointerUpInsideAt?(Point(x: 8, y: 9))

            XCTAssertEqual(locations, [Point(x: 8, y: 9)])
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

    func testOnLongPressGestureEnablesHitTestingAndRunsActionAtItsDeadline() async {
        await MainActor.run {
            var longPressCount = 0
            var pressingStates: [Bool] = []
            let (runtime, node) = makeRuntimeNode(
                Text("HOLD")
                    .onLongPressGesture(
                        minimumDuration: 0.25,
                        maximumDistance: 12,
                        perform: {
                            longPressCount += 1
                        },
                        onPressingChanged: { isPressing in
                            pressingStates.append(isPressing)
                        }
                    )
            )
            var now = 10.0
            runtime.clock = { now }
            let point = Point(x: node.resolvedFrame.midX, y: node.resolvedFrame.midY)

            XCTAssertTrue(node.isHitTestVisible)
            XCTAssertEqual(node.longPressGesture?.minimumDuration, 0.25)
            XCTAssertEqual(node.longPressGesture?.maximumDistance, 12)

            runtime.pointerDown(at: point)
            XCTAssertEqual(longPressCount, 0)
            XCTAssertEqual(pressingStates, [true])

            now = 10.25
            _ = runtime.tickAnimations(at: now)
            XCTAssertEqual(longPressCount, 1)
            XCTAssertEqual(pressingStates, [true, false])
            runtime.pointerUp(at: point)
            XCTAssertEqual(longPressCount, 1)
        }
    }

    func testOnLongPressGestureCancelsPressingOnEarlyReleaseAndExcessMovement() async {
        await MainActor.run {
            var longPressCount = 0
            var pressingStates: [Bool] = []
            let (runtime, node) = makeRuntimeNode(
                Text("HOLD")
                    .onLongPressGesture(
                        minimumDuration: 0.25,
                        pressing: { isPressing in
                            pressingStates.append(isPressing)
                        },
                        perform: { longPressCount += 1 }
                    )
            )
            var now = 10.0
            runtime.clock = { now }
            let point = Point(x: node.resolvedFrame.midX, y: node.resolvedFrame.midY)

            runtime.pointerDown(at: point)
            runtime.pointerUp(at: point)
            runtime.pointerDown(at: point)
            runtime.pointerMoved(to: Point(x: point.x + 20, y: point.y))
            now = 11
            _ = runtime.tickAnimations(at: now)

            XCTAssertEqual(longPressCount, 0)
            XCTAssertEqual(pressingStates, [true, false, true, false])
        }
    }

    func testOnLongPressGesturePreservesExistingPointerHandlers() async {
        await MainActor.run {
            var downCount = 0
            var insideCount = 0
            var outsideCount = 0
            var exitCount = 0
            var longPressCount = 0
            var pressingStates: [Bool] = []
            let (runtime, node) = makeRuntimeNode(
                PointerHandlerProbe(
                    onExit: {
                        exitCount += 1
                    },
                    onDown: {
                        downCount += 1
                    },
                    onUpInside: {
                        insideCount += 1
                    },
                    onUpOutside: {
                        outsideCount += 1
                    }
                )
                .onLongPressGesture(
                    minimumDuration: 0.2,
                    maximumDistance: 8,
                    perform: {
                        longPressCount += 1
                    },
                    onPressingChanged: { isPressing in
                        pressingStates.append(isPressing)
                    }
                )
            )
            var now = 10.0
            runtime.clock = { now }
            let point = Point(x: node.resolvedFrame.midX, y: node.resolvedFrame.midY)

            runtime.pointerDown(at: point)
            now = 10.2
            _ = runtime.tickAnimations(at: now)
            runtime.pointerUp(at: point)
            runtime.pointerDown(at: point)
            runtime.pointerUp(at: Point(x: point.x + 1000, y: point.y + 1000))

            XCTAssertEqual(downCount, 2)
            XCTAssertEqual(insideCount, 1)
            XCTAssertEqual(outsideCount, 1)
            XCTAssertEqual(exitCount, 1)
            XCTAssertEqual(longPressCount, 1)
            XCTAssertEqual(pressingStates, [true, false, true, false])
        }
    }

    func testTapGestureObjectMapsThroughGestureModifier() async {
        await MainActor.run {
            var tapCount = 0
            let node = makeNode(
                Text("TAP")
                    .gesture(
                        TapGesture(count: 2).onEnded { _ in
                            tapCount += 1
                        }
                    )
            )

            XCTAssertTrue(node.isHitTestVisible)

            node.onPointerUpInside?()
            XCTAssertEqual(tapCount, 0)

            node.onPointerUpInside?()
            XCTAssertEqual(tapCount, 1)
        }
    }

    func testGestureMaskCanDisableDirectGestureObject() async {
        await MainActor.run {
            var tapCount = 0
            let node = makeNode(
                Text("TAP")
                    .gesture(
                        TapGesture().onEnded { _ in
                            tapCount += 1
                        },
                        including: .subviews
                    )
            )

            node.onPointerUpInside?()

            XCTAssertEqual(tapCount, 0)
        }
    }

    func testGestureModifierIsEnabledOverloadsGateGestureApplication() async {
        await MainActor.run {
            var enabledTapCount = 0
            var disabledTapCount = 0
            var namedTapCount = 0
            let enabledNode = makeNode(
                Text("TAP")
                    .gesture(
                        TapGesture().onEnded { _ in
                            enabledTapCount += 1
                        },
                        isEnabled: true
                    )
            )
            let disabledNode = makeNode(
                Text("TAP")
                    .gesture(
                        TapGesture().onEnded { _ in
                            disabledTapCount += 1
                        },
                        isEnabled: false
                    )
            )
            let namedNode = makeNode(
                Text("TAP")
                    .gesture(
                        TapGesture().onEnded { _ in
                            namedTapCount += 1
                        },
                        name: "primary-tap",
                        isEnabled: true
                    )
            )

            enabledNode.onPointerUpInside?()
            disabledNode.onPointerUpInside?()
            namedNode.onPointerUpInside?()

            XCTAssertEqual(enabledTapCount, 1)
            XCTAssertEqual(disabledTapCount, 0)
            XCTAssertEqual(namedTapCount, 1)
            XCTAssertNil(disabledNode.onPointerUpInside)
        }
    }

    func testPriorityAndSimultaneousGestureIsEnabledOverloadsGateGestureApplication() async {
        await MainActor.run {
            var highPriorityTapCount = 0
            var disabledHighPriorityTapCount = 0
            var simultaneousTapCount = 0
            var disabledSimultaneousTapCount = 0
            let highPriorityNode = makeNode(
                Text("TAP")
                    .highPriorityGesture(
                        TapGesture().onEnded { _ in
                            highPriorityTapCount += 1
                        },
                        isEnabled: true
                    )
            )
            let disabledHighPriorityNode = makeNode(
                Text("TAP")
                    .highPriorityGesture(
                        TapGesture().onEnded { _ in
                            disabledHighPriorityTapCount += 1
                        },
                        name: "disabled-high-priority",
                        isEnabled: false
                    )
            )
            let simultaneousNode = makeNode(
                Text("TAP")
                    .simultaneousGesture(
                        TapGesture().onEnded { _ in
                            simultaneousTapCount += 1
                        },
                        name: "secondary-tap",
                        isEnabled: true
                    )
            )
            let disabledSimultaneousNode = makeNode(
                Text("TAP")
                    .simultaneousGesture(
                        TapGesture().onEnded { _ in
                            disabledSimultaneousTapCount += 1
                        },
                        isEnabled: false
                    )
            )

            highPriorityNode.onPointerUpInside?()
            disabledHighPriorityNode.onPointerUpInside?()
            simultaneousNode.onPointerUpInside?()
            disabledSimultaneousNode.onPointerUpInside?()

            XCTAssertEqual(highPriorityTapCount, 1)
            XCTAssertEqual(disabledHighPriorityTapCount, 0)
            XCTAssertEqual(simultaneousTapCount, 1)
            XCTAssertEqual(disabledSimultaneousTapCount, 0)
            XCTAssertNil(disabledHighPriorityNode.onPointerUpInside)
            XCTAssertNil(disabledSimultaneousNode.onPointerUpInside)
        }
    }

    func testAnyGestureTypeErasesTapGestureObject() async {
        await MainActor.run {
            var tapCount = 0
            let erasedGesture = AnyGesture(
                TapGesture(count: 2).onEnded { _ in
                    tapCount += 1
                }
            )
            let node = makeNode(
                Text("TAP")
                    .gesture(erasedGesture)
            )

            XCTAssertTrue(node.isHitTestVisible)

            node.onPointerUpInside?()
            XCTAssertEqual(tapCount, 0)

            node.onPointerUpInside?()
            XCTAssertEqual(tapCount, 1)
        }
    }

    func testAnyGesturePreservesMaskAndTypeErasesDragGestureObject() async {
        await MainActor.run {
            var changes: [DragGesture.Value] = []
            var disabledChanges: [DragGesture.Value] = []
            let erasedDragGesture = AnyGesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    changes.append(value)
                }
            )
            let disabledErasedDragGesture = AnyGesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    disabledChanges.append(value)
                }
            )
            let node = makeNode(
                Text("DRAG")
                    .gesture(erasedDragGesture)
            )
            let disabledNode = makeNode(
                Text("DRAG")
                    .gesture(disabledErasedDragGesture, including: .none)
            )

            node.onDragStart?(Point(x: 5, y: 6))
            disabledNode.onDragStart?(Point(x: 7, y: 8))

            XCTAssertEqual(changes.map(\.location), [Point(x: 5, y: 6)])
            XCTAssertEqual(disabledChanges, [])
            XCTAssertNil(disabledNode.onDragStart)
        }
    }

    func testSimultaneousGestureAppliesBothRetainedGestures() async {
        await MainActor.run {
            var tapCount = 0
            var spatialLocations: [Point] = []
            let combinedGesture = TapGesture().onEnded { _ in
                tapCount += 1
            }
            .simultaneously(
                with: SpatialTapGesture().onEnded { value in
                    spatialLocations.append(value.location)
                }
            )
            let node = makeNode(
                Text("TAP")
                    .gesture(combinedGesture)
            )

            XCTAssertTrue(node.isHitTestVisible)

            node.onPointerUpInside?()
            node.onPointerUpInsideAt?(Point(x: 9, y: 10))

            XCTAssertEqual(tapCount, 1)
            XCTAssertEqual(spatialLocations, [Point(x: 9, y: 10)])
        }
    }

    func testSimultaneousGesturePreservesMaskForBothRetainedGestures() async {
        await MainActor.run {
            var tapCount = 0
            var dragChanges: [DragGesture.Value] = []
            let combinedGesture = SimultaneousGesture(
                TapGesture().onEnded { _ in
                    tapCount += 1
                },
                DragGesture(minimumDistance: 0).onChanged { value in
                    dragChanges.append(value)
                }
            )
            let node = makeNode(
                Text("INPUT")
                    .gesture(combinedGesture, including: .none)
            )

            node.onPointerUpInside?()
            node.onDragStart?(Point(x: 1, y: 2))

            XCTAssertEqual(tapCount, 0)
            XCTAssertEqual(dragChanges, [])
            XCTAssertNil(node.onPointerUpInside)
            XCTAssertNil(node.onDragStart)
        }
    }

    func testSequenceGestureAppliesBothRetainedGestures() async {
        await MainActor.run {
            var tapCount = 0
            var dragChanges: [DragGesture.Value] = []
            let sequence = TapGesture().onEnded { _ in
                tapCount += 1
            }
            .sequenced(
                before: DragGesture(minimumDistance: 0).onChanged { value in
                    dragChanges.append(value)
                }
            )
            let node = makeNode(
                Text("INPUT")
                    .gesture(sequence)
            )

            XCTAssertTrue(node.isHitTestVisible)

            node.onPointerUpInside?()
            node.onDragStart?(Point(x: 3, y: 4))

            XCTAssertEqual(tapCount, 1)
            XCTAssertEqual(dragChanges.map(\.location), [Point(x: 3, y: 4)])
        }
    }

    func testExclusiveGestureAppliesFirstRetainedGestureOnly() async {
        await MainActor.run {
            var firstTapCount = 0
            var secondTapLocations: [Point] = []
            let exclusive = ExclusiveGesture(
                TapGesture().onEnded { _ in
                    firstTapCount += 1
                },
                SpatialTapGesture().onEnded { value in
                    secondTapLocations.append(value.location)
                }
            )
            let helperExclusive = TapGesture().onEnded { _ in
                firstTapCount += 10
            }
            .exclusively(
                before: SpatialTapGesture().onEnded { value in
                    secondTapLocations.append(value.location)
                }
            )
            let node = makeNode(Text("FIRST").gesture(exclusive))
            let helperNode = makeNode(Text("HELPER").gesture(helperExclusive))

            node.onPointerUpInside?()
            node.onPointerUpInsideAt?(Point(x: 5, y: 6))
            helperNode.onPointerUpInside?()
            helperNode.onPointerUpInsideAt?(Point(x: 7, y: 8))

            XCTAssertEqual(firstTapCount, 11)
            XCTAssertEqual(secondTapLocations, [])
            XCTAssertNil(node.onPointerUpInsideAt)
            XCTAssertNil(helperNode.onPointerUpInsideAt)
        }
    }

    func testLongPressGestureObjectMapsThroughPriorityGestureModifiers() async {
        await MainActor.run {
            var endings: [Bool] = []
            var changes: [Bool] = []
            var simultaneousTapCount = 0
            let (runtime, highPriorityNode) = makeRuntimeNode(
                Text("HOLD")
                    .highPriorityGesture(
                        LongPressGesture(minimumDuration: 0.2, maximumDistance: 8)
                            .onChanged { isPressing in
                                changes.append(isPressing)
                            }
                            .onEnded { didFinish in
                                endings.append(didFinish)
                            }
                    )
            )
            var now = 10.0
            runtime.clock = { now }
            let point = Point(x: highPriorityNode.resolvedFrame.midX, y: highPriorityNode.resolvedFrame.midY)
            let simultaneousNode = makeNode(
                Text("TAP")
                    .simultaneousGesture(
                        TapGesture().onEnded { _ in
                            simultaneousTapCount += 1
                        }
                    )
            )

            runtime.pointerDown(at: point)
            now = 10.2
            _ = runtime.tickAnimations(at: now)
            runtime.pointerUp(at: point)
            simultaneousNode.onPointerUpInside?()

            XCTAssertEqual(changes, [true])
            XCTAssertEqual(endings, [true])
            XCTAssertEqual(simultaneousTapCount, 1)
        }
    }

    func testSpatialTapGestureObjectMapsThroughGestureModifier() async {
        await MainActor.run {
            var values: [SpatialTapGesture.Value] = []
            let node = makeNode(
                Text("TAP")
                    .gesture(
                        SpatialTapGesture(count: 2, coordinateSpace: .global)
                            .onEnded { value in
                                values.append(value)
                            }
                    )
            )

            XCTAssertTrue(node.isHitTestVisible)

            node.onPointerUpInsideAt?(Point(x: 11, y: 12))
            XCTAssertEqual(values, [])

            node.onPointerUpInsideAt?(Point(x: 13, y: 14))
            XCTAssertEqual(values.map(\.location), [Point(x: 13, y: 14)])
        }
    }

    func testSpatialTapGestureReceivesRuntimePointerUpLocation() async {
        await MainActor.run {
            var locations: [Point] = []
            let (runtime, node) = makeRuntimeNode(
                Text("TAP")
                    .frame(width: 80, height: 24)
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            locations.append(value.location)
                        }
                    ),
                size: Size(width: 200, height: 100)
            )

            XCTAssertTrue(node.isHitTestVisible)

            runtime.pointerDown(at: Point(x: 20, y: 12))
            runtime.pointerUp(at: Point(x: 22, y: 14))

            XCTAssertEqual(locations, [Point(x: 22, y: 14)])
        }
    }

    func testDragGestureObjectMapsRetainedDragValues() async {
        await MainActor.run {
            var changes: [DragGesture.Value] = []
            var endings: [DragGesture.Value] = []
            let node = makeNode(
                Text("DRAG")
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                changes.append(value)
                            }
                            .onEnded { value in
                                endings.append(value)
                            }
                    )
            )

            XCTAssertTrue(node.isHitTestVisible)

            node.onDragStart?(Point(x: 10, y: 20))
            node.onDragChange?(Point(x: 13, y: 24), Point(x: 3, y: 4))
            node.onDragChange?(Point(x: 18, y: 31), Point(x: 8, y: 11))
            node.onDragEnd?(Point(x: 20, y: 34), Point(x: 10, y: 14))

            XCTAssertEqual(changes.count, 2)
            XCTAssertEqual(changes[0].startLocation, Point(x: 10, y: 20))
            XCTAssertEqual(changes[0].location, Point(x: 13, y: 24))
            XCTAssertEqual(changes[0].translation, Size(width: 3, height: 4))
            XCTAssertEqual(changes[1].location, Point(x: 18, y: 31))
            XCTAssertEqual(changes[1].translation, Size(width: 8, height: 11))
            XCTAssertEqual(endings.map(\.location), [Point(x: 20, y: 34)])
            XCTAssertEqual(endings.map(\.translation), [Size(width: 10, height: 14)])
        }
    }

    func testDragGestureMinimumDistanceZeroStartsImmediatelyAndMaskCanDisable() async {
        await MainActor.run {
            var immediateChanges: [DragGesture.Value] = []
            var disabledChanges: [DragGesture.Value] = []
            let immediateNode = makeNode(
                Text("DRAG")
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                immediateChanges.append(value)
                            }
                    )
            )
            let disabledNode = makeNode(
                Text("DRAG")
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                disabledChanges.append(value)
                            },
                        including: .none
                    )
            )

            immediateNode.onDragStart?(Point(x: 2, y: 3))
            disabledNode.onDragStart?(Point(x: 2, y: 3))

            XCTAssertEqual(immediateChanges.map(\.location), [Point(x: 2, y: 3)])
            XCTAssertEqual(immediateChanges.map(\.translation), [Size(width: 0, height: 0)])
            XCTAssertEqual(disabledChanges.count, 0)
            XCTAssertNil(disabledNode.onDragStart)
            XCTAssertNil(disabledNode.onDragChange)
            XCTAssertNil(disabledNode.onDragEnd)
        }
    }

    func testDragGestureAcceptsCoordinateSpaceInitializers() async {
        await MainActor.run {
            var globalChanges: [DragGesture.Value] = []
            var namedEndings: [DragGesture.Value] = []
            let globalNode = makeNode(
                Text("GLOBAL")
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                globalChanges.append(value)
                            }
                    )
            )
            let namedNode = makeNode(
                Text("NAMED")
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                            .onEnded { value in
                                namedEndings.append(value)
                            }
                    )
            )

            globalNode.onDragStart?(Point(x: 1, y: 2))
            namedNode.onDragStart?(Point(x: 3, y: 4))
            namedNode.onDragEnd?(Point(x: 8, y: 10), Point(x: 5, y: 6))

            XCTAssertEqual(globalChanges.map(\.location), [Point(x: 1, y: 2)])
            XCTAssertEqual(namedEndings.map(\.startLocation), [Point(x: 3, y: 4)])
            XCTAssertEqual(namedEndings.map(\.translation), [Size(width: 5, height: 6)])
        }
    }

    func testGestureStateUpdatesDuringDragAndResetsOnEnd() async {
        await MainActor.run {
            let translationState = GestureState(wrappedValue: Size(width: 0, height: 0))
            var transactions: [Transaction] = []
            let node = makeNode(
                Text("DRAG")
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating(translationState.projectedValue) { value, state, transaction in
                                state = value.translation
                                transactions.append(transaction)
                            }
                    )
            )

            XCTAssertEqual(translationState.wrappedValue, Size(width: 0, height: 0))

            node.onDragStart?(Point(x: 2, y: 3))
            XCTAssertEqual(translationState.wrappedValue, Size(width: 0, height: 0))

            node.onDragChange?(Point(x: 12, y: 18), Point(x: 10, y: 15))
            XCTAssertEqual(translationState.wrappedValue, Size(width: 10, height: 15))

            node.onDragEnd?(Point(x: 14, y: 20), Point(x: 12, y: 17))
            XCTAssertEqual(translationState.wrappedValue, Size(width: 0, height: 0))
            XCTAssertEqual(transactions.count, 2)
        }
    }

    func testGestureStateSyntaxWorksInRetainedViewBodies() async {
        await MainActor.run {
            struct GestureStateProbe: View {
                @GestureState var isPressing = false

                var body: some View {
                    Text(isPressing ? "PRESSING" : "IDLE")
                        .gesture(
                            LongPressGesture(minimumDuration: 0.1)
                                .updating($isPressing) { value, state, _ in
                                    state = value
                                }
                        )
                }
            }

            let node = makeNode(GestureStateProbe())
            XCTAssertTrue(node.isHitTestVisible)
            XCTAssertEqual(node.text, "IDLE")
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
            let formattedNode = makeNode(LabeledContent("COUNT", value: 42, format: .number))
            let formattedKeyNode = makeNode(LabeledContent(LocalizedStringKey("SCORE"), value: 0.875, format: .percent))

            XCTAssertEqual(allTexts(in: builderNode), ["LABEL", "VALUE"])
            XCTAssertEqual(builderNode.children[0].layoutPriority, 1)
            XCTAssertEqual(builderNode.children[0].textStyle.color, .secondary)
            XCTAssertEqual(allTexts(in: stringNode), ["STATUS", "READY"])
            XCTAssertEqual(allTexts(in: keyNode), ["MODE", "AUTO"])
            XCTAssertEqual(allTexts(in: formattedNode), ["COUNT", "42"])
            XCTAssertEqual(allTexts(in: formattedKeyNode), ["SCORE", 0.875.formatted(.percent)])
        }
    }

    func testLabeledContentStyleModifierPropagatesThroughEnvironment() async {
        await MainActor.run {
            struct LabeledContentStyleReaderView: View {
                @Environment(\.labeledContentStyle) var labeledContentStyle

                var body: some View {
                    Text(labeledContentStyle == .automatic ? "AUTOMATIC" : "OTHER")
                }
            }

            let readerNode = makeNode(
                LabeledContentStyleReaderView()
                    .labeledContentStyle(AutomaticLabeledContentStyle())
            )
            let inheritedNode = makeNode(
                VStack {
                    LabeledContent("STATUS", value: "READY")
                }
                .labeledContentStyle(.automatic)
            )

            XCTAssertEqual(readerNode.text, "AUTOMATIC")
            XCTAssertEqual(allTexts(in: inheritedNode.children[0]), ["STATUS", "READY"])
            XCTAssertEqual(inheritedNode.children[0].children[0].textStyle.color, Color.secondary)
        }
    }

    func testToolbarModifierComposesRetainedCommandRow() async {
        await MainActor.run {
            var activations = 0
            let node = makeNode(
                Text("DETAIL")
                    .toolbar(id: "main-toolbar") {
                        ToolbarItem(placement: .navigation) {
                            Button("BACK") {
                                activations += 1
                            }
                        }
                        ToolbarItemGroup(id: "actions", placement: .primaryAction) {
                            Button("ADD") {}
                            Button("EDIT") {}
                        }
                    }
            )

            guard case .stack(let rootLayout) = node.layoutMode else {
                return XCTFail("Expected toolbar modifier to wrap content in a vertical stack")
            }

            XCTAssertEqual(rootLayout, .vertical(spacing: 0, alignment: .stretch))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].nodeTag, "main-toolbar")
            XCTAssertEqual(node.children[1].text, "DETAIL")

            let toolbarTexts = allTexts(in: node.children[0])
            XCTAssertTrue(toolbarTexts.contains("BACK"))
            XCTAssertTrue(toolbarTexts.contains("ADD"))
            XCTAssertTrue(toolbarTexts.contains("EDIT"))

            firstFocusable(in: node.children[0])?.onActivate?()
            XCTAssertEqual(activations, 1)
        }
    }

    func testToolbarItemPlacementOrdersRetainedCommandRow() async {
        await MainActor.run {
            let node = makeNode(
                Text("DETAIL")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("SAVE") {}
                        }
                        ToolbarItem(placement: .navigation) {
                            Button("BACK") {}
                        }
                        ToolbarItem(placement: .bottomBar) {
                            Button("BOTTOM") {}
                        }
                        ToolbarItem(placement: .principal) {
                            Text("TITLE")
                        }
                        ToolbarItem(placement: .status) {
                            Text("READY")
                        }
                        ToolbarItem(placement: .destructiveAction) {
                            Button("DELETE") {}
                        }
                    }
            )

            XCTAssertEqual(allTexts(in: node.children[0]), ["BACK", "TITLE", "READY", "SAVE", "DELETE", "BOTTOM"])
            XCTAssertEqual(node.children[1].text, "DETAIL")
        }
    }

    func testToolbarConfigurationModifiersPreserveRetainedToolbarRow() async {
        await MainActor.run {
            let gradient = WinSwiftUI.LinearGradient(
                colors: [.red, .blue],
                startPoint: .leading,
                endPoint: .trailing
            )
            let roles: Set<ToolbarRole> = [.automatic, .navigationStack, .editor, .browser]
            let titleModes: Set<ToolbarTitleDisplayMode> = [.automatic, .inline, .inlineLarge, .large]
            let placements: Set<ToolbarItemPlacement> = [.automatic, .navigationBar, .tabBar, .windowToolbar]

            let node = makeNode(
                Text("DETAIL")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("SAVE") {}
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar, .tabBar)
                    .toolbar(.visible, for: .windowToolbar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarBackground(Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1), for: .navigationBar)
                    .toolbarBackground(nil as Color?, for: .tabBar)
                    .toolbarBackground(ForegroundStyle.color(.secondary), for: .windowToolbar)
                    .toolbarBackground(gradient, for: .bottomBar)
                    .toolbarColorScheme(.light, for: .navigationBar, .tabBar)
                    .toolbarColorScheme(nil, for: .windowToolbar)
                    .toolbarRole(.editor)
                    .toolbarTitleDisplayMode(.inlineLarge)
            )

            guard case .stack(let rootLayout) = node.layoutMode else {
                return XCTFail("Expected toolbar configuration to preserve retained toolbar row")
            }

            XCTAssertEqual(rootLayout, .vertical(spacing: 0, alignment: .stretch))
            XCTAssertEqual(roles.count, 4)
            XCTAssertEqual(titleModes.count, 4)
            XCTAssertEqual(placements.count, 4)
            let toolbarNode = node.children[0]
            XCTAssertTrue(allTexts(in: toolbarNode).contains("SAVE"))
            XCTAssertTrue(toolbarNode.isHidden)
            XCTAssertEqual(toolbarNode.toolbarPlacementTags, Set(["primaryAction"]))
            XCTAssertEqual(toolbarNode.backgroundColor, Color(red: 0.957, green: 0.957, blue: 0.957, alpha: 0.95))
            XCTAssertNil(toolbarNode.backgroundGradient)
            XCTAssertEqual(toolbarNode.cornerRadius, 6)
            XCTAssertEqual(toolbarNode.borderColor, Color(red: 0.44, green: 0.60, blue: 0.86, alpha: 0.30))
            XCTAssertEqual(toolbarNode.shadowSpread, 6)
            XCTAssertEqual(
                firstTextNode(in: toolbarNode)?.textStyle.color, Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 1))
            guard case .stack(let toolbarLayout) = toolbarNode.layoutMode else {
                return XCTFail("Expected retained toolbar row to keep stack layout")
            }
            XCTAssertEqual(toolbarLayout.padding, EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            XCTAssertEqual(node.children[1].text, "DETAIL")
        }
    }

    func testToolbarVisibilityModifierMapsToRetainedToolbarRowVisibility() async {
        await MainActor.run {
            let hiddenNode = makeNode(
                Text("DETAIL")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("SAVE") {}
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
            )
            let visibleNode = makeNode(
                Text("DETAIL")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("SAVE") {}
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbar(.visible, for: .navigationBar)
            )
            let automaticNode = makeNode(
                Text("DETAIL")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("SAVE") {}
                        }
                    }
                    .toolbar(.automatic, for: .navigationBar)
            )

            XCTAssertTrue(hiddenNode.children[0].isHidden)
            XCTAssertEqual(hiddenNode.children[1].text, "DETAIL")
            XCTAssertFalse(visibleNode.children[0].isHidden)
            XCTAssertFalse(automaticNode.children[0].isHidden)
        }
    }

    func testToolbarBarArgumentsScopeRetainedToolbarConfiguration() async {
        await MainActor.run {
            let bottomOnlyNode = makeNode(
                Text("DETAIL")
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Button("BOTTOM") {}
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbarBackground(Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1), for: .navigationBar)
                    .toolbarColorScheme(.light, for: .navigationBar)
            )
            let bottomHiddenNode = makeNode(
                Text("DETAIL")
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Button("BOTTOM") {}
                        }
                    }
                    .toolbar(.hidden, for: .bottomBar)
                    .toolbarBackground(Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1), for: .bottomBar)
            )

            XCTAssertEqual(bottomOnlyNode.children[0].toolbarPlacementTags, Set(["bottomBar"]))
            XCTAssertFalse(bottomOnlyNode.children[0].isHidden)
            XCTAssertEqual(
                bottomOnlyNode.children[0].backgroundColor,
                Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 0.92))

            XCTAssertTrue(bottomHiddenNode.children[0].isHidden)
            XCTAssertEqual(
                bottomHiddenNode.children[0].backgroundColor, Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
        }
    }

    func testNavigationBarItemsBridgeToRetainedToolbarRow() async {
        await MainActor.run {
            var leadingActivations = 0
            var trailingActivations = 0
            let node = makeNode(
                Text("DETAIL")
                    .navigationBarItems(
                        leading: Button("LEADING") {
                            leadingActivations += 1
                        },
                        trailing: Button("TRAILING") {
                            trailingActivations += 1
                        }
                    )
            )

            guard case .stack(let rootLayout) = node.layoutMode else {
                return XCTFail("Expected navigationBarItems to wrap content in a vertical stack")
            }

            XCTAssertEqual(rootLayout, .vertical(spacing: 0, alignment: .stretch))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[1].text, "DETAIL")

            let toolbarTexts = allTexts(in: node.children[0])
            XCTAssertTrue(toolbarTexts.contains("LEADING"))
            XCTAssertTrue(toolbarTexts.contains("TRAILING"))

            let focusables = focusableNodes(in: node.children[0])
            XCTAssertEqual(focusables.count, 2)
            focusables[0].onActivate?()
            focusables[1].onActivate?()

            XCTAssertEqual(leadingActivations, 1)
            XCTAssertEqual(trailingActivations, 1)
        }
    }

    func testNavigationBarItemsSingleSideOverloadsBridgeToRetainedToolbarRows() async {
        await MainActor.run {
            let leadingNode = makeNode(
                Text("DETAIL")
                    .navigationBarItems(leading: Button("LEADING") {})
            )
            let trailingNode = makeNode(
                Text("DETAIL")
                    .navigationBarItems(trailing: Button("TRAILING") {})
            )

            XCTAssertTrue(allTexts(in: leadingNode.children[0]).contains("LEADING"))
            XCTAssertFalse(allTexts(in: leadingNode.children[0]).contains("TRAILING"))
            XCTAssertEqual(leadingNode.children[1].text, "DETAIL")

            XCTAssertTrue(allTexts(in: trailingNode.children[0]).contains("TRAILING"))
            XCTAssertFalse(allTexts(in: trailingNode.children[0]).contains("LEADING"))
            XCTAssertEqual(trailingNode.children[1].text, "DETAIL")
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
            XCTAssertEqual(builderNode.children[1].textStyle.color, Color.secondary)

            builderNode.children[2].onActivate?()

            XCTAssertEqual(retryCount, 1)
            XCTAssertTrue(allTexts(in: titledNode).contains("NO RESULTS"))
            XCTAssertTrue(allTexts(in: titledNode).contains("TRY ANOTHER TERM"))
            XCTAssertTrue(allTexts(in: searchNode).contains("No Results"))
            XCTAssertTrue(allTexts(in: searchNode).contains("No results for widgets"))
        }
    }

    func testContentUnavailableViewNamedImageInitializersComposeBitmapLabel() async {
        await MainActor.run {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("winswiftui-unavailable-image-\(UUID().uuidString)")
                .appendingPathExtension("bmp")
            try! twoPixelBGRA32BMPData().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let stringNode = makeNode(
                ContentUnavailableView("OFFLINE", image: url.path, description: Text("Try again later"))
            )
            let protocolTitle: Substring = "EMPTY"[...]
            let protocolNode = makeNode(
                ContentUnavailableView(protocolTitle, image: url.path)
            )
            let keyNode = makeNode(
                ContentUnavailableView(LocalizedStringKey("MISSING"), image: url.path)
            )

            XCTAssertTrue(allTexts(in: stringNode).contains("OFFLINE"))
            XCTAssertTrue(allTexts(in: stringNode).contains("Try again later"))
            XCTAssertEqual(firstBitmapNode(in: stringNode)?.bitmapSurface?.width, 2)
            XCTAssertEqual(firstBitmapNode(in: stringNode)?.bitmapSurface?.height, 1)
            XCTAssertTrue(allTexts(in: protocolNode).contains("EMPTY"))
            XCTAssertTrue(allTexts(in: keyNode).contains("MISSING"))
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

            // ZStack panel > reader > frame > text: the reader carries a node
            // of its own so its resolved frame is the slot it was handed,
            // which is what the runtime re-invokes the body against.
            XCTAssertEqual(node.children.count, 1)
            XCTAssertEqual(node.children[0].children.count, 1)
            XCTAssertEqual(node.children[0].children[0].children[0].text, "320 X 180")

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

    func testGeometryProxyFrameAndSafeAreaInsetsUseCanvasBounds() async {
        await MainActor.run {
            let rootSize = Size(width: 240, height: 160)
            let context = ViewBuildContext(canvasSizeProvider: { rootSize }, invalidateHandler: {})
            var localFrame: Rect?
            var globalFrame: Rect?
            var namedFrame: Rect?
            var protocolFrame: Rect?
            var namedProtocolFrame: Rect?
            var namedBounds: Rect?
            var safeAreaInsets: EdgeInsets?

            let node = GeometryReader { proxy in
                localFrame = proxy.frame(in: .local)
                globalFrame = proxy.frame(in: .global)
                namedFrame = proxy.frame(in: .named("reader"))
                protocolFrame = proxy.frame(in: GlobalCoordinateSpace.global)
                namedProtocolFrame = proxy.frame(in: NamedCoordinateSpace("reader"))
                namedBounds = proxy.bounds(of: "reader")
                safeAreaInsets = proxy.safeAreaInsets
                Text("GEOMETRY")
                    .coordinateSpace(NamedCoordinateSpace("reader"))
                    .coordinateSpace(name: "legacy")
            }
            .makeComponent(context: context)
            .makeNode(runtime: RetainedViewRuntime(root: ViewNode()))

            XCTAssertTrue(allTexts(in: node).contains("GEOMETRY"))
            XCTAssertEqual(localFrame, Rect(x: 0, y: 0, width: 240, height: 160))
            XCTAssertEqual(globalFrame, Rect(x: 0, y: 0, width: 240, height: 160))
            XCTAssertEqual(namedFrame, Rect(x: 0, y: 0, width: 240, height: 160))
            XCTAssertEqual(protocolFrame, Rect(x: 0, y: 0, width: 240, height: 160))
            XCTAssertEqual(namedProtocolFrame, Rect(x: 0, y: 0, width: 240, height: 160))
            XCTAssertEqual(namedBounds, Rect(x: 0, y: 0, width: 240, height: 160))
            XCTAssertEqual(safeAreaInsets, .zero)
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

    func testObservedObjectManualObjectWillChangeTriggersInvalidation() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                var value = 0

                func increment() {
                    value += 1
                    objectWillChange.send()
                }
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
            model.increment()

            XCTAssertEqual(invalidationCount, 1)
        }
    }

    func testPublishedProjectedPublisherSendsInitialAndUpdatedValues() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
                @Published var title = "ALPHA"
            }

            let model = CounterModel()
            var values: [Int] = []
            var titles: [String] = []
            var cancellables = Set<AnyCancellable>()

            let valueCancellable = model.$value.sink { value in
                values.append(value)
            }
            model.$title.sink { title in
                titles.append(title)
            }.store(in: &cancellables)

            XCTAssertEqual(values, [0])
            XCTAssertEqual(titles, ["ALPHA"])

            model.value = 1
            model.title = "BETA"

            XCTAssertEqual(values, [0, 1])
            XCTAssertEqual(titles, ["ALPHA", "BETA"])
            XCTAssertEqual(cancellables.count, 1)

            valueCancellable.cancel()
            model.value = 2

            XCTAssertEqual(values, [0, 1])
        }
    }

    func testAnyCancellableStoresInArrayCollections() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
            }

            let model = CounterModel()
            var values: [Int] = []
            var cancellables: [AnyCancellable] = []

            model.$value.sink { value in
                values.append(value)
            }.store(in: &cancellables)

            XCTAssertEqual(cancellables.count, 1)
            XCTAssertEqual(values, [0])

            model.value = 1
            XCTAssertEqual(values, [0, 1])

            cancellables.removeAll()
            model.value = 2

            XCTAssertEqual(values, [0, 1])
        }
    }

    func testPublishedPublisherMapAndRemoveDuplicatesChain() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 1
            }

            let model = CounterModel()
            var labels: [String] = []

            let cancellable = model.$value
                .map { "VALUE \($0)" }
                .removeDuplicates()
                .sink { label in
                    labels.append(label)
                }

            XCTAssertEqual(labels, ["VALUE 1"])

            model.value = 1
            model.value = 2
            model.value = 2
            model.value = 3

            XCTAssertEqual(labels, ["VALUE 1", "VALUE 2", "VALUE 3"])

            cancellable.cancel()
            model.value = 4

            XCTAssertEqual(labels, ["VALUE 1", "VALUE 2", "VALUE 3"])
        }
    }

    func testPublishedPublisherRemoveDuplicatesSupportsCustomPredicate() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
            }

            let model = CounterModel()
            var values: [Int] = []

            let cancellable = model.$value
                .removeDuplicates { previous, next in
                    previous % 2 == next % 2
                }
                .sink { value in
                    values.append(value)
                }

            model.value = 2
            model.value = 4
            model.value = 5
            model.value = 7
            model.value = 8

            XCTAssertEqual(values, [0, 5, 8])

            cancellable.cancel()
        }
    }

    func testPublishedPublisherFilterCompactMapAndDropFirstChain() async {
        await MainActor.run {
            final class InputModel: ObservableObject {
                @Published var text = ""
            }

            let model = InputModel()
            var values: [Int] = []

            let cancellable = model.$text
                .dropFirst()
                .filter { !$0.isEmpty }
                .compactMap { Int($0) }
                .sink { value in
                    values.append(value)
                }

            model.text = ""
            model.text = "7"
            model.text = "skip"
            model.text = "8"

            XCTAssertEqual(values, [7, 8])

            cancellable.cancel()
            model.text = "9"

            XCTAssertEqual(values, [7, 8])
        }
    }

    func testOnReceiveAcceptsFilteredPublishedPublisherChain() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            let model = CounterModel()
            var values: [Int] = []

            host.setComponents {
                [
                    Text("VALUE")
                        .onReceive(model.$value.dropFirst().filter { $0.isMultiple(of: 2) }) { value in
                            values.append(value)
                        }
                        .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()
            model.value = 1
            model.value = 2
            model.value = 3
            model.value = 4

            XCTAssertEqual(values, [2, 4])
        }
    }

    func testJustPublisherSendsImmediateValueAndSupportsOperators() async {
        await MainActor.run {
            var values: [String] = []

            _ = Just(4)
                .map { $0 * 2 }
                .filter { $0 > 4 }
                .sink { value in
                    values.append("VALUE \(value)")
                }

            XCTAssertEqual(values, ["VALUE 8"])
        }
    }

    func testPublisherAssignWritesReferenceKeyPathAndCancels() async {
        await MainActor.run {
            final class SourceModel: ObservableObject {
                @Published var value = 0
            }

            final class TargetModel {
                var value = -1
            }

            let source = SourceModel()
            let target = TargetModel()
            let cancellable = source.$value.assign(to: \.value, on: target)

            XCTAssertEqual(target.value, 0)

            source.value = 3
            XCTAssertEqual(target.value, 3)

            cancellable.cancel()
            source.value = 4

            XCTAssertEqual(target.value, 3)
        }
    }

    func testOnReceiveAcceptsJustPublisher() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            var values: [String] = []

            host.setComponents {
                [
                    Text("VALUE")
                        .onReceive(Just("READY")) { value in
                            values.append(value)
                        }
                        .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()

            XCTAssertEqual(values, ["READY"])
        }
    }

    func testPublisherEraseToAnyPublisherPreservesSubscriptionBehavior() async {
        await MainActor.run {
            final class SourceModel: ObservableObject {
                @Published var value = 0
            }

            let source = SourceModel()
            let publisher = source.$value
                .dropFirst()
                .map { "VALUE \($0)" }
                .eraseToAnyPublisher()
            var values: [String] = []

            let cancellable = publisher.sink { value in
                values.append(value)
            }

            source.value = 1
            source.value = 2

            XCTAssertEqual(values, ["VALUE 1", "VALUE 2"])

            cancellable.cancel()
            source.value = 3

            XCTAssertEqual(values, ["VALUE 1", "VALUE 2"])
        }
    }

    func testOnReceiveAcceptsAnyPublisher() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            let model = CounterModel()
            let publisher = model.$value
                .dropFirst()
                .filter { $0 > 1 }
                .eraseToAnyPublisher()
            var values: [Int] = []

            host.setComponents {
                [
                    Text("VALUE")
                        .onReceive(publisher) { value in
                            values.append(value)
                        }
                        .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()
            model.value = 1
            model.value = 2
            model.value = 3

            XCTAssertEqual(values, [2, 3])
        }
    }

    func testPassthroughSubjectSendsOnlyAfterSubscriptionAndCancels() async {
        await MainActor.run {
            let subject = PassthroughSubject<Int, Never>()
            var values: [Int] = []

            subject.send(1)

            let cancellable =
                subject
                .filter { $0.isMultiple(of: 2) }
                .sink { value in
                    values.append(value)
                }

            subject.send(2)
            subject.send(3)
            subject.send(4)

            XCTAssertEqual(values, [2, 4])

            cancellable.cancel()
            subject.send(6)

            XCTAssertEqual(values, [2, 4])
        }
    }

    func testCurrentValueSubjectReplaysCurrentValueAndPublishesValueWrites() async {
        await MainActor.run {
            let subject = CurrentValueSubject<String, Never>("ALPHA")
            var values: [String] = []

            let cancellable =
                subject
                .removeDuplicates()
                .sink { value in
                    values.append(value)
                }

            subject.send("BETA")
            subject.value = "BETA"
            subject.value = "GAMMA"

            XCTAssertEqual(subject.value, "GAMMA")
            XCTAssertEqual(values, ["ALPHA", "BETA", "GAMMA"])

            cancellable.cancel()
            subject.value = "DELTA"

            XCTAssertEqual(subject.value, "DELTA")
            XCTAssertEqual(values, ["ALPHA", "BETA", "GAMMA"])
        }
    }

    func testOnReceiveAcceptsPassthroughSubjectPublisher() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            let subject = PassthroughSubject<String, Never>()
            var values: [String] = []

            host.setComponents {
                [
                    Text("VALUE")
                        .onReceive(subject.eraseToAnyPublisher()) { value in
                            values.append(value)
                        }
                        .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()

            subject.send("READY")
            subject.send("DONE")

            XCTAssertEqual(values, ["READY", "DONE"])
        }
    }

    func testPassthroughSubjectVoidSendConveniencePublishesUnitValues() async {
        await MainActor.run {
            let subject = PassthroughSubject<Void, Never>()
            var count = 0

            let cancellable = subject.sink {
                count += 1
            }

            subject.send()
            subject.send(())

            XCTAssertEqual(count, 2)

            cancellable.cancel()
            subject.send()

            XCTAssertEqual(count, 2)
        }
    }

    func testObservableObjectPublisherSupportsSinkSubscriptions() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                var value = 0

                func increment() {
                    value += 1
                    objectWillChange.send()
                }
            }

            let model = CounterModel()
            var notifications = 0

            let cancellable = model.objectWillChange.sink {
                notifications += 1
            }

            model.increment()
            model.increment()

            XCTAssertEqual(notifications, 2)

            cancellable.cancel()
            model.increment()

            XCTAssertEqual(notifications, 2)
        }
    }

    func testOnReceiveAcceptsObservableObjectPublisher() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                func notify() {
                    objectWillChange.send()
                }
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            let model = CounterModel()
            var notifications = 0

            host.setComponents {
                [
                    Text("VALUE")
                        .onReceive(model.objectWillChange) {
                            notifications += 1
                        }
                        .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()

            model.notify()
            model.notify()

            XCTAssertEqual(notifications, 2)
        }
    }

    func testOnReceiveSubscribesToPublishedPublisherWhileRendered() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 100) },
                invalidateHandler: {}
            )
            let model = CounterModel()
            var values: [Int] = []
            var isVisible = true

            host.setComponents {
                guard isVisible else {
                    return []
                }

                return [
                    Text("VALUE")
                        .onReceive(model.$value) { value in
                            values.append(value)
                        }
                        .makeComponent(context: context)
                ]
            }

            runtime.setRootSize(IntSize(width: 200, height: 100))
            _ = runtime.renderFrame()
            model.value = 1

            isVisible = false
            host.reload()
            model.value = 2

            XCTAssertEqual(values, [0, 1])
        }
    }

    func testObservedObjectDynamicMemberProjectionFeedsRetainedControls() async {
        await MainActor.run {
            final class FormModel: ObservableObject {
                @Published var isEnabled = false
                @Published var title = "ALPHA"
            }

            struct ObservedEditor: View {
                @ObservedObject var model: FormModel

                var body: some View {
                    VStack {
                        Toggle("ENABLED", isOn: $model.isEnabled)
                        TextField("TITLE", text: $model.title.animation(.easeInOut))
                    }
                }
            }

            let model = FormModel()
            let node = makeNode(ObservedEditor(model: model))
            let controls = focusableNodes(in: node)

            controls.first?.onActivate?()
            controls.last?.onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertTrue(model.isEnabled)
            XCTAssertEqual(model.title, "ALPHAz")
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

    func testStateObjectDynamicMemberProjectionFeedsRetainedControls() async {
        await MainActor.run {
            final class FormModel: ObservableObject {
                @Published var title = "ALPHA"
            }

            struct StateObjectEditor: View {
                @StateObject var model: FormModel

                var body: some View {
                    TextField("TITLE", text: $model.title.transaction(Transaction()))
                }
            }

            let model = FormModel()
            let node = makeNode(StateObjectEditor(model: model))

            firstFocusable(in: node)?.onKeyDown?(KeyboardEvent(keyCode: 0x5A))

            XCTAssertEqual(model.title, "ALPHAz")
        }
    }

    func testInspectorModifierComposesInspectorWhenPresented() async {
        await MainActor.run {
            var isPresented = true
            let node = makeNode(
                Text("MAIN")
                    .inspector(isPresented: .init(get: { isPresented }, set: { isPresented = $0 })) {
                        Text("INSPECTOR")
                    }
            )

            XCTAssertTrue(allTexts(in: node).contains("MAIN"))
            XCTAssertTrue(allTexts(in: node).contains("INSPECTOR"))
        }
    }

    func testNavigationTransitionModifierStoresRetainedTransition() async {
        await MainActor.run {
            let node = makeNode(
                Text("PAGE")
                    .navigationTransition(.zoom(sourceID: "hero", in: Namespace().wrappedValue))
            )

            let textNode = firstTextNode(in: node)!
            XCTAssertNotNil(textNode.navigationTransition)
        }
    }

    func testFileExporterModifierStoresConfiguration() async {
        await MainActor.run {
            var isPresented = false
            let node = makeNode(
                Text("DOC")
                    .fileExporter(
                        isPresented: .init(get: { isPresented }, set: { isPresented = $0 }),
                        document: "hello",
                        contentType: .plainText,
                        defaultFilename: "doc.txt",
                        onCompletion: { _ in }
                    )
            )

            let textNode = firstTextNode(in: node)!
            XCTAssertNotNil(textNode.fileExporterConfiguration)
            XCTAssertEqual(textNode.fileExporterConfiguration?.defaultFilename, "doc.txt")
        }
    }

    func testFileImporterModifierStoresConfiguration() async {
        await MainActor.run {
            var isPresented = false
            let node = makeNode(
                Text("IMPORT")
                    .fileImporter(
                        isPresented: .init(get: { isPresented }, set: { isPresented = $0 }),
                        allowedContentTypes: [.plainText],
                        onCompletion: { _ in }
                    )
            )

            let textNode = firstTextNode(in: node)!
            XCTAssertNotNil(textNode.fileImporterConfiguration)
            XCTAssertEqual(
                textNode.fileImporterConfiguration?.allowedContentTypes.first?.identifier, UTType.plainText.identifier)
        }
    }

    func testOnScrollVisibilityChangeAppendsScrollObservation() async {
        await MainActor.run {
            let node = makeNode(
                ScrollView {
                    Text("VIS")
                }
                .onScrollVisibilityChange { _ in }
            )

            XCTAssertTrue(node.scrollObservations.contains("visibility:threshold:0.5"))
        }
    }

    func testOnScrollTargetVisibilityChangeAppendsScrollObservation() async {
        await MainActor.run {
            let node = makeNode(
                ScrollView {
                    Text("TARGET")
                }
                .onScrollTargetVisibilityChange(idType: String.self) { (_: [String]) in }
            )

            XCTAssertTrue(node.scrollObservations.contains("targetVisibility:idType:String,threshold:0.5"))
        }
    }

    func testOnKeyPressModifierAttachesKeyDownHandler() async {
        await MainActor.run {
            var receivedPress: KeyPress?
            let node = makeNode(
                Text("KEY")
                    .onKeyPress(keys: [.return]) { press in
                        receivedPress = press
                        return .handled
                    }
            )

            let textNode = firstTextNode(in: node)!
            textNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            XCTAssertNotNil(receivedPress)
            XCTAssertEqual(receivedPress?.key, .return)

            var ignoredCount = 0
            let ignoredNode = makeNode(
                Text("IGNORE")
                    .onKeyPress(keys: [.space]) { _ in
                        ignoredCount += 1
                        return .handled
                    }
            )
            let ignoredTextNode = firstTextNode(in: ignoredNode)!
            ignoredTextNode.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            XCTAssertEqual(ignoredCount, 0)
        }
    }

    func testMatchedGeometryEffectStoresRetainedMetadata() async {
        await MainActor.run {
            let namespace = Namespace()
            let node = makeNode(
                Text("SOURCE")
                    .matchedGeometryEffect(id: "card", in: namespace.wrappedValue)
            )

            let textNode = firstTextNode(in: node)!
            XCTAssertNotNil(textNode.matchedGeometryEffect)
            XCTAssertEqual(textNode.matchedGeometryEffect?.elementID, "card")
            XCTAssertTrue(textNode.matchedGeometryEffect?.isSource ?? false)
        }
    }

    func testOnGeometryChangeAttachesLayoutHandler() async {
        await MainActor.run {
            var observedSize: Size?
            let node = makeNode(
                Text("GEO")
                    .onGeometryChange(for: Size.self) { proxy in
                        proxy.size
                    } action: { newValue, _ in
                        observedSize = newValue
                    }
            )

            let textNode = firstTextNode(in: node)!
            XCTAssertNotNil(textNode.onLayout)
            textNode.onLayout?(Rect(origin: .zero, size: Size(width: 100, height: 200)))
            XCTAssertEqual(observedSize, Size(width: 100, height: 200))
        }
    }

    func testOnScrollPhaseChangeAppendsScrollObservation() async {
        await MainActor.run {
            let node = makeNode(
                ScrollView {
                    Text("PHASE")
                }
                .onScrollPhaseChange { _, _ in }
            )

            XCTAssertTrue(node.scrollObservations.contains("phase"))
        }
    }

}
private func waitForAsyncTaskCounter(_ counter: AsyncTaskCounter, toReach expectedValue: Int) async {
    for _ in 0..<50 {
        if await counter.value() >= expectedValue {
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
private func waitForTaskStart(_ recorder: AsyncTaskLifecycleRecorder, toReach expectedValue: Int) async {
    for _ in 0..<50 {
        if await recorder.startCount() >= expectedValue {
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
private func waitForTaskCancellation(_ recorder: AsyncTaskLifecycleRecorder, toReach expectedValue: Int) async {
    for _ in 0..<50 {
        if await recorder.cancellations() >= expectedValue {
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
private func cancellableTask(id: Int, recorder: AsyncTaskLifecycleRecorder) async {
    await recorder.recordStart(id)
    await withTaskCancellationHandler {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    } onCancel: {
        Task {
            await recorder.recordCancellation()
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

/// The value a colour takes once the build context has resolved it for the
/// tests' default (dark) appearance.
///
/// Identity for a colour the test mixed itself, and the published dark twin
/// for one of the system colours (`SystemColorPalette`) — which is why an
/// expectation written as `Color.red` needs this wrapper while
/// `Color(red: 0.2, ...)` does not.
private func inDarkAppearance(_ color: Color) -> Color {
    color.resolvedForVisualEnvironment(
        colorScheme: .dark, contrast: .standard, backgroundProminence: .standard)
}

/// The same, for a gradient: every stop resolves, so a gradient built from
/// `[.red, .blue]` is not the gradient the node carries in a dark window.
private func inDarkAppearance(_ gradient: WinSwiftUI.LinearGradient) -> WinSwiftUI.LinearGradient {
    gradient.resolvedForVisualEnvironment(
        colorScheme: .dark, contrast: .standard, backgroundProminence: .standard)
}
@MainActor
private func makeRuntimeNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600),
    onInvalidate: @escaping () -> Void = {}
) -> (runtime: RetainedViewRuntime, node: ViewNode) {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    node.frame = Rect(origin: .zero, size: size)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    _ = runtime.renderFrame()
    return (runtime, node)
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
        0x00, 0xFF, 0x00, 0xFF,
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
private func firstBitmapNode(in node: ViewNode) -> ViewNode? {
    if node.bitmapSurface != nil {
        return node
    }

    for child in node.children {
        if let bitmapNode = firstBitmapNode(in: child) {
            return bitmapNode
        }
    }

    return nil
}
/// A list's *row* children, skipping the hairline rules the default list
/// style interleaves between adjacent rows.
@MainActor
private func listRows(of node: ViewNode) -> [ViewNode] {
    let separator = ControlPalette.darkStandard.separator
    return node.children.filter { child in
        !(child.backgroundColor == separator && child.text == nil && child.children.isEmpty)
    }
}

@MainActor
private func allTextColors(in node: ViewNode) -> [Color] {
    var result: [Color] = []
    if node.text != nil {
        result.append(node.textStyle.color)
    }
    for child in node.children {
        result.append(contentsOf: allTextColors(in: child))
    }
    return result
}

/// NSStepper is a *vertical* joined pair — one bezel holding an up chevron
/// over a down chevron — beside the label, not the side-by-side
/// decrement/increment pills that used to sit as `children[1]`/`children[2]`.
@MainActor
private func stepperIncrement(of node: ViewNode) -> ViewNode {
    // The bezel holds [increment][seam rule][decrement].
    node.children[1].children[0]
}

@MainActor
private func stepperDecrement(of node: ViewNode) -> ViewNode {
    node.children[1].children[2]
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
/// Returns the child at `index` inside a presented overlay container
/// (`[base, overlay]` roots built by the retained presentation helpers:
/// scrim at index 0, panel at index 1), asserting the overlay carries the
/// expected `<kind>-overlay` tag.
@MainActor
private func presentationOverlayChild(
    in node: ViewNode,
    overlayTag: String,
    index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) -> ViewNode? {
    guard let overlay = node.children.last, overlay.nodeTag == overlayTag else {
        XCTFail("Expected presentation overlay tagged \(overlayTag)", file: file, line: line)
        return nil
    }
    guard overlay.children.count > index else {
        XCTFail(
            "Expected presentation overlay \(overlayTag) to have a child at index \(index)",
            file: file,
            line: line
        )
        return nil
    }
    return overlay.children[index]
}
final class WindowTitleBarTests: XCTestCase {
    func testWindowTitleBarVisibilityConfiguration() async {
        await MainActor.run {
            let scene = Window("Test") {
                EmptyView()
            }
            .windowTitleBar(.hidden)

            let config = scene.makeWindowConfiguration()
            XCTAssertEqual(config.titleBarVisibility, WindowTitleBarVisibility.hidden)
        }
    }

    func testWindowTitleBarVisibilityDefaultsToNil() async {
        await MainActor.run {
            let scene = Window("Test") {
                EmptyView()
            }

            let config = scene.makeWindowConfiguration()
            XCTAssertNil(config.titleBarVisibility)
        }
    }

    func testWindowTitleBarVisibilityKinds() {
        XCTAssertEqual(WindowTitleBarVisibility.visible.kind, .visible)
        XCTAssertEqual(WindowTitleBarVisibility.hidden.kind, .hidden)
        XCTAssertEqual(WindowTitleBarVisibility.hiddenInFullScreen.kind, .hiddenInFullScreen)
        XCTAssertEqual(WindowTitleBarVisibility.automatic.kind, .automatic)
    }
}
final class WindowGroupInitTests: XCTestCase {
    func testWindowGroupInitWithID() async {
        await MainActor.run {
            let scene = WindowGroup(id: "myWindowGroup") {
                AnyView(EmptyView())
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertEqual(config.windowID, "myWindowGroup")
            XCTAssertEqual(config.title, "WinSwiftUI")
        }
    }

    func testWindowGroupInitWithoutID() async {
        await MainActor.run {
            let scene = WindowGroup {
                AnyView(EmptyView())
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertNil(config.windowID)
            XCTAssertEqual(config.title, "WinSwiftUI")
        }
    }

    func testWindowGroupForInitStoresTypeAndBuilder() async {
        await MainActor.run {
            struct Item: Codable, Hashable {
                let name: String
            }
            let scene = WindowGroup(for: Item.self) { item in
                Text(item.wrappedValue.name)
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertTrue(config.content.isEmpty)
            XCTAssertTrue(config.forType == Item.self)
            XCTAssertNotNil(config.dataBoundContent)

            let views = config.dataBoundContent?(AnyHashable(Item(name: "Test")))
            XCTAssertEqual(views?.count, 1)
        }
    }

    func testWindowGroupForInitWithID() async {
        await MainActor.run {
            struct Item: Codable, Hashable {
                let id: Int
            }
            let scene = WindowGroup("Items", id: "itemGroup", for: Item.self) { item in
                Text("\(item.wrappedValue.id)")
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertEqual(config.title, "Items")
            XCTAssertEqual(config.windowID, "itemGroup")
            XCTAssertTrue(config.forType == Item.self)
        }
    }
}
final class WindowInitTests: XCTestCase {
    func testWindowForInitStoresTypeAndBuilder() async {
        await MainActor.run {
            struct Item: Codable, Hashable {
                let name: String
            }
            let scene = Window("Item Window", for: Item.self) { item in
                Text(item.wrappedValue.name)
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertTrue(config.content.isEmpty)
            XCTAssertTrue(config.forType == Item.self)
            XCTAssertNotNil(config.dataBoundContent)

            let views = config.dataBoundContent?(AnyHashable(Item(name: "A")))
            XCTAssertEqual(views?.count, 1)
        }
    }

    func testWindowForInitWithID() async {
        await MainActor.run {
            struct Item: Codable, Hashable {
                let id: Int
            }
            let scene = Window("Item", id: "itemWindow", for: Item.self) { item in
                Text("\(item.wrappedValue.id)")
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertEqual(config.windowID, "itemWindow")
            XCTAssertTrue(config.forType == Item.self)
        }
    }
}
final class WindowSceneInitTests: XCTestCase {
    func testWindowSceneForInitStoresTypeAndBuilder() async {
        await MainActor.run {
            struct Item: Codable, Hashable {
                let name: String
            }
            let scene = WindowScene("Item Scene", for: Item.self) { item in
                Text(item.wrappedValue.name)
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertTrue(config.content.isEmpty)
            XCTAssertTrue(config.forType == Item.self)
            XCTAssertNotNil(config.dataBoundContent)

            let views = config.dataBoundContent?(AnyHashable(Item(name: "A")))
            XCTAssertEqual(views?.count, 1)
        }
    }

    func testWindowSceneForInitWithID() async {
        await MainActor.run {
            struct Item: Codable, Hashable {
                let id: Int
            }
            let scene = WindowScene("Item", id: "itemScene", for: Item.self) { item in
                Text("\(item.wrappedValue.id)")
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertEqual(config.windowID, "itemScene")
            XCTAssertTrue(config.forType == Item.self)
        }
    }
}
final class DocumentGroupTests: XCTestCase {
    func testDocumentGroupEditingInitForFileDocument() async {
        await MainActor.run {
            struct TestDoc: FileDocument {
                static var readableContentTypes: [UTType] { [.plainText] }
                init() {}
                init(configuration: ReadConfiguration) throws { self.init() }
                func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
                    FileWrapper()
                }
            }
            var contentBuilds = 0
            let scene = DocumentGroup(editing: TestDoc.self) { config in
                contentBuilds += 1
                // Exercise the typed FileDocumentConfiguration without a vacuous
                // `is TestDoc` check (always true for FileDocumentConfiguration<TestDoc>).
                return Text(config.isEditable ? "EDIT" : "VIEW")
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertTrue(config.isDocumentGroup)
            XCTAssertEqual(config.title, "Untitled")
            XCTAssertTrue(config.content.isEmpty)
            XCTAssertNotNil(config.documentScene)
            XCTAssertNil(config.documentWindowContext)
            XCTAssertEqual(contentBuilds, 0, "A declaration cannot fabricate an empty document for its builder.")
        }
    }
}
final class NewDocumentButtonTests: XCTestCase {
    func testNewDocumentButtonDefaultTitle() async {
        await MainActor.run {
            let button = NewDocumentButton()
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let component = button.makeComponent(context: context)
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = component.makeNode(runtime: runtime)
            // Should render a button node with children
            XCTAssertFalse(node.children.isEmpty)
        }
    }

    func testNewDocumentButtonCustomTitle() async {
        await MainActor.run {
            let button = NewDocumentButton("New File")
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let component = button.makeComponent(context: context)
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = component.makeNode(runtime: runtime)
            XCTAssertFalse(node.children.isEmpty)
        }
    }

    func testNewDocumentButtonCustomAction() async {
        await MainActor.run {
            var didTrigger = false
            let button = NewDocumentButton {
                didTrigger = true
            }
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let component = button.makeComponent(context: context)
            let runtime = RetainedViewRuntime(root: ViewNode())
            _ = component.makeNode(runtime: runtime)
            // Button should be renderable with custom action
            XCTAssertFalse(didTrigger)  // Action not triggered just by rendering
        }
    }

    func testWithObservationTrackingDetectsPropertyChanges() async {
        await MainActor.run {
            final class Person: Observable {
                let registrar = ObservationRegistrar()
                private var _name: String = "Alice"
                var name: String {
                    get {
                        registrar.access(subject: self, keyPath: \.name)
                        return _name
                    }
                    set {
                        registrar.willSet(subject: self, keyPath: \.name)
                        _name = newValue
                        registrar.didSet(subject: self, keyPath: \.name)
                    }
                }
            }

            let person = Person()
            var changeCount = 0

            func readName() -> String {
                withObservationTracking(
                    apply: { person.name },
                    onChange: { changeCount += 1 }
                )
            }

            XCTAssertEqual(readName(), "Alice")
            XCTAssertEqual(changeCount, 0)

            person.name = "Bob"
            XCTAssertEqual(changeCount, 1)

            person.name = "Charlie"
            XCTAssertEqual(changeCount, 1)  // one-shot tracking, no re-registration
        }
    }

    func testWithObservationTrackingMultipleProperties() async {
        await MainActor.run {
            final class Counter: Observable {
                let registrar = ObservationRegistrar()
                private var _value = 0
                var value: Int {
                    get {
                        registrar.access(subject: self, keyPath: \.value)
                        return _value
                    }
                    set {
                        registrar.willSet(subject: self, keyPath: \.value)
                        _value = newValue
                        registrar.didSet(subject: self, keyPath: \.value)
                    }
                }
            }

            let counter = Counter()
            var didChange = false

            let result = withObservationTracking(
                apply: { counter.value + 10 },
                onChange: { didChange = true }
            )
            XCTAssertEqual(result, 10)
            XCTAssertFalse(didChange)

            counter.value = 5
            XCTAssertTrue(didChange)
        }
    }

    func testObservationRegistrarWithMutation() async {
        await MainActor.run {
            final class Item: Observable {
                let registrar = ObservationRegistrar()
                private var _price = 10.0
                var price: Double {
                    get {
                        registrar.access(subject: self, keyPath: \.price)
                        return _price
                    }
                    set {
                        registrar.withMutation(of: self, keyPath: \.price) {
                            _price = newValue
                        }
                    }
                }
            }

            let item = Item()
            var triggered = false

            let _ = withObservationTracking(
                apply: { item.price },
                onChange: { triggered = true }
            )

            item.price = 20.0
            XCTAssertTrue(triggered)
        }
    }
}
final class ClipboardButtonTests: XCTestCase {
    func testPasteButtonComponentCapturesSupportedContentTypes() async {
        await MainActor.run {
            let button = PasteButton(supportedContentTypes: [UTType.plainText]) { items in
                _ = items
            }
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let component = button.makeComponent(context: context)
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = component.makeNode(runtime: runtime)
            XCTAssertFalse(node.children.isEmpty)
        }
    }

    func testCopyButtonComponentCapturesItems() async {
        await MainActor.run {
            let button = CopyButton(item: "hello")
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let component = button.makeComponent(context: context)
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = component.makeNode(runtime: runtime)
            XCTAssertFalse(node.children.isEmpty)
        }
    }

    func testCutButtonComponentCapturesItems() async {
        await MainActor.run {
            let button = CutButton(item: "world")
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let component = button.makeComponent(context: context)
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = component.makeNode(runtime: runtime)
            XCTAssertFalse(node.children.isEmpty)
        }
    }

    func testShareLinkComponentCapturesItems() async {
        await MainActor.run {
            let link = ShareLink(item: "share me") {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let component = link.makeComponent(context: context)
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = component.makeNode(runtime: runtime)
            XCTAssertFalse(node.children.isEmpty)
        }
    }
}
final class TransitionReaderTests: XCTestCase {
    func testTransitionReaderInitWithContent() async {
        await MainActor.run {
            let reader = TransitionReader { proxy in
                Text("isActive: \(proxy.isActive)")
            }
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let component = reader.makeComponent(context: context)
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = component.makeNode(runtime: runtime)
            XCTAssertTrue(allTexts(in: node).contains("isActive: false"))
        }
    }

    func testTransitionProxyDefaultValues() async {
        await MainActor.run {
            let proxy = TransitionProxy()
            XCTAssertFalse(proxy.isActive)
            XCTAssertEqual(proxy.value, 0)
        }
    }

    func testTransitionProxyEquatable() async {
        await MainActor.run {
            let a = TransitionProxy(isActive: true, value: 0.5)
            let b = TransitionProxy(isActive: true, value: 0.5)
            let c = TransitionProxy(isActive: false, value: 0.5)
            XCTAssertEqual(a, b)
            XCTAssertNotEqual(a, c)
        }
    }
}
final class CommandsAndSceneTests: XCTestCase {
    func testCommandsModifierAttachesToWindowConfiguration() async {
        await MainActor.run {
            let scene = WindowGroup {
                Text("Hello")
            }
            .commands {
                CommandMenu("Custom") {
                    Button("Action", action: {})
                }
            }

            let config = scene.makeWindowConfiguration()
            XCTAssertNotNil(config.commands)
            XCTAssertFalse(config.commands!.menus.isEmpty)
            XCTAssertEqual(config.commands!.menus.first?.name, "Custom")
        }
    }

    func testCommandsRemovedModifierEmptiesConfiguration() async {
        await MainActor.run {
            let scene = WindowGroup {
                Text("Hello")
            }
            .commands {
                CommandMenu("Custom") {
                    Button("Action", action: {})
                }
            }
            .commandsRemoved()

            let config = scene.makeWindowConfiguration()
            XCTAssertNotNil(config.commands)
            XCTAssertTrue(config.commands!.menus.isEmpty)
            XCTAssertTrue(config.commands!.groups.isEmpty)
        }
    }

    func testCommandsReplacedModifierOverwritesConfiguration() async {
        await MainActor.run {
            let scene = WindowGroup {
                Text("Hello")
            }
            .commands {
                CommandMenu("Old") {
                    Button("Old Action", action: {})
                }
            }
            .commandsReplaced {
                CommandMenu("New") {
                    Button("New Action", action: {})
                }
            }

            let config = scene.makeWindowConfiguration()
            XCTAssertNotNil(config.commands)
            XCTAssertEqual(config.commands!.menus.count, 1)
            XCTAssertEqual(config.commands!.menus.first?.name, "New")
        }
    }

    func testSettingsSceneIsMarkedAsSettingsWindow() async {
        await MainActor.run {
            let scene = Settings {
                Text("Preferences")
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertTrue(config.isSettingsWindow)
            XCTAssertEqual(config.title, "Settings")
        }
    }

    func testMenuBarExtraSceneIsMarkedAsMenuBarExtra() async {
        await MainActor.run {
            let scene = MenuBarExtra("Extra") {
                Text("Menu Content")
            }
            let config = scene.makeWindowConfiguration()
            XCTAssertTrue(config.isMenuBarExtra)
            XCTAssertEqual(config.title, "Extra")
        }
    }
}
