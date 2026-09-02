import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MultiDatePickerControlTests: XCTestCase {
    func testExistingPublicInitializersUseAnInteractiveCurrentMonthCalendar() async throws {
        let calendar = multiDatePickerCalendar()
        let selection = MultiDatePickerTestSelection()
        let before = Date()
        let views: [AnyView] = [
            AnyView(MultiDatePicker("String title", selection: selection.binding)),
            AnyView(MultiDatePicker(LocalizedStringKey("Localized title"), selection: selection.binding)),
            AnyView(MultiDatePicker(selection: selection.binding) { Text("Builder title") }),
        ]
        for (view, title) in zip(views, ["String title", "Localized title", "Builder title"]) {
            let host = multiDatePickerHost {
                AnyView(
                    view.environment(\.calendar, calendar)
                        .environment(\.timeZone, calendar.timeZone)
                        .environment(\.locale, Locale(identifier: "en_US_POSIX")))
            }
            defer { host.close() }
            host.render()
            let after = Date()
            let possibleTitles = try [before, after].map { date in
                try XCTUnwrap(
                    DatePickerCalendarModel(
                        containing: date, calendar: calendar, timeZone: calendar.timeZone,
                        locale: Locale(identifier: "en_US_POSIX"))
                ).title
            }
            XCTAssertTrue(possibleTitles.contains(try multiDatePickerTitle(label: title, in: host)))
            XCTAssertNotNil(try multiDatePickerNode(.previousMonth, label: title, in: host).onActivate)
            XCTAssertNotNil(try multiDatePickerNode(.nextMonth, label: title, in: host).onActivate)
            let grid = try multiDatePickerNode(.grid, label: title, in: host)
            let days = multiDatePickerDescendants(grid).filter { $0.accessibilityTraits.contains(.isButton) }
            XCTAssertGreaterThanOrEqual(days.count, 28)
            XCTAssertLessThanOrEqual(days.count, 31)
            XCTAssertTrue(days.allSatisfy { $0.isFocusable && $0.onActivate != nil })
            XCTAssertNil(host.coordinator.latestInstallationError)
        }
        XCTAssertTrue(selection.value.isEmpty)
        XCTAssertTrue(selection.writes.isEmpty)
    }

    func testFebruaryHasAHeaderSevenWeekdaysAndRealDayButtons() async throws {
        let selection = MultiDatePickerTestSelection([DateComponents(year: 2024, month: 2, day: 15)])
        let host = multiDatePickerHost { multiDatePickerView(selection: selection.binding) }
        defer { host.close() }
        host.render()
        let surface = try multiDatePickerSurface(in: host)
        let grid = try multiDatePickerNode(.grid, in: host)
        let weekdays = try multiDatePickerNode(.weekdays, in: host)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        XCTAssertEqual(surface.children.count, 2, "The calendar contains a header and a grid")
        XCTAssertEqual(surface.accessibilityChildBehavior, .contain)
        XCTAssertEqual(grid.children.count, 6, "Five week rows follow the weekday header")
        XCTAssertEqual(weekdays.children.compactMap(\.text), ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        let buttons = multiDatePickerDescendants(surface).filter { $0.accessibilityTraits.contains(.isButton) }
        XCTAssertEqual(buttons.count, 31)
        XCTAssertTrue(buttons.allSatisfy { $0.isFocusable && $0.onActivate != nil })
        for day in 1...29 {
            let node = try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, day)), in: host)
            XCTAssertEqual(node.accessibilityTraits.contains(.isSelected), day == 15)
            XCTAssertFalse(node.accessibilityLabel?.isEmpty ?? true)
        }
        let firstWeek = try multiDatePickerNode(.week(0), in: host)
        XCTAssertEqual(firstWeek.children.count, 7)
        XCTAssertTrue(firstWeek.children.prefix(4).allSatisfy { $0.isAccessibilityHidden && !$0.isFocusable })
        XCTAssertTrue(selection.writes.isEmpty)
    }

    func testMonthBrowsingCrossesYearWithoutWritingSelection() async throws {
        let initial: Set<DateComponents> = [
            DateComponents(year: 2024, month: 12, day: 31), DateComponents(year: 2025, month: 2, day: 10),
        ]
        let selection = MultiDatePickerTestSelection(initial)
        let host = multiDatePickerHost {
            multiDatePickerView(selection: selection.binding, now: { multiDatePickerDate(2024, 12, 31) })
        }
        defer { host.close() }
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "December 2024")
        try multiDatePickerActivate(.nextMonth, in: host)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "January 2025")
        try multiDatePickerActivate(.previousMonth, in: host)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "December 2024")
        try multiDatePickerActivate(.previousMonth, in: host)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "November 2024")
        XCTAssertEqual(selection.value, initial)
        XCTAssertTrue(selection.writes.isEmpty)
    }

    func testPointerTogglingReadsCurrentSetAndPreservesOtherMonths() async throws {
        let previousMonth = DateComponents(year: 2024, month: 1, day: 15)
        let nextMonth = DateComponents(year: 2024, month: 3, day: 1)
        let clicked = DateComponents(year: 2024, month: 2, day: 20)
        let selection = MultiDatePickerTestSelection([previousMonth])
        let host = multiDatePickerHost { multiDatePickerView(selection: selection.binding) }
        defer { host.close() }
        host.render()
        let day = try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host)
        var reloads = 0
        host.componentHost.onReloadCompleted = { reloads += 1 }
        selection.value.insert(nextMonth)
        multiDatePickerClick(day, in: host)
        XCTAssertEqual(selection.value, [previousMonth, nextMonth, clicked])
        XCTAssertEqual(selection.writes, [[previousMonth, nextMonth, clicked]])
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")

        multiDatePickerClick(try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host), in: host)
        XCTAssertEqual(selection.value, [previousMonth, nextMonth])
        XCTAssertEqual(selection.writes.count, 2)
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
    }

    func testTabEnterAndSpaceBrowseAndToggleTheFocusedDay() async throws {
        let selection = MultiDatePickerTestSelection()
        let host = multiDatePickerHost {
            multiDatePickerView(selection: selection.binding, now: { multiDatePickerDate(2024, 1, 15) })
        }
        defer { host.close() }
        host.render()
        guard multiDatePickerFocus(.nextMonth, in: host) else { return }
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "March 2024")
        guard multiDatePickerFocus(.previousMonth, in: host) else { return }
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        XCTAssertTrue(selection.writes.isEmpty)

        let day = MultiDatePickerNodeID.day(multiDatePickerDate(2024, 2, 20))
        guard multiDatePickerFocus(day, in: host) else { return }
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
        host.render()
        XCTAssertEqual(selection.value, [DateComponents(year: 2024, month: 2, day: 20)])
        XCTAssertEqual(host.runtime.focusedNode?.nodeTag, day.nodeTag)
        XCTAssertTrue(try multiDatePickerNode(day, in: host).accessibilityTraits.contains(.isSelected))
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
        host.render()
        XCTAssertTrue(selection.value.isEmpty)
        XCTAssertEqual(selection.writes.count, 2)
        XCTAssertEqual(host.runtime.focusedNode?.nodeTag, day.nodeTag)
    }

    func testAccessibleDefaultActionsPublishFullDateAndSelectedState() async throws {
        let selection = MultiDatePickerTestSelection([DateComponents(year: 2024, month: 2, day: 15)])
        let host = multiDatePickerHost { multiDatePickerView(selection: selection.binding) }
        defer { host.close() }
        host.render()
        let surface = try multiDatePickerSurface(in: host)
        let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: host.runtime))
        let calendar = try XCTUnwrap(projection.flattened().first { $0.sourceNode === surface })
        XCTAssertEqual(calendar.name, "Available dates")
        let buttons = calendar.flattened().filter { $0.controlType == .button }
        XCTAssertEqual(buttons.count, 31)
        XCTAssertTrue(buttons.allSatisfy(\.isEnabled))
        let selected = try XCTUnwrap(buttons.first { $0.name == "Thursday, February 15, 2024" })
        XCTAssertTrue(selected.isSelected)
        XCTAssertTrue(selected.invokeDefaultAction())
        host.render()
        XCTAssertTrue(selection.value.isEmpty)

        let current = try XCTUnwrap(AccessibilityProjection.project(runtime: host.runtime))
        let following = try XCTUnwrap(current.flattened().first { $0.name == "Friday, February 16, 2024" })
        XCTAssertFalse(following.isSelected)
        XCTAssertTrue(following.invokeDefaultAction())
        host.render()
        XCTAssertEqual(selection.value, [DateComponents(year: 2024, month: 2, day: 16)])
        XCTAssertEqual(selection.writes.count, 2)
        XCTAssertTrue(
            try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 16)), in: host)
                .accessibilityTraits.contains(.isSelected))
    }

    func testDisabledCalendarRetainsSemanticsButHasNoActivationOrFocus() async throws {
        let initial: Set<DateComponents> = [DateComponents(year: 2024, month: 2, day: 15)]
        let selection = MultiDatePickerTestSelection(initial)
        let host = multiDatePickerHost {
            AnyView(multiDatePickerView(selection: selection.binding).disabled(true))
        }
        defer { host.close() }
        host.render()
        let surface = try multiDatePickerSurface(in: host)
        let buttons = multiDatePickerDescendants(surface).filter { $0.accessibilityTraits.contains(.isButton) }
        XCTAssertEqual(buttons.count, 31)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        for button in buttons {
            XCTAssertFalse(button.isFocusable)
            XCTAssertFalse(button.isHitTestVisible)
            XCTAssertNil(button.onActivate)
            XCTAssertNil(button.onKeyDown)
            XCTAssertNil(button.onPointerUpInside)
            XCTAssertTrue(button.accessibilityActions.isEmpty)
            XCTAssertEqual(button.accessibilityRespondsToUserInteraction, false)
            XCTAssertFalse(button.accessibilityLabel?.isEmpty ?? true)
        }
        let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: host.runtime))
        let projectedButtons = projection.flattened().filter { $0.controlType == .button }
        XCTAssertEqual(projectedButtons.count, 31)
        for button in projectedButtons {
            XCTAssertFalse(button.isEnabled)
            XCTAssertFalse(button.invokeDefaultAction())
        }
        XCTAssertTrue(
            try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 15)), in: host)
                .accessibilityTraits.contains(.isSelected))
        multiDatePickerClick(try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host), in: host)
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
        XCTAssertNil(host.runtime.focusedNode)
        XCTAssertEqual(selection.value, initial)
        XCTAssertTrue(selection.writes.isEmpty)
    }

    func testFirstWeekdayLocaleAndExplicitTimeZoneReachTheCalendar() async throws {
        let instant = multiDatePickerDate(2024, 3, 1, minute: 30)
        let pacific = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        for firstWeekday in [1, 2] {
            let selection = MultiDatePickerTestSelection()
            let inherited = multiDatePickerCalendar(firstWeekday: firstWeekday, timeZone: tokyo)
            let host = multiDatePickerHost {
                multiDatePickerView(
                    selection: selection.binding, now: { instant }, calendar: inherited,
                    timeZone: pacific, locale: Locale(identifier: "fr_FR"))
            }
            defer { host.close() }
            host.render()
            let title = try multiDatePickerTitle(in: host).lowercased()
            XCTAssertTrue(title.contains("février"))
            XCTAssertTrue(title.contains("2024"))
            let weekdays = try multiDatePickerNode(.weekdays, in: host)
            let initials = weekdays.children.compactMap(\.text).map { String($0.lowercased().prefix(1)) }
            XCTAssertEqual(
                initials,
                firstWeekday == 1 ? ["d", "l", "m", "m", "j", "v", "s"] : ["l", "m", "m", "j", "v", "s", "d"])
            let firstDay = try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 1, hour: 8)), in: host)
            let firstRow = try multiDatePickerNode(.week(0), in: host)
            XCTAssertTrue(firstRow.children[firstWeekday == 1 ? 4 : 3] === firstDay)
            let leapDay = try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 29, hour: 8)), in: host)
            XCTAssertTrue(leapDay.accessibilityLabel?.contains("jeudi") == true)
            multiDatePickerClick(leapDay, in: host)
            XCTAssertEqual(selection.value, [DateComponents(year: 2024, month: 2, day: 29)])
            XCTAssertEqual(inherited.timeZone, tokyo, "The environment calendar value is not mutated")
        }
    }

    func testNonGregorianShortMonthCanSelectAndBrowseAcrossItsYearBoundary() async throws {
        let calendar = multiDatePickerCalendar(.coptic)
        let selection = MultiDatePickerTestSelection()
        let host = multiDatePickerHost {
            multiDatePickerView(
                selection: selection.binding, now: { multiDatePickerDate(2024, 9, 6) }, calendar: calendar)
        }
        defer { host.close() }
        host.render()
        XCTAssertTrue(try multiDatePickerTitle(in: host).contains("1740"))
        let grid = try multiDatePickerNode(.grid, in: host)
        XCTAssertEqual(grid.children.count, 5)
        XCTAssertEqual(grid.children.dropFirst().reduce(0) { $0 + $1.children.count }, 28)
        XCTAssertEqual(multiDatePickerDescendants(grid).filter { $0.accessibilityTraits.contains(.isButton) }.count, 5)
        try multiDatePickerActivate(.day(multiDatePickerDate(2024, 9, 7)), in: host)
        XCTAssertEqual(selection.value, [DateComponents(year: 1740, month: 13, day: 2)])
        try multiDatePickerActivate(.nextMonth, in: host)
        XCTAssertTrue(try multiDatePickerTitle(in: host).contains("1741"))
        XCTAssertNotNil(try multiDatePickerNode(.day(multiDatePickerDate(2024, 9, 11)), in: host).onActivate)
        XCTAssertEqual(selection.writes.count, 1)
        XCTAssertEqual(selection.value, [DateComponents(year: 1740, month: 13, day: 2)])
    }

    func testCompactRegularAndRTLGridsKeepSevenNonoverlappingColumns() async throws {
        let fixtures = [(2015, 2, 28, 0, 4), (2024, 2, 29, 4, 5), (2020, 8, 31, 6, 6)]
        for (year, month, dayCount, leading, rowCount) in fixtures {
            for width in [220.0, 280.0, 340.0] {
                var compactDayHeight: Double?
                for size in [ControlSize.small, .regular] {
                    var forwardTags: [String?] = []
                    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                        let selection = MultiDatePickerTestSelection()
                        let host = multiDatePickerHost(size: Size(width: width, height: 500)) {
                            AnyView(
                                multiDatePickerView(
                                    selection: selection.binding, now: { multiDatePickerDate(year, month, 15) },
                                    direction: direction, controlSize: size
                                ).labelsHidden())
                        }
                        defer { host.close() }
                        host.render()
                        let surface = try multiDatePickerSurface(in: host)
                        let grid = try multiDatePickerNode(.grid, in: host)
                        let weekdays = try multiDatePickerNode(.weekdays, in: host)
                        XCTAssertEqual(grid.children.count, rowCount + 1)
                        XCTAssertEqual(grid.children.dropFirst().reduce(0) { $0 + $1.children.count }, rowCount * 7)
                        XCTAssertLessThanOrEqual(rowCount * 7, 42)
                        multiDatePickerAssertContained(
                            multiDatePickerFrame(surface), in: Rect(x: 0, y: 0, width: width, height: 500))
                        let ordered = weekdays.children.sorted {
                            multiDatePickerFrame($0).minX < multiDatePickerFrame($1).minX
                        }
                        XCTAssertEqual(ordered.count, 7)
                        if direction == .leftToRight {
                            forwardTags = ordered.map(\.nodeTag)
                        } else {
                            XCTAssertEqual(ordered.map(\.nodeTag), Array(forwardTags.reversed()))
                        }
                        for row in grid.children {
                            XCTAssertEqual(row.children.count, 7)
                            let cells = row.children.sorted {
                                multiDatePickerFrame($0).minX < multiDatePickerFrame($1).minX
                            }
                            for cell in cells {
                                let bounds = multiDatePickerFrame(cell)
                                XCTAssertGreaterThan(bounds.width, 0)
                                XCTAssertGreaterThan(bounds.height, 0)
                                multiDatePickerAssertContained(bounds, in: multiDatePickerFrame(row))
                            }
                            for (left, right) in zip(cells, cells.dropFirst()) {
                                XCTAssertLessThanOrEqual(
                                    multiDatePickerFrame(left).maxX, multiDatePickerFrame(right).minX + 0.01)
                            }
                        }
                        for day in 1...dayCount {
                            let node = try multiDatePickerNode(.day(multiDatePickerDate(year, month, day)), in: host)
                            let logicalColumn = (leading + day - 1) % 7
                            let column = direction == .leftToRight ? logicalColumn : 6 - logicalColumn
                            XCTAssertEqual(
                                multiDatePickerFrame(node).minX,
                                multiDatePickerFrame(ordered[column]).minX, accuracy: 0.01)
                        }
                        let previous = try multiDatePickerNode(.previousMonth, in: host)
                        let next = try multiDatePickerNode(.nextMonth, in: host)
                        XCTAssertEqual(
                            multiDatePickerFrame(previous).minX < multiDatePickerFrame(next).minX,
                            direction == .leftToRight)
                        if direction == .leftToRight {
                            let height = try multiDatePickerNode(.day(multiDatePickerDate(year, month, 1)), in: host)
                                .resolvedFrame.height
                            if size == .small {
                                compactDayHeight = height
                            } else {
                                XCTAssertLessThan(try XCTUnwrap(compactDayHeight), height)
                            }
                        }
                        XCTAssertTrue(selection.writes.isEmpty)
                    }
                }
            }
        }
    }

    func testSelectionChangesActualRetainedPixelsAndDeselectRestoresThem() async throws {
        let selection = MultiDatePickerTestSelection()
        let host = multiDatePickerHost(size: Size(width: 300, height: 350)) {
            AnyView(multiDatePickerView(selection: selection.binding).labelsHidden().tint(.red))
        }
        defer { host.close() }
        let size = IntSize(width: 300, height: 350)
        let initial = GPUIRawSceneRasterizer.rasterize(host.runtime.renderScene(), size: size)
        let identifier = MultiDatePickerNodeID.day(multiDatePickerDate(2024, 2, 20))
        let frame = multiDatePickerFrame(try multiDatePickerNode(identifier, in: host))
        try multiDatePickerActivate(identifier, in: host)
        let selected = GPUIRawSceneRasterizer.rasterize(host.runtime.renderScene(), size: size)
        XCTAssertNotEqual(selected.pixels, initial.pixels)
        let offset = Int(frame.midY) * Int(selected.bytesPerRow) + (Int(frame.minX) + 3) * 4
        let pixels = [UInt8](selected.pixels)
        XCTAssertGreaterThan(Int(pixels[offset + 2]), Int(pixels[offset + 1]) + 100)
        XCTAssertGreaterThan(Int(pixels[offset + 2]), Int(pixels[offset]) + 100)
        XCTAssertEqual(pixels[offset + 3], 255)
        try multiDatePickerActivate(identifier, in: host)
        let restored = GPUIRawSceneRasterizer.rasterize(host.runtime.renderScene(), size: size)
        XCTAssertEqual(restored.pixels, initial.pixels)
        XCTAssertTrue(selection.value.isEmpty)
    }

    func testHiddenLabelsAndGroupedFormKeepTheNamedInteractiveCalendar() async throws {
        for hidden in [false, true] {
            let selection = MultiDatePickerTestSelection()
            let host = multiDatePickerHost(size: Size(width: 700, height: 500)) {
                AnyView(
                    Form {
                        Section("Schedule") {
                            if hidden {
                                multiDatePickerView("Schedule dates", selection: selection.binding).labelsHidden()
                            } else {
                                multiDatePickerView("Schedule dates", selection: selection.binding)
                            }
                        }
                    }.formStyle(.grouped))
            }
            defer { host.close() }
            host.render()
            let surface = try multiDatePickerSurface("Schedule dates", in: host)
            XCTAssertEqual(surface.accessibilityChildBehavior, .contain)
            let labels = multiDatePickerDescendants(host.runtime.root).filter { $0.text == "Schedule dates" }
            XCTAssertEqual(labels.count, hidden ? 0 : 1)
            if !hidden {
                let row = try XCTUnwrap(
                    multiDatePickerDescendants(host.runtime.root).first {
                        $0.formRowLabelChildIndex != nil && multiDatePickerDescendants($0).contains { $0 === surface }
                    })
                XCTAssertEqual(row.children.count, 2)
            }
            let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: host.runtime))
            let calendar = try XCTUnwrap(projection.flattened().first { $0.sourceNode === surface })
            XCTAssertEqual(calendar.name, "Schedule dates")
            XCTAssertEqual(calendar.flattened().filter { $0.controlType == .button }.count, 31)
        }
    }

    func testInvalidInitialDateFailsClosedWithoutConstructingDayActions() async throws {
        for seconds in [Double.nan, Double.infinity, -Double.infinity] {
            let selection = MultiDatePickerTestSelection()
            var clockReads = 0
            let host = multiDatePickerHost {
                multiDatePickerView(
                    selection: selection.binding,
                    now: {
                        clockReads += 1
                        return Date(timeIntervalSinceReferenceDate: seconds)
                    })
            }
            defer { host.close() }
            host.render()
            host.reload()
            host.render()
            let surface = try multiDatePickerSurface(in: host)
            XCTAssertTrue(multiDatePickerDescendants(surface).contains { $0.text == "Calendar unavailable" })
            XCTAssertFalse(multiDatePickerDescendants(surface).contains { $0.onActivate != nil || $0.isFocusable })
            XCTAssertEqual(clockReads, 1)
            XCTAssertTrue(selection.value.isEmpty)
            XCTAssertTrue(selection.writes.isEmpty)
        }
    }
}
