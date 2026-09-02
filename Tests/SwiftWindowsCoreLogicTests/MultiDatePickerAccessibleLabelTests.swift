import Foundation
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MultiDatePickerAccessibleLabelTests: XCTestCase {
    func testHiddenAndIgnoredLabelSubtreesCannotOverrideTheVisibleAccessibleName() async throws {
        for decorativeMode in 0..<3 {
            for hideControlLabel in [false, true] {
                for hasExplicitVisibleLabel in [false, true] {
                    let selection = MultiDatePickerTestSelection()
                    let decorative: AnyView
                    switch decorativeMode {
                    case 0:
                        decorative = AnyView(
                            Text("Decorative").padding()
                                .accessibilityLabel("Hidden override").hidden())
                    case 1:
                        decorative = AnyView(
                            Text("Decorative").padding()
                                .accessibilityLabel("Hidden override").accessibilityHidden(true))
                    default:
                        decorative = AnyView(
                            Text("Decorative").padding().accessibilityElement(children: .ignore))
                    }
                    let visible: AnyView
                    if hasExplicitVisibleLabel {
                        visible = AnyView(
                            Text("Travel dates").accessibilityElement(children: .ignore)
                                .accessibilityLabel("Accessible travel dates"))
                    } else {
                        visible = AnyView(Text("Travel dates").accessibilityElement(children: .ignore))
                    }
                    let label = AnyView(
                        HStack {
                            decorative
                            visible
                        })
                    let picker = MultiDatePickerContent(
                        selection: selection.binding, label: [label], now: { multiDatePickerDate(2024, 2, 15) }
                    )
                    .environment(\.calendar, multiDatePickerCalendar())
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    let host = multiDatePickerHost {
                        hideControlLabel ? AnyView(picker.labelsHidden()) : AnyView(picker)
                    }
                    defer { host.close() }
                    host.render()
                    let context =
                        "mode=\(decorativeMode), labelsHidden=\(hideControlLabel), explicit=\(hasExplicitVisibleLabel)"
                    let expectedName = hasExplicitVisibleLabel ? "Accessible travel dates" : "Travel dates"
                    let surface = try XCTUnwrap(
                        multiDatePickerDescendants(host.runtime.root).first {
                            $0.nodeTag == MultiDatePickerNodeID.surface.nodeTag
                        }, context)
                    XCTAssertEqual(surface.accessibilityLabel, expectedName, context)
                    let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: host.runtime), context)
                    let calendar = try XCTUnwrap(
                        projection.flattened().first { $0.sourceNode === surface }, context)
                    XCTAssertEqual(calendar.name, expectedName, context)
                    let buttons = calendar.flattened().filter { $0.controlType == .button }
                    XCTAssertEqual(buttons.count, 31, context)
                    XCTAssertTrue(buttons.allSatisfy(\.isEnabled), context)
                    XCTAssertTrue(selection.writes.isEmpty, context)
                    let day = try XCTUnwrap(
                        buttons.first { $0.name == "Friday, February 16, 2024" }, context)
                    XCTAssertTrue(day.invokeDefaultAction(), context)
                    host.render()
                    XCTAssertEqual(selection.value, [DateComponents(year: 2024, month: 2, day: 16)], context)
                    XCTAssertEqual(selection.writes.count, 1, context)
                }
            }
        }
    }
}
