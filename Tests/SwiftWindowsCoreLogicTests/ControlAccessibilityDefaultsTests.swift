import Foundation
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsUI
@testable import WinSwiftUI

// Default accessibility metadata for retained controls and WinSwiftUI
// controls (Stabilization Roadmap, Phase 2): control builders seed sensible
// traits, names, and values so the accessibility projection produces useful
// control types without app authors writing accessibility modifiers.
// Explicit modifiers always win because they apply after the builders.

// MARK: - Helpers (main-actor, matching ViewNode isolation)

@MainActor
private let testPalette = SurfacePalette(
    idle: Color(red: 0.2, green: 0.2, blue: 0.2, alpha: 1),
    focused: Color(red: 0.3, green: 0.3, blue: 0.3, alpha: 1),
    pressed: Color(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
)

@MainActor
private func makeRuntime() -> RetainedViewRuntime {
    RetainedViewRuntime(root: ViewNode())
}

@MainActor
private func makeContext() -> ViewBuildContext {
    ViewBuildContext(
        canvasSizeProvider: { Size(width: 400, height: 600) },
        invalidateHandler: {}
    )
}

@MainActor
private func makeNode<V: View>(_ view: V, runtime: RetainedViewRuntime) -> ViewNode {
    view.makeComponent(context: makeContext()).makeNode(runtime: runtime)
}

@MainActor
private func findNode(in node: ViewNode, matching predicate: (ViewNode) -> Bool) -> ViewNode? {
    if predicate(node) { return node }
    for child in node.children {
        if let match = findNode(in: child, matching: predicate) { return match }
    }
    return nil
}

@MainActor
private func subtreeTexts(of node: ViewNode) -> [String] {
    var texts: [String] = node.text.map { [$0] } ?? []
    for child in node.children {
        texts.append(contentsOf: subtreeTexts(of: child))
    }
    return texts
}

// MARK: - Retained control builders (SwiftWindowsUI)

final class RetainedControlAccessibilityDefaultsTests: XCTestCase {
    func testButtonDefaultsToButtonTraitAndCombine() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: testPalette,
                children: [Controls.label("Go")]
            )
            XCTAssertTrue(node.accessibilityTraits.contains(.isButton))
            XCTAssertEqual(node.accessibilityChildBehavior, .combine)
        }
    }

    func testDisabledButtonKeepsButtonTrait() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: testPalette,
                isEnabled: false
            )
            XCTAssertTrue(node.accessibilityTraits.contains(.isButton))
        }
    }

    func testButtonProjectionFoldsNameFromContent() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: testPalette,
                children: [Controls.label("Save Changes")]
            )
            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .button)
            XCTAssertEqual(projection?.name, "Save Changes")
            // Combine folds the label into the button: no child elements.
            XCTAssertEqual(projection?.children.isEmpty, true)
        }
    }

    func testIconIsHiddenFromAccessibility() async {
        await MainActor.run {
            let node = Controls.icon(.checkmark)
            XCTAssertTrue(node.isAccessibilityHidden)
        }
    }

    func testToggleProjectsOnStateAsSelected() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let onNode = Controls.toggle(runtime: runtime, isOn: true)
            XCTAssertTrue(onNode.accessibilityTraits.contains(.isButton))
            XCTAssertTrue(onNode.accessibilityTraits.contains(.isToggle))
            XCTAssertTrue(onNode.accessibilityTraits.contains(.isSelected))

            let offNode = Controls.toggle(runtime: runtime, isOn: false)
            XCTAssertTrue(offNode.accessibilityTraits.contains(.isButton))
            XCTAssertTrue(offNode.accessibilityTraits.contains(.isToggle))
            XCTAssertFalse(offNode.accessibilityTraits.contains(.isSelected))
        }
    }

    func testCheckboxProjectsCheckedStateAsSelected() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = Controls.checkbox(runtime: runtime, label: "Wi-Fi", isChecked: true)
            XCTAssertTrue(node.accessibilityTraits.contains(.isToggle))
            XCTAssertTrue(node.accessibilityTraits.contains(.isSelected))

            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .checkBox)
            XCTAssertEqual(projection?.name, "Wi-Fi")
            XCTAssertEqual(projection?.isSelected, true)
        }
    }

    func testNewTraitControlTypeMappings() async {
        await MainActor.run {
            // isToggle wins over isButton (toggles keep the retained button
            // trait but must project as checkboxes).
            let toggleNode = ViewNode()
            toggleNode.accessibilityTraits = [.isToggle, .isButton]
            XCTAssertEqual(AccessibilityProjection.resolveControlType(for: toggleNode), .checkBox)

            let progressNode = ViewNode()
            progressNode.accessibilityTraits = .isProgressIndicator
            XCTAssertEqual(AccessibilityProjection.resolveControlType(for: progressNode), .progressBar)

            let textInputNode = ViewNode()
            textInputNode.accessibilityTraits = .isTextInput
            XCTAssertEqual(AccessibilityProjection.resolveControlType(for: textInputNode), .edit)
        }
    }

    func testSliderDefaultsToSliderBehaviorAndValue() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = Controls.slider(runtime: runtime, value: 0.5, range: 0...1)
            XCTAssertEqual(node.accessibilityPrefersSliderBehavior, true)
            XCTAssertEqual(node.accessibilityValue, "0.5")

            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .slider)
            XCTAssertEqual(projection?.value, "0.5")
        }
    }

    func testProgressBarDefaultsToPercentageValue() async {
        await MainActor.run {
            let node = Controls.progressBar(value: 2, total: 5)
            XCTAssertTrue(node.accessibilityTraits.contains(.isProgressIndicator))
            XCTAssertEqual(node.accessibilityValue, "40%")

            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .progressBar)
            XCTAssertEqual(projection?.value, "40%")
        }
    }

    func testCircularProgressValueOnlyWhenDeterminate() async {
        await MainActor.run {
            let determinate = Controls.circularProgress(value: 1, total: 4)
            XCTAssertTrue(determinate.accessibilityTraits.contains(.isProgressIndicator))
            XCTAssertEqual(determinate.accessibilityValue, "25%")

            let projection = AccessibilityProjection.project(root: determinate)
            XCTAssertEqual(projection?.controlType, .progressBar)

            let indeterminate = Controls.circularProgress(value: nil)
            XCTAssertTrue(indeterminate.accessibilityTraits.contains(.isProgressIndicator))
            XCTAssertNil(indeterminate.accessibilityValue)
        }
    }
}

// MARK: - WinSwiftUI control defaults

final class WinSwiftUIControlAccessibilityDefaultsTests: XCTestCase {
    func testButtonDefaultsNameFromTitle() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(Button("Save") {}, runtime: runtime)
            XCTAssertTrue(node.accessibilityTraits.contains(.isButton))
            XCTAssertEqual(node.accessibilityLabel, "Save")

            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .button)
            XCTAssertEqual(projection?.name, "Save")
        }
    }

    func testButtonDefaultsNameFromCustomLabel() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Button(action: {}) { [AnyView(Text("Custom Action"))] },
                runtime: runtime
            )
            XCTAssertEqual(node.accessibilityLabel, "Custom Action")
        }
    }

    func testExplicitAccessibilityLabelWinsOverButtonDefault() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Button("Save") {}.accessibilityLabel("A11y Save"),
                runtime: runtime
            )
            XCTAssertEqual(node.accessibilityLabel, "A11y Save")
        }
    }

    func testExplicitTraitModifiersWinOverButtonDefault() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let removed = makeNode(
                Button("Save") {}.accessibilityRemoveTraits(.isButton),
                runtime: runtime
            )
            XCTAssertFalse(removed.accessibilityTraits.contains(.isButton))

            let added = makeNode(
                Button("Save") {}.accessibilityAddTraits(.isHeader),
                runtime: runtime
            )
            XCTAssertTrue(added.accessibilityTraits.contains(.isButton))
            XCTAssertTrue(added.accessibilityTraits.contains(.isHeader))
        }
    }

    func testExplicitChildBehaviorWinsOverButtonCombineDefault() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Button("Save") {}.accessibilityElement(children: .contain),
                runtime: runtime
            )
            XCTAssertEqual(node.accessibilityChildBehavior, .contain)
        }
    }

    func testLinkDefaultsToHyperlinkWithName() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Link("Docs", destination: URL(string: "https://example.com")!),
                runtime: runtime
            )
            XCTAssertTrue(node.accessibilityTraits.contains(.isLink))
            // The projection table checks isButton before isLink, so the link
            // must not keep the retained button default.
            XCTAssertFalse(node.accessibilityTraits.contains(.isButton))
            XCTAssertEqual(node.accessibilityLabel, "Docs")

            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .hyperlink)
            XCTAssertEqual(projection?.name, "Docs")
        }
    }

    func testMenuButtonDefaultsToButtonWithName() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Menu("File") { [AnyView(Button("New") {})] },
                runtime: runtime
            )
            let menuButton = findNode(in: node) { $0.accessibilityTraits.contains(.isButton) }
            XCTAssertNotNil(menuButton)
            XCTAssertEqual(menuButton?.accessibilityLabel, "File")

            let projection = AccessibilityProjection.project(root: node)
            let buttonElement = projection?.flattened().first { $0.controlType == .button }
            XCTAssertEqual(buttonElement?.name, "File")
        }
    }

    func testStepperButtonsHaveActionNames() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Stepper("Count", value: .constant(2), in: 0...10),
                runtime: runtime
            )
            let decrement = findNode(in: node) { $0.accessibilityLabel == "Decrement" }
            let increment = findNode(in: node) { $0.accessibilityLabel == "Increment" }
            XCTAssertNotNil(decrement)
            XCTAssertNotNil(increment)
            XCTAssertEqual(decrement?.accessibilityTraits.contains(.isButton), true)
            XCTAssertEqual(increment?.accessibilityTraits.contains(.isButton), true)
        }
    }

    func testToggleDefaultsNameAndSelectedState() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(Toggle("Wi-Fi", isOn: .constant(true)), runtime: runtime)
            let toggle = findNode(in: node) { $0.accessibilityTraits.contains(.isButton) }
            XCTAssertNotNil(toggle)
            XCTAssertEqual(toggle?.accessibilityLabel, "Wi-Fi")
            XCTAssertEqual(toggle?.accessibilityTraits.contains(.isToggle), true)
            XCTAssertEqual(toggle?.accessibilityTraits.contains(.isSelected), true)

            let projection = AccessibilityProjection.project(root: node)
            let toggleElement = projection?.flattened().first { $0.controlType == .checkBox }
            XCTAssertEqual(toggleElement?.name, "Wi-Fi")
            XCTAssertEqual(toggleElement?.isSelected, true)
        }
    }

    func testToggleOffHasNoSelectedState() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(Toggle("Wi-Fi", isOn: .constant(false)), runtime: runtime)
            let toggle = findNode(in: node) { $0.accessibilityTraits.contains(.isButton) }
            XCTAssertEqual(toggle?.accessibilityTraits.contains(.isSelected), false)
        }
    }

    func testCheckboxStyleToggleProjectsSelectedState() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Toggle("Wi-Fi", isOn: .constant(true)).toggleStyle(CheckboxToggleStyle()),
                runtime: runtime
            )
            XCTAssertTrue(node.accessibilityTraits.contains(.isButton))
            XCTAssertTrue(node.accessibilityTraits.contains(.isToggle))
            XCTAssertTrue(node.accessibilityTraits.contains(.isSelected))

            // Combine folds the label text (the check glyph is hidden).
            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .checkBox)
            XCTAssertEqual(projection?.name, "Wi-Fi")
            XCTAssertEqual(projection?.isSelected, true)
        }
    }

    func testSliderDefaultsToSliderTypeAndValue() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(Slider(value: .constant(0.5)), runtime: runtime)
            XCTAssertEqual(node.accessibilityPrefersSliderBehavior, true)
            XCTAssertEqual(node.accessibilityValue, "0.5")

            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .slider)
            XCTAssertEqual(projection?.value, "0.5")
        }
    }

    func testSliderDefaultsNameFromLabel() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Slider(value: .constant(0.25)) { [AnyView(Text("Volume"))] },
                runtime: runtime
            )
            let slider = findNode(in: node) { $0.accessibilityPrefersSliderBehavior == true }
            XCTAssertEqual(slider?.accessibilityLabel, "Volume")
            XCTAssertEqual(slider?.accessibilityValue, "0.25")
        }
    }

    func testSliderExplicitValueWins() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Slider(value: .constant(0.5)).accessibilityValue("half"),
                runtime: runtime
            )
            XCTAssertEqual(node.accessibilityValue, "half")
        }
    }

    func testProgressViewDefaultsToPercentageValue() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(ProgressView(value: 0.4, total: 1.0), runtime: runtime)
            XCTAssertTrue(node.accessibilityTraits.contains(.isProgressIndicator))
            XCTAssertEqual(node.accessibilityValue, "40%")

            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .progressBar)
        }
    }

    func testProgressViewDefaultsNameFromTitle() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(ProgressView("Loading", value: 0.4), runtime: runtime)
            let bar = findNode(in: node) { $0.accessibilityValue != nil }
            XCTAssertEqual(bar?.accessibilityValue, "40%")
            XCTAssertEqual(bar?.accessibilityLabel, "Loading")
        }
    }

    func testGaugeDefaultsNameAndValue() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(Gauge("Battery", value: 0.5), runtime: runtime)
            let bar = findNode(in: node) { $0.accessibilityValue != nil }
            XCTAssertEqual(bar?.accessibilityValue, "50%")
            XCTAssertEqual(bar?.accessibilityLabel, "Battery")
        }
    }

    func testTextFieldDefaultsNameAndValue() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(TextField("Name", text: .constant("Ada")), runtime: runtime)
            XCTAssertTrue(node.accessibilityTraits.contains(.isTextInput))
            XCTAssertEqual(node.accessibilityLabel, "Name")
            XCTAssertEqual(node.accessibilityValue, "Ada")

            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .edit)
            XCTAssertEqual(projection?.name, "Name")
            XCTAssertEqual(projection?.value, "Ada")
        }
    }

    func testTextFieldEmptyTextHasNoValue() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(TextField("Name", text: .constant("")), runtime: runtime)
            XCTAssertEqual(node.accessibilityLabel, "Name")
            XCTAssertNil(node.accessibilityValue)
        }
    }

    func testTextFieldExplicitModifiersWin() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                TextField("Name", text: .constant("Ada"))
                    .accessibilityLabel("Given name")
                    .accessibilityValue("Ada Lovelace"),
                runtime: runtime
            )
            XCTAssertEqual(node.accessibilityLabel, "Given name")
            XCTAssertEqual(node.accessibilityValue, "Ada Lovelace")
        }
    }

    func testSecureFieldNeverExposesTextAsValue() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(SecureField("Password", text: .constant("hunter2")), runtime: runtime)
            XCTAssertTrue(node.accessibilityTraits.contains(.isTextInput))
            XCTAssertEqual(node.accessibilityLabel, "Password")
            XCTAssertNil(node.accessibilityValue)

            let projection = AccessibilityProjection.project(root: node)
            XCTAssertEqual(projection?.controlType, .edit)
            XCTAssertNil(projection?.value)
        }
    }

    func testWinSwiftUITraitMirrorMatchesRetainedRawValues() async {
        await MainActor.run {
            XCTAssertEqual(AccessibilityTraits.isToggle.retainedTraits, .isToggle)
            XCTAssertEqual(AccessibilityTraits.isProgressIndicator.retainedTraits, .isProgressIndicator)
            XCTAssertEqual(AccessibilityTraits.isTextInput.retainedTraits, .isTextInput)
        }
    }

    func testSectionHeaderDefaultsToHeaderType() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                Section("Settings") { [AnyView(Text("Body"))] },
                runtime: runtime
            )
            let header = findNode(in: node) { $0.accessibilityTraits.contains(.isHeader) }
            XCTAssertNotNil(header)

            let projection = AccessibilityProjection.project(root: node)
            let headerElement = projection?.flattened().first { $0.controlType == .header }
            XCTAssertEqual(headerElement?.name, "Settings")
        }
    }

    func testNavigationTitleDefaultsToHeaderType() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                NavigationStack { [AnyView(Text("Body").navigationTitle("Home"))] },
                runtime: runtime
            )
            let title = findNode(in: node) { $0.accessibilityTraits.contains(.isHeader) }
            XCTAssertNotNil(title)
            XCTAssertTrue(subtreeTexts(of: title!).contains("Home"))
        }
    }

    func testSelectedListRowProjectsSelectedState() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let node = makeNode(
                List(selection: Binding<Int?>.constant(1)) {
                    [AnyView(Text("Row A").tag(1)), AnyView(Text("Row B").tag(2))]
                },
                runtime: runtime
            )
            let selectedRow = findNode(in: node) { $0.accessibilityTraits.contains(.isSelected) }
            XCTAssertNotNil(selectedRow)
            XCTAssertTrue(subtreeTexts(of: selectedRow!).contains("Row A"))
        }
    }
}
