import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUIEnvironmentConsistencyTests: XCTestCase {
    func testEnvironmentEnabledValueDisablesButtonsAndPreventsActivation() async {
        await MainActor.run {
            var didActivate = false
            let node = makeEnvironmentConsistencyNode(
                Button("Save") {
                    didActivate = true
                }
                .environment(\.isEnabled, false)
            )

            XCTAssertFalse(node.isFocusable)
            XCTAssertFalse(node.isHitTestVisible)
            XCTAssertNil(node.onActivate)
            node.onActivate?()
            XCTAssertFalse(didActivate)
            XCTAssertEqual(node.children.first?.opacity, ControlPalette.disabledContentOpacity)
        }
    }

    func testEnvironmentEnabledValueDisablesEveryDescendantControl() async {
        await MainActor.run {
            var isOn = false
            var text = "Original"
            var value = 0.5

            let node = makeEnvironmentConsistencyNode(
                VStack {
                    Toggle(
                        "Enabled",
                        isOn: Binding(get: { isOn }, set: { isOn = $0 })
                    )
                    TextField(
                        "Name",
                        text: Binding(get: { text }, set: { text = $0 })
                    )
                    Slider(
                        value: Binding(get: { value }, set: { value = $0 })
                    )
                }
                .environment(\.isEnabled, false)
            )

            XCTAssertNil(firstEnvironmentConsistencyFocusable(in: node))
            XCTAssertFalse(node.children[0].children[1].isHitTestVisible)
            XCTAssertFalse(node.children[1].isHitTestVisible)
            XCTAssertNil(node.children[2].onDragStart)
            XCTAssertFalse(isOn)
            XCTAssertEqual(text, "Original")
            XCTAssertEqual(value, 0.5)
        }
    }

    func testDisabledAncestorCannotBeReenabledByNestedEnvironmentOverride() async {
        await MainActor.run {
            var didActivate = false

            let node = makeEnvironmentConsistencyNode(
                VStack {
                    EnvironmentConsistencyEnabledReader()
                        .environment(\.isEnabled, true)
                    Button("Save") {
                        didActivate = true
                    }
                    .environment(\.isEnabled, true)
                }
                .disabled(true)
            )

            XCTAssertEqual(node.children[0].text, "DISABLED")
            XCTAssertFalse(node.children[1].isFocusable)
            XCTAssertFalse(node.children[1].isHitTestVisible)
            node.children[1].onActivate?()
            XCTAssertFalse(didActivate)
        }
    }

    func testEnvironmentEnabledReaderAgreesWithRenderedControls() async {
        await MainActor.run {
            let node = makeEnvironmentConsistencyNode(
                VStack {
                    EnvironmentConsistencyEnabledReader()
                    Button("Save") {}
                }
                .environment(\.isEnabled, false)
            )

            XCTAssertEqual(node.children[0].text, "DISABLED")
            XCTAssertFalse(node.children[1].isFocusable)
            XCTAssertFalse(node.children[1].isHitTestVisible)
        }
    }

    func testButtonStyleModifierUpdatesEnvironmentReader() async {
        await MainActor.run {
            let plainNode = makeEnvironmentConsistencyNode(
                EnvironmentConsistencyButtonStyleReader()
                    .buttonStyle(.plain)
            )
            let prominentNode = makeEnvironmentConsistencyNode(
                EnvironmentConsistencyButtonStyleReader()
                    .buttonStyle(.borderedProminent)
            )

            XCTAssertEqual(plainNode.text, "PLAIN")
            XCTAssertEqual(prominentNode.text, "PROMINENT")
        }
    }

    func testEnvironmentButtonStyleUpdatesChromeAndNearestOverrideWins() async {
        await MainActor.run {
            let accent = Color(red: 0.21, green: 0.61, blue: 0.37, alpha: 1)
            let node = makeEnvironmentConsistencyNode(
                VStack {
                    Button("Prominent") {}
                        .environment(\.buttonStyle, .borderedProminent)
                    Button("Plain") {}
                    EnvironmentConsistencyButtonStyleReader()
                        .environment(\.buttonStyle, .borderedProminent)
                }
                .buttonStyle(.plain)
                .tint(accent)
            )

            XCTAssertEqual(node.children[0].backgroundColor, accent)
            XCTAssertEqual(node.children[1].backgroundColor, .clear)
            XCTAssertEqual(node.children[2].text, "PROMINENT")
        }
    }

    func testPickerStyleModifierUpdatesEnvironmentReader() async {
        await MainActor.run {
            let menuNode = makeEnvironmentConsistencyNode(
                EnvironmentConsistencyPickerStyleReader()
                    .pickerStyle(.menu)
            )
            let inlineNode = makeEnvironmentConsistencyNode(
                EnvironmentConsistencyPickerStyleReader()
                    .pickerStyle(.inline)
            )

            XCTAssertEqual(menuNode.text, "MENU")
            XCTAssertEqual(inlineNode.text, "INLINE")
        }
    }

    func testEnvironmentPickerStyleBuildsInteractiveMenuChrome() async {
        await MainActor.run {
            var selection = "one"
            let node = makeEnvironmentConsistencyNode(
                Picker(
                    "Mode",
                    selection: Binding(get: { selection }, set: { selection = $0 })
                ) {
                    Text("One").tag("one")
                    Text("Two").tag("two")
                }
                .environment(\.pickerStyle, .menu)
            )

            let menu = node.children[1]
            XCTAssertNotNil(menu.onActivate)
            XCTAssertEqual(menu.children.count, 2)
            XCTAssertTrue(menu.children[1].isHidden)

            menu.onActivate?()
            XCTAssertFalse(menu.children[1].isHidden)
            menu.children[1].children[1].onActivate?()
            XCTAssertEqual(selection, "two")
        }
    }

    func testForegroundColorModifierAndEnvironmentStaySynchronized() async {
        await MainActor.run {
            let modifierNode = makeEnvironmentConsistencyNode(
                EnvironmentConsistencyForegroundReader()
                    .foregroundColor(.red)
            )
            let environmentNode = makeEnvironmentConsistencyNode(
                Text("Environment")
                    .environment(\.foregroundColor, Color.green)
            )
            let overrideNode = makeEnvironmentConsistencyNode(
                Text("Override")
                    .environment(\.foregroundColor, Color.green)
                    .foregroundColor(.red)
            )
            let resolvedGreen = Color.green.resolvedForVisualEnvironment(
                colorScheme: .dark,
                contrast: .standard,
                backgroundProminence: .standard
            )

            XCTAssertEqual(modifierNode.text, "RED")
            XCTAssertEqual(environmentNode.textStyle.color, resolvedGreen)
            XCTAssertEqual(overrideNode.textStyle.color, resolvedGreen)
        }
    }

    func testGradientForegroundClearsInheritedLegacyForegroundColor() async {
        await MainActor.run {
            let gradient = LinearGradient(
                colors: [.red, .blue],
                startPoint: .leading,
                endPoint: .trailing
            )
            let node = makeEnvironmentConsistencyNode(
                EnvironmentConsistencyForegroundReader()
                    .foregroundStyle(gradient)
                    .foregroundColor(.red)
            )

            XCTAssertEqual(node.text, "NONE")
        }
    }

    func testAccentColorModifierAndEnvironmentDriveInheritedTint() async {
        await MainActor.run {
            let accent = Color(red: 0.21, green: 0.61, blue: 0.37, alpha: 1)
            let modifierNode = makeEnvironmentConsistencyNode(
                EnvironmentConsistencyAccentReader()
                    .accentColor(accent)
            )
            let tintNode = makeEnvironmentConsistencyNode(
                EnvironmentConsistencyAccentReader()
                    .tint(accent)
            )
            let prominentNode = makeEnvironmentConsistencyNode(
                Button("Prominent") {}
                    .buttonStyle(.borderedProminent)
                    .environment(\.accentColor, accent)
            )

            XCTAssertEqual(modifierNode.text, "SYNCHRONIZED")
            XCTAssertEqual(tintNode.text, "SYNCHRONIZED")
            XCTAssertEqual(prominentNode.backgroundColor, accent)
        }
    }

    func testNearestAccentEnvironmentOverrideWinsOverInheritedTint() async {
        await MainActor.run {
            let inheritedTint = Color(red: 0.72, green: 0.24, blue: 0.31, alpha: 1)
            let localAccent = Color(red: 0.21, green: 0.61, blue: 0.37, alpha: 1)
            let node = makeEnvironmentConsistencyNode(
                VStack {
                    Button("Local") {}
                        .environment(\.accentColor, localAccent)
                    Button("Inherited") {}
                }
                .buttonStyle(.borderedProminent)
                .tint(inheritedTint)
            )

            XCTAssertEqual(node.children[0].backgroundColor, localAccent)
            XCTAssertEqual(node.children[1].backgroundColor, inheritedTint)
        }
    }
}

@MainActor
private func makeEnvironmentConsistencyNode<V: View>(_ view: V) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 800, height: 600) },
        invalidateHandler: {}
    )
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func firstEnvironmentConsistencyFocusable(in node: ViewNode) -> ViewNode? {
    if node.isFocusable {
        return node
    }
    for child in node.children {
        if let focusable = firstEnvironmentConsistencyFocusable(in: child) {
            return focusable
        }
    }
    return nil
}

@MainActor
private struct EnvironmentConsistencyEnabledReader: View {
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Text(isEnabled ? "ENABLED" : "DISABLED")
    }
}

@MainActor
private struct EnvironmentConsistencyButtonStyleReader: View {
    @Environment(\.buttonStyle) private var buttonStyle

    var body: some View {
        Text(buttonStyle == .plain ? "PLAIN" : buttonStyle == .borderedProminent ? "PROMINENT" : "AUTOMATIC")
    }
}

@MainActor
private struct EnvironmentConsistencyPickerStyleReader: View {
    @Environment(\.pickerStyle) private var pickerStyle

    var body: some View {
        Text(pickerStyle == .menu ? "MENU" : pickerStyle == .inline ? "INLINE" : "AUTOMATIC")
    }
}

@MainActor
private struct EnvironmentConsistencyForegroundReader: View {
    @Environment(\.foregroundColor) private var foregroundColor

    var body: some View {
        Text(foregroundColor == .red ? "RED" : foregroundColor == nil ? "NONE" : "OTHER")
    }
}

@MainActor
private struct EnvironmentConsistencyAccentReader: View {
    @Environment(\.accentColor) private var accentColor
    @Environment(\.tint) private var tint

    var body: some View {
        Text(accentColor != nil && accentColor == tint ? "SYNCHRONIZED" : "UNSYNCHRONIZED")
    }
}
