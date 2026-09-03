import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewThatFitsScalarLabelTransparencyTests: XCTestCase {
    func testControlLabelPriorityDefaultsReachSelectedLabelsAndPreserveAuthoredPriorities() async throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = Date(timeIntervalSinceReferenceDate: 0)
        var rootBuilds = 0
        let host = MountedOnChangeTestHost(size: Size(width: 700, height: 1_400)) {
            rootBuilds += 1
            return AnyView(
                VStack(spacing: 0) {
                    scalarLabelControls(prefix: "floor", priority: 0, date: date)
                    scalarLabelControls(prefix: "authored", priority: 7, date: date)
                }
                .environment(\.calendar, calendar)
                .environment(\.timeZone, timeZone)
                .environment(\.locale, Locale(identifier: "en_US_POSIX")))
        }
        defer { host.close() }

        host.render()
        XCTAssertEqual(rootBuilds, 1)
        let priorities: [(String, Double)] = [("floor", 1), ("authored", 7)]
        let families = ["labeled", "group", "date", "color", "picker", "multi"]
        for (prefix, expectedPriority) in priorities {
            for family in families {
                let label = try scalarLabelNode("scalar.\(prefix).\(family).label", in: host)
                let control = try scalarLabelNode("scalar.\(prefix).\(family).control", in: host)
                let outer = try scalarLabelOuter(of: label)
                XCTAssertEqual(label.layoutPriority, expectedPriority, "\(prefix).\(family)")
                XCTAssertNil(control.selectedContentRole)
                XCTAssertEqual(control.children.count, 2)
                let labelContainer: ViewNode
                if family == "picker" {
                    labelContainer = try XCTUnwrap(control.children.first)
                    XCTAssertNil(labelContainer.selectedContentRole)
                    XCTAssertEqual(labelContainer.children.count, 2)
                } else {
                    labelContainer = control
                }
                XCTAssertTrue(labelContainer.children.first === outer)
                XCTAssertTrue(outer.parent === labelContainer)
                if family == "multi" {
                    XCTAssertEqual(outer.nodeTag, "WinSwiftUI.MultiDatePicker.calendar.label")
                    XCTAssertNotEqual(label.nodeTag, "WinSwiftUI.MultiDatePicker.calendar.label")
                }
            }
        }
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testDisabledButtonDimsSelectedLabelWithoutGivingBoundariesOpacityOrFocus() async throws {
        var rootBuilds = 0
        var activations = 0
        let host = MountedOnChangeTestHost {
            rootBuilds += 1
            return AnyView(
                VStack(spacing: 0) {
                    Button(action: { activations += 1 }) {
                        scalarLabelSelection(
                            Text("Enabled label").accessibilityIdentifier("scalar.enabled.label"))
                    }
                    .accessibilityIdentifier("scalar.enabled.button")
                    Button(action: { activations += 1 }) {
                        scalarLabelSelection(
                            Text("Disabled label").accessibilityIdentifier("scalar.disabled.label"))
                    }
                    .disabled(true)
                    .accessibilityIdentifier("scalar.disabled.button")
                })
        }
        defer { host.close() }

        host.render()
        XCTAssertEqual(rootBuilds, 1)
        let enabledLabel = try scalarLabelNode("scalar.enabled.label", in: host)
        let disabledLabel = try scalarLabelNode("scalar.disabled.label", in: host)
        let enabledButton = try scalarLabelNode("scalar.enabled.button", in: host)
        let disabledButton = try scalarLabelNode("scalar.disabled.button", in: host)
        let enabledBoundary = try scalarLabelOuter(of: enabledLabel)
        let disabledBoundary = try scalarLabelOuter(of: disabledLabel)
        XCTAssertEqual(enabledLabel.opacity, 1)
        XCTAssertEqual(disabledLabel.opacity, 0.35, accuracy: 0.000_001)
        XCTAssertFalse(enabledLabel.isFocusable)
        XCTAssertFalse(disabledLabel.isFocusable)
        XCTAssertNil(enabledButton.selectedContentRole)
        XCTAssertNil(disabledButton.selectedContentRole)
        XCTAssertEqual(enabledButton.children.count, 1)
        XCTAssertEqual(disabledButton.children.count, 1)
        XCTAssertTrue(enabledButton.children.first === enabledBoundary)
        XCTAssertTrue(disabledButton.children.first === disabledBoundary)
        XCTAssertTrue(enabledBoundary.parent === enabledButton)
        XCTAssertTrue(disabledBoundary.parent === disabledButton)
        XCTAssertTrue(enabledButton.isFocusable)
        XCTAssertFalse(disabledButton.isFocusable)
        XCTAssertTrue(enabledButton.isHitTestVisible)
        XCTAssertFalse(disabledButton.isHitTestVisible)
        XCTAssertNotNil(enabledButton.onActivate)
        XCTAssertNil(disabledButton.onActivate)
        XCTAssertEqual(activations, 0)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testSearchFocusedMakesOnlySelectedContentFocusableThroughNestedBoundaries() async throws {
        let focus = FocusState<Bool>()
        var rootBuilds = 0
        let host = MountedOnChangeTestHost {
            rootBuilds += 1
            return AnyView(
                VStack(spacing: 0) {
                    scalarLabelSelection(
                        Text("Search target").accessibilityIdentifier("scalar.search.target")
                    )
                    .searchFocused(focus.projectedValue)
                    scalarLabelSelection(
                        Text("Ordinary target").accessibilityIdentifier("scalar.search.ordinary"))
                })
        }
        defer { host.close() }

        host.render()
        XCTAssertEqual(rootBuilds, 1)
        let target = try scalarLabelNode("scalar.search.target", in: host)
        let ordinary = try scalarLabelNode("scalar.search.ordinary", in: host)
        let targetBoundary = try scalarLabelOuter(of: target)
        let ordinaryBoundary = try scalarLabelOuter(of: ordinary)
        XCTAssertTrue(target.isFocusable)
        XCTAssertFalse(ordinary.isFocusable)
        XCTAssertFalse(target.isHitTestVisible)
        XCTAssertFalse(ordinary.isHitTestVisible)
        XCTAssertTrue(targetBoundary.parent === ordinaryBoundary.parent)
        let stack = try XCTUnwrap(targetBoundary.parent)
        XCTAssertNil(stack.selectedContentRole)
        XCTAssertEqual(stack.children.count, 2)
        XCTAssertTrue(stack.children.first === targetBoundary)
        XCTAssertTrue(stack.children.last === ordinaryBoundary)
        XCTAssertFalse(focus.wrappedValue)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }
}

@MainActor
private func scalarLabelControls(prefix: String, priority: Double, date: Date) -> some View {
    VStack(spacing: 0) {
        LabeledContent {
            Text("Value")
        } label: {
            scalarPriorityLabel(prefix: prefix, family: "labeled", priority: priority)
        }
        .accessibilityIdentifier("scalar.\(prefix).labeled.control")
        ControlGroup {
            Text("Control")
        } label: {
            scalarPriorityLabel(prefix: prefix, family: "group", priority: priority)
        }
        .accessibilityIdentifier("scalar.\(prefix).group.control")
        DatePicker(selection: .constant(date), displayedComponents: .date) {
            scalarPriorityLabel(prefix: prefix, family: "date", priority: priority)
        }
        .accessibilityIdentifier("scalar.\(prefix).date.control")
        ColorPicker(selection: .constant(.blue), supportsOpacity: false) {
            scalarPriorityLabel(prefix: prefix, family: "color", priority: priority)
        }
        .accessibilityIdentifier("scalar.\(prefix).color.control")
        Picker(selection: .constant(0)) {
            Text("First option").tag(0)
        } label: {
            scalarPriorityLabel(prefix: prefix, family: "picker", priority: priority)
        } currentValueLabel: {
            Text("Current value")
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("scalar.\(prefix).picker.control")
        // Public MultiDatePicker reads its existing initial-date clock. This
        // test has no month/date oracle and neither injects nor advances time.
        MultiDatePicker(selection: .constant(Set([DateComponents(year: 2001, month: 1, day: 1)]))) {
            scalarPriorityLabel(prefix: prefix, family: "multi", priority: priority)
        }
        .accessibilityIdentifier("scalar.\(prefix).multi.control")
    }
}

@MainActor
private func scalarPriorityLabel(prefix: String, family: String, priority: Double) -> some View {
    scalarLabelSelection(
        Text("\(prefix) \(family)")
            .layoutPriority(priority)
            .accessibilityIdentifier("scalar.\(prefix).\(family).label"))
}

@MainActor
private func scalarLabelSelection<Content: View>(_ content: Content) -> some View {
    ViewThatFits(in: .horizontal) {
        ViewThatFits(in: .horizontal) { content }
    }
}

@MainActor
private func scalarLabelOuter(
    of selected: ViewNode, file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    XCTAssertNil(selected.selectedContentRole, file: file, line: line)
    let inner = try XCTUnwrap(selected.parent, file: file, line: line)
    let outer = try XCTUnwrap(inner.parent, file: file, line: line)
    for boundary in [inner, outer] {
        XCTAssertEqual(boundary.selectedContentRole, .viewThatFits, file: file, line: line)
        XCTAssertEqual(boundary.children.count, 1, file: file, line: line)
        XCTAssertEqual(boundary.layoutPriority, 0, file: file, line: line)
        XCTAssertEqual(boundary.opacity, 1, file: file, line: line)
        XCTAssertFalse(boundary.isFocusable, file: file, line: line)
    }
    XCTAssertTrue(inner.children.first === selected, file: file, line: line)
    XCTAssertTrue(outer.children.first === inner, file: file, line: line)
    return outer
}

@MainActor
private func scalarLabelNode(
    _ identifier: String, in host: MountedOnChangeTestHost,
    file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    let matches = scalarLabelDescendants(host.runtime.root).filter { $0.accessibilityIdentifier == identifier }
    XCTAssertEqual(matches.count, 1, file: file, line: line)
    return try XCTUnwrap(matches.first, file: file, line: line)
}

@MainActor
private func scalarLabelDescendants(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap(scalarLabelDescendants)
}
