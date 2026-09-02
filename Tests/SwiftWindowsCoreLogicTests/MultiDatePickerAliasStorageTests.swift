import Foundation
import XCTest

@testable import WinSwiftUI

final class MultiDatePickerAliasStorageTests: XCTestCase {
    func testGregorianAliasesRetainBothLeapMarkerFormsForEveryMetadataCombination() async throws {
        let calendar = multiDatePickerCalendar()
        let day = try multiDatePickerDay(multiDatePickerDate(2024, 2, 15))
        let selection = try XCTUnwrap(MultiDatePickerDaySelection(day: day, calendar: calendar))

        XCTAssertEqual(selection.aliases.count, 16)
        XCTAssertEqual(selection.aliases.filter { $0.isLeapMonth == nil }.count, 8)
        XCTAssertEqual(selection.aliases.filter { $0.isLeapMonth == false }.count, 8)
        for includesCalendar in [false, true] {
            for includesTimeZone in [false, true] {
                for includesEra in [false, true] {
                    let aliases = selection.aliases.filter {
                        $0.calendar == (includesCalendar ? calendar : nil)
                            && $0.timeZone == (includesTimeZone ? calendar.timeZone : nil)
                            && $0.era == (includesEra ? 1 : nil)
                    }
                    XCTAssertEqual(aliases.count, 2)
                    XCTAssertEqual(aliases.filter { $0.isLeapMonth == nil }.count, 1)
                    XCTAssertEqual(aliases.filter { $0.isLeapMonth == false }.count, 1)
                    for alias in aliases {
                        XCTAssertEqual(alias.year, 2024)
                        XCTAssertEqual(alias.month, 2)
                        XCTAssertEqual(alias.day, 15)
                        XCTAssertEqual(calendar.date(from: alias), day.start)
                    }
                }
            }
        }
    }

    func testEachLeapMarkerAliasIndependentlyTogglesWithoutChangingUnrelatedSelections() async throws {
        let calendar = multiDatePickerCalendar()
        let day = try multiDatePickerDay(multiDatePickerDate(2024, 2, 15))
        let selection = try XCTUnwrap(MultiDatePickerDaySelection(day: day, calendar: calendar))
        let otherDate = DateComponents(year: 2024, month: 3, day: 15)
        var foreignRepresentation = DateComponents(
            calendar: multiDatePickerCalendar(.buddhist), year: 2024, month: 2, day: 15)
        foreignRepresentation.isLeapMonth = false
        let untouched: Set<DateComponents> = [otherDate, foreignRepresentation]
        var checked = 0

        for includesCalendar in [false, true] {
            for includesTimeZone in [false, true] {
                for includesEra in [false, true] {
                    for includesLeapMarker in [false, true] {
                        var alias = DateComponents(
                            calendar: includesCalendar ? calendar : nil,
                            timeZone: includesTimeZone ? calendar.timeZone : nil,
                            era: includesEra ? 1 : nil, year: 2024, month: 2, day: 15)
                        if includesLeapMarker { alias.isLeapMonth = false }
                        XCTAssertEqual(calendar.date(from: alias), day.start)
                        let input: Set<DateComponents> = [alias, otherDate, foreignRepresentation]

                        XCTAssertEqual(input.count, 3)
                        XCTAssertTrue(selection.isSelected(in: input))
                        let output = selection.toggling(in: input)
                        XCTAssertEqual(output, untouched)
                        XCTAssertEqual(output.count, 2)
                        XCTAssertEqual(input, [alias, otherDate, foreignRepresentation])
                        XCTAssertEqual(input.count, 3)
                        for expected in [alias, otherDate, foreignRepresentation] {
                            let unchanged = try XCTUnwrap(input.first { $0 == expected })
                            XCTAssertEqual(unchanged.isLeapMonth, expected.isLeapMonth)
                        }
                        for expected in [otherDate, foreignRepresentation] {
                            let retained = try XCTUnwrap(output.first { $0 == expected })
                            XCTAssertEqual(retained.isLeapMonth, expected.isLeapMonth)
                        }
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 16)
    }
}
