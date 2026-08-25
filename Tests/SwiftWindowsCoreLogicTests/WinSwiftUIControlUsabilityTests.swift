import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private func makeControlUsabilityNode<V: View>(
    _ view: V,
    colorScheme: ColorScheme = .dark,
    contrast: ColorSchemeContrast = .standard,
    invalidate: @escaping () -> Void = {}
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 800, height: 600) },
        invalidateHandler: invalidate
    )
    .withEnvironmentValue(\.colorScheme, colorScheme)
    .withEnvironmentValue(\.colorSchemeContrast, contrast)
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func makeControlUsabilityPicker(style: PickerStyle) -> some View {
    Picker("Appearance", selection: .constant(0)) {
        Text("First").tag(0)
        Text("Second").tag(1)
    }
    .pickerStyle(style)
}

final class WinSwiftUIControlUsabilityTests: XCTestCase {
    func testDatePickerStyledSurfacesFollowLightAndDarkAppearance() async {
        await MainActor.run {
            let styles: [DatePickerStyle] = [.compact, .field, .stepperField, .wheel, .graphical]
            let date = Date(timeIntervalSince1970: 1_778_400_000)

            for scheme in [ColorScheme.dark, .light] {
                let palette = ControlPalette.resolve(colorScheme: scheme)
                for style in styles {
                    let node = makeControlUsabilityNode(
                        DatePicker("Start", selection: .constant(date))
                            .datePickerStyle(style),
                        colorScheme: scheme
                    )
                    let control = node.children[1]
                    let expectedSurface = style == .graphical ? palette.raisedSurface : palette.fieldSurface

                    XCTAssertEqual(control.backgroundColor, expectedSurface)
                    XCTAssertEqual(control.borderColor, palette.controlBorder)
                }
            }
        }
    }

    func testDatePickerBorderFollowsIncreasedContrast() async {
        await MainActor.run {
            let date = Date(timeIntervalSince1970: 1_778_400_000)

            for scheme in [ColorScheme.dark, .light] {
                let standard = makeControlUsabilityNode(
                    DatePicker("Start", selection: .constant(date)).datePickerStyle(.field),
                    colorScheme: scheme
                )
                let increased = makeControlUsabilityNode(
                    DatePicker("Start", selection: .constant(date)).datePickerStyle(.field),
                    colorScheme: scheme,
                    contrast: .increased
                )

                XCTAssertEqual(
                    increased.children[1].borderColor,
                    ControlPalette.resolve(colorScheme: scheme, contrast: .increased).controlBorder
                )
                XCTAssertGreaterThan(
                    increased.children[1].borderColor.alpha,
                    standard.children[1].borderColor.alpha
                )
            }
        }
    }

    func testDatePickerPublishesNameValueAndAdjustableActions() async {
        await MainActor.run {
            let date = Date(timeIntervalSince1970: 1_778_400_000)
            let visible = makeControlUsabilityNode(
                DatePicker("Start date", selection: .constant(date), displayedComponents: .date)
            )
            let hidden = makeControlUsabilityNode(
                DatePicker("Start date", selection: .constant(date), displayedComponents: .date)
                    .labelsHidden()
            )

            XCTAssertEqual(visible.accessibilityLabel, "Start date")
            XCTAssertEqual(visible.accessibilityValue, visible.children[1].text)
            XCTAssertEqual(hidden.accessibilityLabel, "Start date")
            XCTAssertEqual(hidden.accessibilityValue, hidden.text)
            XCTAssertEqual(visible.accessibilityActions.map(\.kind), [.increment, .decrement])
            XCTAssertTrue(visible.interceptsVerticalArrowKeys)
        }
    }

    func testDisabledDatePickerRemainsAccessibleWithoutAdjustmentHandlers() async {
        await MainActor.run {
            let date = Date(timeIntervalSince1970: 1_778_400_000)
            let node = makeControlUsabilityNode(
                DatePicker("Start date", selection: .constant(date), displayedComponents: .date)
                    .disabled(true)
            )

            XCTAssertEqual(node.accessibilityLabel, "Start date")
            XCTAssertNotNil(node.accessibilityValue)
            XCTAssertEqual(node.accessibilityRespondsToUserInteraction, false)
            XCTAssertFalse(node.isFocusable)
            XCTAssertNil(node.onKeyDown)
            XCTAssertTrue(node.accessibilityActions.isEmpty)
        }
    }

    func testDatePickerStepperButtonsMutateBindingAndRespectRange() async {
        await MainActor.run {
            let initialDate = Date(timeIntervalSince1970: 1_778_400_000)
            let nextDate = initialDate.addingTimeInterval(86_400)
            var selectedDate = initialDate
            var invalidations = 0
            let binding = Binding<Date>(
                get: { selectedDate },
                set: { selectedDate = $0 }
            )

            let lowerBoundNode = makeControlUsabilityNode(
                DatePicker("Start", selection: binding, in: initialDate...nextDate, displayedComponents: .date)
                    .datePickerStyle(.stepperField),
                invalidate: { invalidations += 1 }
            )
            let lowerBoundButtons = lowerBoundNode.children[1].children[1].children

            XCTAssertEqual(lowerBoundButtons[0].accessibilityLabel, "Increment")
            XCTAssertTrue(lowerBoundButtons[0].isFocusable)
            XCTAssertEqual(lowerBoundButtons[1].accessibilityLabel, "Decrement")
            XCTAssertEqual(lowerBoundButtons[1].accessibilityRespondsToUserInteraction, false)
            XCTAssertFalse(lowerBoundButtons[1].isFocusable)
            XCTAssertNil(lowerBoundButtons[1].onActivate)

            lowerBoundButtons[0].onActivate?()
            XCTAssertEqual(selectedDate, nextDate)
            XCTAssertEqual(invalidations, 1)

            lowerBoundButtons[0].onActivate?()
            XCTAssertEqual(selectedDate, nextDate)
            XCTAssertEqual(invalidations, 1)

            let upperBoundNode = makeControlUsabilityNode(
                DatePicker("Start", selection: binding, in: initialDate...nextDate, displayedComponents: .date)
                    .datePickerStyle(.stepperField)
            )
            let upperBoundButtons = upperBoundNode.children[1].children[1].children
            XCTAssertFalse(upperBoundButtons[0].isFocusable)
            XCTAssertTrue(upperBoundButtons[1].isFocusable)
            upperBoundButtons[1].onActivate?()
            XCTAssertEqual(selectedDate, initialDate)
        }
    }

    func testDatePickerAccessibilityAdjustmentsRespectRange() async {
        await MainActor.run {
            let initialDate = Date(timeIntervalSince1970: 1_778_400_000)
            let nextDate = initialDate.addingTimeInterval(86_400)
            var selectedDate = initialDate
            let binding = Binding<Date>(
                get: { selectedDate },
                set: { selectedDate = $0 }
            )
            let node = makeControlUsabilityNode(
                DatePicker("Start", selection: binding, in: initialDate...nextDate, displayedComponents: .date)
            )

            node.accessibilityActions[1].handler()
            XCTAssertEqual(selectedDate, initialDate)

            node.accessibilityActions[0].handler()
            XCTAssertEqual(selectedDate, nextDate)

            node.accessibilityActions[0].handler()
            XCTAssertEqual(selectedDate, nextDate)
        }
    }

    func testPickerPanelStylesFollowLightAndDarkAppearance() async {
        await MainActor.run {
            let styles: [PickerStyle] = [.inline, .palette, .radioGroup, .wheel]

            for scheme in [ColorScheme.dark, .light] {
                let palette = ControlPalette.resolve(colorScheme: scheme)
                for style in styles {
                    let node = makeControlUsabilityNode(
                        makeControlUsabilityPicker(style: style),
                        colorScheme: scheme
                    )
                    let control = node.children[1]

                    XCTAssertEqual(control.backgroundColor, palette.controlBackground)
                    XCTAssertEqual(control.borderColor, palette.controlBorder)
                }
            }
        }
    }

    func testDropdownPickerMenuAndLabelsFollowAppearance() async {
        await MainActor.run {
            for scheme in [ColorScheme.dark, .light] {
                let palette = ControlPalette.resolve(colorScheme: scheme)
                for style in [PickerStyle.menu, .navigationLink] {
                    let node = makeControlUsabilityNode(
                        makeControlUsabilityPicker(style: style),
                        colorScheme: scheme
                    )
                    let dropdown = node.children[1]
                    let header = dropdown.children[0]
                    let menu = dropdown.children[1]

                    XCTAssertEqual(dropdown.backgroundColor, palette.controlSurface)
                    XCTAssertEqual(dropdown.borderColor, palette.controlBorder)
                    XCTAssertEqual(header.children[0].textStyle.color, palette.label)
                    XCTAssertEqual(header.children[1].textStyle.color, palette.secondaryLabel)
                    XCTAssertEqual(menu.backgroundColor, palette.elevatedSurface)
                    XCTAssertEqual(menu.borderColor, palette.elevatedSurfaceBorder)
                    XCTAssertEqual(menu.children[0].children[0].textStyle.color, palette.selectedContentLabel)
                    XCTAssertEqual(menu.children[1].children[0].textStyle.color, palette.label)
                }
            }
        }
    }

    func testPickerBordersFollowIncreasedContrast() async {
        await MainActor.run {
            for style in [PickerStyle.inline, .menu, .radioGroup] {
                let node = makeControlUsabilityNode(
                    makeControlUsabilityPicker(style: style),
                    colorScheme: .light,
                    contrast: .increased
                )

                XCTAssertEqual(
                    node.children[1].borderColor,
                    ControlPalette.resolve(colorScheme: .light, contrast: .increased).controlBorder
                )
            }
        }
    }

    func testWheelPickerUsesReadableAppearanceResolvedLabels() async {
        await MainActor.run {
            let palette = ControlPalette.resolve(colorScheme: .light)
            let node = makeControlUsabilityNode(
                makeControlUsabilityPicker(style: .wheel),
                colorScheme: .light
            )
            let wheel = node.children[1]

            XCTAssertEqual(wheel.children[0].children[0].textStyle.color, palette.selectedContentLabel)
            XCTAssertEqual(wheel.children[1].children[0].textStyle.color, palette.secondaryLabel)
        }
    }

    func testSliderArrowKeysHonorStepBoundsEditingAndAccessibility() async {
        await MainActor.run {
            var value = 0.5
            var editingChanges: [Bool] = []
            var invalidations = 0
            let node = makeControlUsabilityNode(
                Slider(
                    value: Binding(get: { value }, set: { value = $0 }),
                    in: 0...1,
                    step: 0.25,
                    onEditingChanged: { editingChanges.append($0) }
                ),
                invalidate: { invalidations += 1 }
            )

            XCTAssertTrue(node.interceptsVerticalArrowKeys)
            XCTAssertEqual(node.accessibilityActions.map(\.kind), [.increment, .decrement])

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            XCTAssertEqual(value, 0.75, accuracy: 0.0001)
            XCTAssertEqual(node.accessibilityValue, "0.75")
            XCTAssertEqual(editingChanges, [true, false])

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            XCTAssertEqual(value, 1, accuracy: 0.0001)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            XCTAssertEqual(value, 1, accuracy: 0.0001)
            XCTAssertEqual(invalidations, 2)

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertEqual(value, 0.75, accuracy: 0.0001)
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
            XCTAssertEqual(value, 0.5, accuracy: 0.0001)
        }
    }

    func testSliderHomeEndPageAndAccessibilityActionsAdjustValue() async {
        await MainActor.run {
            var value = 50.0
            let node = makeControlUsabilityNode(
                Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...100)
            )

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            XCTAssertEqual(value, 51, accuracy: 0.0001)
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.pageUp.rawValue))
            XCTAssertEqual(value, 61, accuracy: 0.0001)
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.pageDown.rawValue))
            XCTAssertEqual(value, 51, accuracy: 0.0001)
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.home.rawValue))
            XCTAssertEqual(value, 0, accuracy: 0.0001)
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.end.rawValue))
            XCTAssertEqual(value, 100, accuracy: 0.0001)

            node.accessibilityActions[1].handler()
            XCTAssertEqual(value, 99, accuracy: 0.0001)
            node.accessibilityActions[0].handler()
            XCTAssertEqual(value, 100, accuracy: 0.0001)
        }
    }

    func testSliderHorizontalArrowKeysRespectRightToLeftLayout() async {
        await MainActor.run {
            var value = 0.5
            let node = makeControlUsabilityNode(
                Slider(
                    value: Binding(get: { value }, set: { value = $0 }),
                    in: 0...1,
                    step: 0.25
                )
                .environment(\.layoutDirection, .rightToLeft)
            )

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            XCTAssertEqual(value, 0.25, accuracy: 0.0001)
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
            XCTAssertEqual(value, 0.5, accuracy: 0.0001)
        }
    }

    func testDisabledSliderHasNoKeyboardOrAccessibilityAdjustments() async {
        await MainActor.run {
            var value = 0.5
            let node = makeControlUsabilityNode(
                Slider(value: Binding(get: { value }, set: { value = $0 }))
                    .disabled(true),
                colorScheme: .light
            )

            XCTAssertFalse(node.isFocusable)
            XCTAssertNil(node.onKeyDown)
            XCTAssertTrue(node.accessibilityActions.isEmpty)
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            XCTAssertEqual(value, 0.5, accuracy: 0.0001)
        }
    }
}
