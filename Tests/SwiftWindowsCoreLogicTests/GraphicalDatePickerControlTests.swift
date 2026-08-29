import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class GraphicalDatePickerControlValue {
    var value: Date
    var writes: [Date] = []

    init(_ value: Date) {
        self.value = value
    }

    var binding: Binding<Date> {
        Binding(
            get: { self.value },
            set: {
                self.value = $0
                self.writes.append($0)
            })
    }
}

@MainActor
final class GraphicalDatePickerControlTests: XCTestCase {
    func testGraphicalDateStyleContainsRealDayButtonsAndHeader() async throws {
        let components: [DatePickerComponents] = [.date, .all, []]
        for displayedComponents in components {
            let selection = GraphicalDatePickerControlValue(date(2024, 2, 15, hour: 10, minute: 20))
            let host = makeHost {
                DatePicker("Departure date", selection: selection.binding, displayedComponents: displayedComponents)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }
            defer { host.close() }
            host.render()

            let surface = try node(.surface, in: host)
            let title = try node(.monthTitle, in: host)
            let value = try node(.value, in: host)
            let grid = try node(.grid, in: host)
            let weekdays = try node(.weekdays, in: host)
            XCTAssertEqual(surface.children.count, 3)
            let header = try XCTUnwrap(surface.children.first)
            XCTAssertEqual(header.children.count, 3)
            XCTAssertTrue(descendants(of: header).contains { $0 === title })
            XCTAssertTrue(surface.children.dropFirst().first === value)
            XCTAssertTrue(surface.children.last === grid)
            XCTAssertEqual(surface.preferredSize, Size(width: 280, height: 274))
            XCTAssertEqual(surface.backgroundColor, ControlPalette.resolve(colorScheme: .light).raisedSurface)
            XCTAssertEqual(surface.borderWidth, 1)
            XCTAssertEqual(surface.cornerRadius, 12)
            XCTAssertEqual(title.text, "February 2024")
            XCTAssertEqual(
                weekdays.children.flatMap { texts(in: $0) }, ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
            XCTAssertEqual(grid.children.count, 6, "Five week rows follow the weekday headings")

            let dayButtons = descendants(of: grid).filter { $0.accessibilityTraits.contains(.isButton) }
            XCTAssertEqual(dayButtons.count, 29)
            XCTAssertEqual(Set(dayButtons.compactMap(\.nodeTag)).count, 29)
            for day in 1...29 {
                let button = try node(.day(date(2024, 2, day)), in: host)
                XCTAssertEqual(texts(in: button), [String(day)])
                XCTAssertTrue(button.isFocusable)
                XCTAssertTrue(button.isHitTestVisible)
                XCTAssertNotNil(button.onActivate)
                XCTAssertEqual(button.accessibilityRespondsToUserInteraction, true)
            }
            for index in [0, 1, 2, 3, 33, 34] {
                let padding = try node(.padding(index), in: host)
                assertInert(padding)
                XCTAssertTrue(padding.isAccessibilityHidden)
            }
            XCTAssertEqual(try node(.previousMonth, in: host).accessibilityLabel, "Previous month")
            XCTAssertEqual(try node(.nextMonth, in: host).accessibilityLabel, "Next month")
            XCTAssertTrue(selection.writes.isEmpty, "Constructing and rendering a calendar never selects a date")
        }
    }

    func testDayActivationWritesOnceAndRevalidatesCurrentSelection() async throws {
        let selection = GraphicalDatePickerControlValue(
            date(2024, 2, 15, hour: 9, minute: 17, second: 30, fraction: 0.125))
        let host = makeHost {
            DatePicker("Departure date", selection: selection.binding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        defer { host.close() }
        host.render()
        let twentieth = try node(.day(date(2024, 2, 20)), in: host)
        var completedReloads = 0
        host.componentHost.onReloadCompleted = { completedReloads += 1 }

        // Change the authored binding without rebuilding. Activation must read
        // this time, not the time captured while the day node was constructed.
        selection.value = date(2024, 2, 16, hour: 17, minute: 42, second: 8, fraction: 0.5)
        let expected = date(2024, 2, 20, hour: 17, minute: 42, second: 8, fraction: 0.5)
        click(twentieth, in: host)
        XCTAssertEqual(selection.value, expected)
        XCTAssertEqual(selection.writes, [expected])
        XCTAssertEqual(completedReloads, 1)

        click(try node(.day(date(2024, 2, 20)), in: host), in: host)
        XCTAssertEqual(selection.writes, [expected], "Selecting the same accepted instant is a no-op")
        XCTAssertEqual(completedReloads, 1)
    }

    func testMonthButtonsBrowseWithoutChangingDateBinding() async throws {
        let initial = date(2024, 1, 31, hour: 14, minute: 25)
        let selection = GraphicalDatePickerControlValue(initial)
        let host = makeHost {
            DatePicker("Departure date", selection: selection.binding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        defer { host.close() }
        host.render()
        let initialValue = try node(.value, in: host).text
        XCTAssertEqual(try node(.monthTitle, in: host).text, "January 2024")

        click(try node(.nextMonth, in: host), in: host)
        XCTAssertEqual(try node(.monthTitle, in: host).text, "February 2024")
        XCTAssertNotNil(tagged(.day(date(2024, 2, 29)), in: host.runtime.root))
        XCTAssertNil(tagged(.day(date(2024, 3, 1)), in: host.runtime.root))
        XCTAssertFalse(
            descendants(of: try node(.grid, in: host)).contains { $0.accessibilityTraits.contains(.isSelected) })

        click(try node(.nextMonth, in: host), in: host)
        XCTAssertEqual(try node(.monthTitle, in: host).text, "March 2024")
        click(try node(.previousMonth, in: host), in: host)
        XCTAssertEqual(try node(.monthTitle, in: host).text, "February 2024")
        click(try node(.previousMonth, in: host), in: host)
        XCTAssertEqual(try node(.monthTitle, in: host).text, "January 2024")
        click(try node(.previousMonth, in: host), in: host)
        XCTAssertEqual(try node(.monthTitle, in: host).text, "December 2023")
        XCTAssertEqual(try node(.value, in: host).text, initialValue)
        XCTAssertEqual(selection.value, initial)
        XCTAssertTrue(selection.writes.isEmpty)
    }

    func testDisabledGridRetainsLabelsAndHasNoActivationHandlers() async throws {
        let initial = date(2024, 2, 15, hour: 12)
        let selection = GraphicalDatePickerControlValue(initial)
        let host = makeHost {
            DatePicker("Departure date", selection: selection.binding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .disabled(true)
        }
        defer { host.close() }
        host.render()

        let surface = try node(.surface, in: host)
        assertInert(surface)
        XCTAssertEqual(surface.accessibilityLabel, "Departure date")
        XCTAssertEqual(surface.accessibilityRespondsToUserInteraction, false)
        XCTAssertEqual(try node(.monthTitle, in: host).text, "February 2024")
        XCTAssertFalse(descendants(of: host.runtime.root).contains { $0.isFocusable })
        let buttons = descendants(of: surface).filter { $0.accessibilityTraits.contains(.isButton) }
        XCTAssertEqual(buttons.count, 31, "Disabled dates and month controls retain their semantic button roles")
        for button in buttons {
            assertInert(button)
            XCTAssertEqual(button.accessibilityRespondsToUserInteraction, false)
            XCTAssertFalse(button.accessibilityLabel?.isEmpty ?? true)
            button.onActivate?()
        }
        let selected = try node(.day(date(2024, 2, 15)), in: host)
        XCTAssertEqual(selected.accessibilityLabel, "Thursday, February 15, 2024")
        XCTAssertTrue(selected.accessibilityTraits.contains(.isSelected))
        click(try node(.day(date(2024, 2, 20)), in: host), in: host)
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
        XCTAssertNil(host.runtime.focusedNode)
        XCTAssertEqual(selection.value, initial)
        XCTAssertTrue(selection.writes.isEmpty)
    }

    func testOutOfRangeDaysPublishDisabledMetadataAndCannotWrite() async throws {
        let lower = date(2024, 2, 10, hour: 9)
        let upper = date(2024, 2, 20, hour: 14)
        let selection = GraphicalDatePickerControlValue(date(2024, 2, 15, hour: 12))
        let host = makeHost {
            DatePicker("Departure date", selection: selection.binding, in: lower...upper, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        defer { host.close() }
        host.render()
        let projected = try XCTUnwrap(AccessibilityProjection.project(runtime: host.runtime)).flattened()

        for day in 1...29 {
            let button = try node(.day(date(2024, 2, day)), in: host)
            let enabled = (10...20).contains(day)
            XCTAssertEqual(button.accessibilityRespondsToUserInteraction, enabled)
            XCTAssertEqual(button.isFocusable, enabled)
            XCTAssertEqual(button.isHitTestVisible, enabled)
            let element = try XCTUnwrap(projected.first { $0.sourceNode === button })
            XCTAssertEqual(element.controlType, .button)
            XCTAssertEqual(element.isEnabled, enabled)
            if !enabled {
                assertInert(button)
                button.onActivate?()
            }
        }
        assertInert(try node(.previousMonth, in: host))
        assertInert(try node(.nextMonth, in: host))
        click(try node(.day(date(2024, 2, 9)), in: host), in: host)
        click(try node(.day(date(2024, 2, 21)), in: host), in: host)
        XCTAssertTrue(selection.writes.isEmpty)

        selection.value = date(2024, 2, 15, hour: 1)
        click(try node(.day(date(2024, 2, 10)), in: host), in: host)
        XCTAssertEqual(selection.value, lower, "The first enabled day clamps to its allowed partial-day interval")
        selection.value = date(2024, 2, 15, hour: 20)
        click(try node(.day(date(2024, 2, 20)), in: host), in: host)
        XCTAssertEqual(selection.value, upper)
        XCTAssertEqual(selection.writes, [lower, upper])
    }

    func testSelectedDayPublishesSelectedTraitAndFullDateLabel() async throws {
        let fixtures = [
            ("en_US_POSIX", "Thursday, February 15, 2024", "Friday, February 16, 2024"),
            ("fr_FR", "jeudi 15 février 2024", "vendredi 16 février 2024"),
        ]
        for (locale, selectedName, nextName) in fixtures {
            let selection = GraphicalDatePickerControlValue(date(2024, 2, 15, hour: 23, minute: 40))
            let host = makeHost(locale: Locale(identifier: locale)) {
                DatePicker("Departure date", selection: selection.binding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }
            defer { host.close() }
            host.render()
            let selected = try node(.day(date(2024, 2, 15)), in: host)
            let next = try node(.day(date(2024, 2, 16)), in: host)
            XCTAssertEqual(selected.accessibilityLabel, selectedName)
            XCTAssertTrue(selected.accessibilityTraits.contains(.isButton))
            XCTAssertTrue(selected.accessibilityTraits.contains(.isSelected))
            XCTAssertEqual(next.accessibilityLabel, nextName)
            XCTAssertFalse(next.accessibilityTraits.contains(.isSelected))
            let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: host.runtime))
            let selectedElement = try XCTUnwrap(projection.flattened().first { $0.sourceNode === selected })
            XCTAssertEqual(selectedElement.name, selectedName)
            XCTAssertTrue(selectedElement.isSelected)

            click(next, in: host)
            let selectedNodes = descendants(of: try node(.grid, in: host)).filter {
                $0.accessibilityTraits.contains(.isSelected)
            }
            XCTAssertEqual(
                selectedNodes.compactMap(\.nodeTag), [GraphicalDatePickerNodeID.day(date(2024, 2, 16)).nodeTag])
            XCTAssertEqual(selection.writes, [date(2024, 2, 16, hour: 23, minute: 40)])
        }
    }

    func testHiddenLabelsKeepAccessibleNameAndInteractiveChildren() async throws {
        let selection = GraphicalDatePickerControlValue(date(2024, 2, 15))
        let host = makeHost {
            DatePicker("Departure date", selection: selection.binding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        defer { host.close() }
        host.render()
        let surface = try node(.surface, in: host)
        XCTAssertFalse(texts(in: host.runtime.root).contains("Departure date"))
        XCTAssertEqual(surface.accessibilityLabel, "Departure date")
        XCTAssertEqual(surface.accessibilityValue, try node(.value, in: host).text)
        XCTAssertEqual(surface.accessibilityChildBehavior, .contain)

        let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: host.runtime))
        let picker = try XCTUnwrap(projection.flattened().first { $0.sourceNode === surface })
        XCTAssertEqual(picker.name, "Departure date")
        let buttons = picker.flattened().filter { $0.controlType == .button }
        XCTAssertEqual(buttons.count, 31, "The named parent must not combine away its interactive descendants")
        XCTAssertTrue(buttons.allSatisfy(\.isEnabled))
        XCTAssertTrue(buttons.contains { $0.name == "Previous month" })
        XCTAssertTrue(buttons.contains { $0.name == "Next month" })
        XCTAssertTrue(buttons.contains { $0.name == "Thursday, February 15, 2024" && $0.isSelected })
    }

    func testGroupedFormGraphicalControlHasOneLabelColumn() async throws {
        let selection = GraphicalDatePickerControlValue(date(2024, 2, 15))
        let host = makeHost(size: Size(width: 900, height: 700)) {
            Form {
                Section("Schedule") {
                    DatePicker("Departure date", selection: selection.binding, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Toggle("A longer companion label", isOn: .constant(true))
                }
            }
            .formStyle(.grouped)
        }
        defer { host.close() }
        host.render()
        let rows = descendants(of: host.runtime.root).filter { $0.formRowLabelChildIndex != nil }
        XCTAssertEqual(rows.count, 2)
        let pickerRow = try XCTUnwrap(rows.first { tagged(.surface, in: $0) != nil })
        let companionRow = try XCTUnwrap(rows.first { texts(in: $0).contains("A longer companion label") })
        XCTAssertEqual(pickerRow.formRowLabelChildIndex, 0)
        XCTAssertEqual(pickerRow.children.count, 2)
        let labelColumn = try XCTUnwrap(pickerRow.children.first)
        let valueColumn = try XCTUnwrap(pickerRow.children.dropFirst().first)
        let companionLabelColumn = try XCTUnwrap(companionRow.children.first)
        let surface = try node(.surface, in: host)
        XCTAssertEqual(texts(in: labelColumn), ["Departure date"])
        XCTAssertEqual(texts(in: host.runtime.root).filter { $0 == "Departure date" }.count, 1)
        XCTAssertTrue(descendants(of: valueColumn).contains { $0 === surface })
        XCTAssertFalse(descendants(of: surface).contains { $0.formRowLabelChildIndex != nil })
        XCTAssertEqual(labelColumn.resolvedFrame.width, companionLabelColumn.resolvedFrame.width, accuracy: 0.51)
        XCTAssertEqual(
            absoluteFrame(of: labelColumn).maxX, absoluteFrame(of: companionLabelColumn).maxX, accuracy: 0.51)
        assertContained(absoluteFrame(of: surface), in: absoluteFrame(of: valueColumn))
        XCTAssertEqual(surface.accessibilityLabel, "Departure date")
        XCTAssertEqual(surface.accessibilityChildBehavior, .contain)
        XCTAssertEqual(try node(.monthTitle, in: host).text, "February 2024")
    }

    func testGraphicalAllKeepsMinuteArrowSemantics() async throws {
        let initial = date(2024, 2, 15, hour: 9, minute: 30)
        let selection = GraphicalDatePickerControlValue(initial)
        let host = makeHost {
            DatePicker("Departure date", selection: selection.binding, displayedComponents: .all)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        defer { host.close() }
        host.render()
        let arrows: [(KeyboardKey, TimeInterval)] = [
            (.upArrow, 60), (.downArrow, 0), (.rightArrow, 60), (.leftArrow, 0),
        ]
        for (key, offset) in arrows {
            guard focusUsingTab(.surface, in: host) else { return }
            host.runtime.keyDown(KeyboardEvent(keyCode: key.rawValue))
            host.render()
            XCTAssertEqual(selection.value, initial.addingTimeInterval(offset))
        }
        let increment = try XCTUnwrap(try node(.surface, in: host).accessibilityActions.first { $0.kind == .increment })
        increment.handler()
        host.render()
        XCTAssertEqual(selection.value, initial.addingTimeInterval(60))
        let decrement = try XCTUnwrap(try node(.surface, in: host).accessibilityActions.first { $0.kind == .decrement })
        decrement.handler()
        host.render()
        XCTAssertEqual(selection.value, initial)
        click(try node(.day(date(2024, 2, 17)), in: host), in: host)
        XCTAssertEqual(selection.value, date(2024, 2, 17, hour: 9, minute: 30))
        XCTAssertEqual(selection.writes.count, 7)
    }

    func testTimeOnlyGraphicalStyleDoesNotInventDaySelection() async throws {
        let initial = date(2024, 2, 15, hour: 13, minute: 45)
        let selection = GraphicalDatePickerControlValue(initial)
        let host = makeHost {
            DatePicker("Departure time", selection: selection.binding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        defer { host.close() }
        host.render()
        for identifier in [GraphicalDatePickerNodeID.grid, .monthTitle, .previousMonth, .nextMonth, .weekdays] {
            XCTAssertNil(tagged(identifier, in: host.runtime.root))
        }
        XCTAssertFalse(descendants(of: host.runtime.root).contains { $0.accessibilityTraits.contains(.isButton) })
        let control = try XCTUnwrap(
            descendants(of: host.runtime.root).first { $0.accessibilityLabel == "Departure time" })
        XCTAssertEqual(
            control.children.count, 1, "A time surface contains its value, without decorative calendar squares")
        let value = try XCTUnwrap(control.children.first)
        XCTAssertTrue(value.children.isEmpty)
        let initialText = try XCTUnwrap(value.text)
        XCTAssertFalse(initialText.isEmpty)
        XCTAssertFalse(initialText.contains("2024"))
        XCTAssertEqual(control.accessibilityValue, initialText)
        XCTAssertEqual(control.accessibilityActions.map(\.kind), [.increment, .decrement])
        host.runtime.requestFocus(control)
        XCTAssertTrue(host.runtime.focusedNode === control)
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
        host.render()
        XCTAssertEqual(selection.writes, [initial.addingTimeInterval(60)])
        let updated = try XCTUnwrap(
            descendants(of: host.runtime.root).first { $0.accessibilityLabel == "Departure time" })
        XCTAssertNotNil(updated.accessibilityValue)
        XCTAssertNotEqual(updated.accessibilityValue, initialText)
        XCTAssertNil(tagged(.grid, in: host.runtime.root))
    }

    func testGraphicalCalendarCellFramesStayInBoundsAcrossWidthsAndDirections() async throws {
        // With Sunday first: February 2015 starts on Sunday, February 2024 on
        // Thursday, and August 2020 on Saturday. These exercise 4, 5, and 6 rows.
        let months = [(2015, 2, 28, 0, 4), (2024, 2, 29, 4, 5), (2020, 8, 31, 6, 6)]
        for (year, month, days, firstColumn, rowCount) in months {
            for width in [220.0, 280.0, 340.0] {
                var leftToRightWeekdayTags: [String?]?
                for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                    let selection = GraphicalDatePickerControlValue(date(year, month, 15))
                    let host = makeHost(size: Size(width: width, height: 480), direction: direction) {
                        DatePicker("Departure date", selection: selection.binding, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                    defer { host.close() }
                    host.render()
                    let surface = try node(.surface, in: host)
                    let grid = try node(.grid, in: host)
                    let weekdays = try node(.weekdays, in: host)
                    XCTAssertEqual(surface.preferredSize, Size(width: 280, height: 104 + Double(rowCount) * 34))
                    assertContained(absoluteFrame(of: surface), in: Rect(x: 0, y: 0, width: width, height: 480))
                    assertContained(absoluteFrame(of: grid), in: absoluteFrame(of: surface))
                    let physicalWeekdays = weekdays.children.sorted {
                        absoluteFrame(of: $0).minX < absoluteFrame(of: $1).minX
                    }
                    guard physicalWeekdays.count == 7 else {
                        return XCTFail("Every calendar week needs seven physical columns")
                    }
                    if direction == .leftToRight {
                        leftToRightWeekdayTags = physicalWeekdays.map(\.nodeTag)
                    } else {
                        XCTAssertEqual(
                            physicalWeekdays.map(\.nodeTag), Array(try XCTUnwrap(leftToRightWeekdayTags).reversed()))
                    }
                    let columnWidth = try XCTUnwrap(physicalWeekdays.first).resolvedFrame.width
                    var rows = [weekdays]
                    for week in 0..<rowCount {
                        rows.append(try node(.week(week), in: host))
                    }
                    XCTAssertEqual(grid.children.count, rowCount + 1)
                    for row in rows {
                        let rowBounds = absoluteFrame(of: row)
                        assertContained(rowBounds, in: absoluteFrame(of: grid))
                        XCTAssertEqual(row.children.count, 7)
                        let cells = row.children.sorted { absoluteFrame(of: $0).minX < absoluteFrame(of: $1).minX }
                        for cell in cells {
                            let bounds = absoluteFrame(of: cell)
                            XCTAssertGreaterThan(bounds.width, 0)
                            XCTAssertGreaterThan(bounds.height, 0)
                            XCTAssertEqual(bounds.width, columnWidth, accuracy: 0.01)
                            assertContained(bounds, in: rowBounds)
                        }
                        for (left, right) in zip(cells, cells.dropFirst()) {
                            XCTAssertLessThanOrEqual(absoluteFrame(of: left).maxX, absoluteFrame(of: right).minX + 0.01)
                        }
                    }
                    for (upper, lower) in zip(rows, rows.dropFirst()) {
                        XCTAssertLessThanOrEqual(absoluteFrame(of: upper).maxY, absoluteFrame(of: lower).minY + 0.01)
                    }
                    for day in 1...days {
                        let button = try node(.day(date(year, month, day)), in: host)
                        let logicalColumn = (firstColumn + day - 1) % 7
                        let physicalColumn = direction == .leftToRight ? logicalColumn : 6 - logicalColumn
                        let bounds = absoluteFrame(of: button)
                        XCTAssertEqual(
                            bounds.minX, absoluteFrame(of: physicalWeekdays[physicalColumn]).minX, accuracy: 0.01)
                        let week = try node(.week((firstColumn + day - 1) / 7), in: host)
                        assertContained(bounds, in: absoluteFrame(of: week))
                        host.runtime.pointerMoved(to: Point(x: bounds.midX, y: bounds.midY))
                        XCTAssertTrue(button.isHovered, "Each day keeps its own hit target")
                    }
                    XCTAssertTrue(selection.writes.isEmpty)
                }
            }
        }
    }

    func testFocusTabAndEnterActivateMonthAndDayButtons() async throws {
        let initial = date(2024, 1, 15, hour: 9, minute: 30)
        let selection = GraphicalDatePickerControlValue(initial)
        let host = makeHost {
            DatePicker("Departure date", selection: selection.binding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        defer { host.close() }
        host.render()
        guard focusUsingTab(.nextMonth, in: host) else { return }
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
        host.render()
        XCTAssertEqual(try node(.monthTitle, in: host).text, "February 2024")
        XCTAssertEqual(host.runtime.focusedNode?.nodeTag, GraphicalDatePickerNodeID.nextMonth.nodeTag)
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
        host.render()
        XCTAssertEqual(try node(.monthTitle, in: host).text, "March 2024")
        guard focusUsingTab(.previousMonth, in: host) else { return }
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
        host.render()
        XCTAssertEqual(try node(.monthTitle, in: host).text, "February 2024")
        XCTAssertEqual(selection.value, initial)
        XCTAssertTrue(selection.writes.isEmpty)

        let twentieth = GraphicalDatePickerNodeID.day(date(2024, 2, 20))
        guard focusUsingTab(twentieth, in: host) else { return }
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
        host.render()
        XCTAssertEqual(selection.writes, [date(2024, 2, 20, hour: 9, minute: 30)])
        XCTAssertEqual(host.runtime.focusedNode?.nodeTag, twentieth.nodeTag)
        XCTAssertTrue(try node(twentieth, in: host).accessibilityTraits.contains(.isSelected))
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
        host.render()
        XCTAssertEqual(selection.writes.count, 1)
        guard focusUsingTab(.day(date(2024, 2, 21)), in: host) else { return }
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
        host.render()
        XCTAssertEqual(
            selection.writes, [date(2024, 2, 20, hour: 9, minute: 30), date(2024, 2, 21, hour: 9, minute: 30)])
    }

    private func makeHost<V: View>(
        size: Size = Size(width: 400, height: 420),
        direction: LayoutDirection = .leftToRight,
        locale: Locale = Locale(identifier: "en_US_POSIX"),
        content: @escaping @MainActor () -> V
    ) -> MountedOnChangeTestHost {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let inheritedCalendar = calendar
        return MountedOnChangeTestHost(size: size) {
            AnyView(
                content()
                    .environment(\.calendar, inheritedCalendar)
                    .environment(\.timeZone, inheritedCalendar.timeZone)
                    .environment(\.locale, locale)
                    .environment(\.layoutDirection, direction)
                    .environment(\.colorScheme, .light))
        }
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 0, minute: Int = 0, second: Int = 0, fraction: TimeInterval = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
            .addingTimeInterval(fraction)
    }

    private func descendants(of root: ViewNode) -> [ViewNode] {
        var result = [root]
        var index = 0
        while index < result.count {
            result.append(contentsOf: result[index].children)
            index += 1
        }
        return result
    }

    private func texts(in root: ViewNode) -> [String] {
        descendants(of: root).compactMap(\.text).filter { !$0.isEmpty }
    }

    private func tagged(_ identifier: GraphicalDatePickerNodeID, in root: ViewNode) -> ViewNode? {
        descendants(of: root).first { $0.nodeTag == identifier.nodeTag }
    }

    private func node(
        _ identifier: GraphicalDatePickerNodeID, in host: MountedOnChangeTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        try XCTUnwrap(
            tagged(identifier, in: host.runtime.root), "Missing calendar node \(identifier)", file: file, line: line)
    }

    private func absoluteFrame(of node: ViewNode) -> Rect {
        var origin = node.resolvedFrame.origin
        var ancestor = node.parent
        while let current = ancestor {
            origin.x += current.resolvedFrame.origin.x
            origin.y += current.resolvedFrame.origin.y
            ancestor = current.parent
        }
        return Rect(origin: origin, size: node.resolvedFrame.size)
    }

    private func click(_ node: ViewNode, in host: MountedOnChangeTestHost) {
        let bounds = absoluteFrame(of: node)
        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)
        let point = Point(x: bounds.midX, y: bounds.midY)
        host.runtime.pointerMoved(to: point)
        host.runtime.pointerDown(at: point)
        host.runtime.pointerUp(at: point)
        host.render()
    }

    private func focusUsingTab(
        _ identifier: GraphicalDatePickerNodeID, in host: MountedOnChangeTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) -> Bool {
        let stops = descendants(of: host.runtime.root).filter(\.isFocusable).count
        for _ in 0...stops {
            host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
            if host.runtime.focusedNode?.nodeTag == identifier.nodeTag { return true }
        }
        XCTFail("Tab cannot reach calendar node \(identifier)", file: file, line: line)
        return false
    }

    private func assertInert(_ node: ViewNode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(node.isFocusable, file: file, line: line)
        XCTAssertFalse(node.isHitTestVisible, file: file, line: line)
        XCTAssertNil(node.onActivate, file: file, line: line)
        XCTAssertNil(node.onRepeatActivate, file: file, line: line)
        XCTAssertNil(node.onKeyDown, file: file, line: line)
        XCTAssertNil(node.onPointerDown, file: file, line: line)
        XCTAssertNil(node.onPointerUpInside, file: file, line: line)
        XCTAssertNil(node.onPointerUpInsideAt, file: file, line: line)
        XCTAssertTrue(node.accessibilityActions.isEmpty, file: file, line: line)
    }

    private func assertContained(
        _ bounds: Rect, in container: Rect, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(bounds.minX, container.minX - 0.51, file: file, line: line)
        XCTAssertGreaterThanOrEqual(bounds.minY, container.minY - 0.51, file: file, line: line)
        XCTAssertLessThanOrEqual(bounds.maxX, container.maxX + 0.51, file: file, line: line)
        XCTAssertLessThanOrEqual(bounds.maxY, container.maxY + 0.51, file: file, line: line)
    }
}
