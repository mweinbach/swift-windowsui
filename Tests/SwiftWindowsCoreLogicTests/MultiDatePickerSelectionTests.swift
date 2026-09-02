import Foundation
import XCTest

@testable import WinSwiftUI

final class MultiDatePickerSelectionTests: XCTestCase {
    func testGregorianInsertionKeepsExistingBareYearMonthDayRepresentation() async throws {
        let calendar = multiDatePickerCalendar()
        let day = try multiDatePickerDay(multiDatePickerDate(2024, 2, 29))
        let selection = try XCTUnwrap(MultiDatePickerDaySelection(day: day, calendar: calendar))
        let expected = DateComponents(year: 2024, month: 2, day: 29)

        XCTAssertEqual(selection.insertion, expected)
        XCTAssertNil(selection.insertion.calendar)
        XCTAssertNil(selection.insertion.timeZone)
        XCTAssertNil(selection.insertion.era)
        XCTAssertNil(selection.insertion.isLeapMonth)
        XCTAssertEqual(selection.toggling(in: []), [expected])
        XCTAssertEqual(selection.toggling(in: [expected]), [])
    }

    func testLegacyAndDocumentedCalendarAliasesRemoveOnlyTheClickedDay() async throws {
        let calendar = multiDatePickerCalendar()
        let day = try multiDatePickerDay(multiDatePickerDate(2024, 2, 15))
        let selection = try XCTUnwrap(MultiDatePickerDaySelection(day: day, calendar: calendar))
        let legacy = DateComponents(year: 2024, month: 2, day: 15)
        let calendarBearing = DateComponents(calendar: calendar, year: 2024, month: 2, day: 15)
        let nextMonth = DateComponents(year: 2024, month: 3, day: 15)
        let previousYear = DateComponents(calendar: calendar, year: 2023, month: 2, day: 15)
        let original: Set<DateComponents> = [legacy, calendarBearing, nextMonth, previousYear]

        XCTAssertNotEqual(legacy, calendarBearing)
        XCTAssertTrue(selection.isSelected(in: [legacy]))
        XCTAssertTrue(selection.isSelected(in: [calendarBearing]))
        XCTAssertEqual(selection.toggling(in: original), [nextMonth, previousYear])
        XCTAssertEqual(original, [legacy, calendarBearing, nextMonth, previousYear])

        var expectedAliases: [DateComponents] = []
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
                        expectedAliases.append(alias)
                        XCTAssertTrue(selection.isSelected(in: [alias]))
                        XCTAssertEqual(selection.toggling(in: [alias, nextMonth]), [nextMonth])
                    }
                }
            }
        }
        XCTAssertEqual(selection.aliases.count, expectedAliases.count)
        var remaining = expectedAliases
        for actual in selection.aliases {
            let index = try XCTUnwrap(
                remaining.firstIndex { $0 == actual && $0.isLeapMonth == actual.isLeapMonth })
            remaining.remove(at: index)
        }
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInvalidForeignAndAdditionalComponentsRemainUntouched() async throws {
        let calendar = multiDatePickerCalendar()
        let day = try multiDatePickerDay(multiDatePickerDate(2023, 3, 1))
        let selection = try XCTUnwrap(MultiDatePickerDaySelection(day: day, calendar: calendar))
        var otherSettings = calendar
        otherSettings.firstWeekday = 2
        let invalid = DateComponents(year: 2023, month: 2, day: 29)
        let foreignCalendar = DateComponents(
            calendar: multiDatePickerCalendar(.buddhist), year: 2023, month: 3, day: 1)
        let foreignZone = DateComponents(
            timeZone: TimeZone(secondsFromGMT: 3_600), year: 2023, month: 3, day: 1)
        let differentCalendarSettings = DateComponents(calendar: otherSettings, year: 2023, month: 3, day: 1)
        let explicitHour = DateComponents(year: 2023, month: 3, day: 1, hour: 0)
        let explicitWeekday = DateComponents(year: 2023, month: 3, day: 1, weekday: 4)
        let incomplete = DateComponents(month: 3, day: 1)
        let untouched: Set<DateComponents> = [
            invalid, foreignCalendar, foreignZone, differentCalendarSettings, explicitHour, explicitWeekday, incomplete,
        ]

        XCTAssertFalse(selection.isSelected(in: untouched))
        let inserted = selection.toggling(in: untouched)
        XCTAssertEqual(inserted, untouched.union([DateComponents(year: 2023, month: 3, day: 1)]))
        XCTAssertEqual(selection.toggling(in: inserted), untouched)
        for entry in untouched {
            XCTAssertFalse(selection.aliases.contains(entry))
        }
    }

    func testJapaneseEraFallbackKeepsTheSameNumbersInAnotherEraDistinct() async throws {
        let calendar = multiDatePickerCalendar(.japanese)
        let historicalDay = try multiDatePickerDay(multiDatePickerDate(1990, 5, 1), calendar: calendar)
        let modernDay = try multiDatePickerDay(multiDatePickerDate(2020, 5, 1), calendar: calendar)
        let historical = try XCTUnwrap(MultiDatePickerDaySelection(day: historicalDay, calendar: calendar))
        let modern = try XCTUnwrap(MultiDatePickerDaySelection(day: modernDay, calendar: calendar))
        let oldComponents = calendar.dateComponents([.calendar, .era, .year, .month, .day], from: historicalDay.start)
        let newComponents = calendar.dateComponents([.calendar, .era, .year, .month, .day], from: modernDay.start)

        XCTAssertEqual(oldComponents.year, 2)
        XCTAssertEqual(newComponents.year, 2)
        XCTAssertEqual(oldComponents.month, newComponents.month)
        XCTAssertEqual(oldComponents.day, newComponents.day)
        XCTAssertNotEqual(oldComponents.era, newComponents.era)
        XCTAssertNotEqual(historical.insertion, DateComponents(year: 2, month: 5, day: 1))
        XCTAssertEqual(calendar.date(from: historical.insertion), historicalDay.start)
        XCTAssertNotNil(historical.insertion.era)
        XCTAssertTrue(historical.isSelected(in: [oldComponents]))
        XCTAssertFalse(historical.isSelected(in: [newComponents]))
        XCTAssertFalse(modern.isSelected(in: [oldComponents]))
        XCTAssertEqual(historical.toggling(in: [oldComponents, newComponents]), [newComponents])
    }

    func testLeapMonthFallbackKeepsOrdinaryMonthSelectionDistinct() async throws {
        let calendar = multiDatePickerCalendar(.chinese)
        let ordinaryDay = try multiDatePickerDay(multiDatePickerDate(2023, 2, 20), calendar: calendar)
        let leapDay = try multiDatePickerDay(multiDatePickerDate(2023, 3, 22), calendar: calendar)
        let ordinary = try XCTUnwrap(MultiDatePickerDaySelection(day: ordinaryDay, calendar: calendar))
        let leap = try XCTUnwrap(MultiDatePickerDaySelection(day: leapDay, calendar: calendar))
        let ordinaryComponents = calendar.dateComponents(
            [.calendar, .era, .year, .month, .day], from: ordinaryDay.start)
        let leapComponents = calendar.dateComponents([.calendar, .era, .year, .month, .day], from: leapDay.start)

        XCTAssertEqual(ordinaryComponents.year, leapComponents.year)
        XCTAssertEqual(ordinaryComponents.month, 2)
        XCTAssertEqual(leapComponents.month, 2)
        XCTAssertEqual(ordinaryComponents.day, 1)
        XCTAssertEqual(leapComponents.day, 1)
        XCTAssertEqual(ordinaryComponents.isLeapMonth, false)
        XCTAssertEqual(leapComponents.isLeapMonth, true)
        XCTAssertEqual(leap.insertion.isLeapMonth, true)
        XCTAssertEqual(calendar.date(from: leap.insertion), leapDay.start)
        XCTAssertFalse(ordinary.isSelected(in: [leapComponents]))
        XCTAssertFalse(leap.isSelected(in: [ordinaryComponents]))
        XCTAssertEqual(leap.toggling(in: [ordinaryComponents]), [ordinaryComponents, leap.insertion])
        XCTAssertEqual(leap.toggling(in: [ordinaryComponents, leapComponents]), [ordinaryComponents])
    }

    func testSelectionSetIsNotLimitedToTheNumberOfVisibleCells() async throws {
        let calendar = multiDatePickerCalendar()
        let first = multiDatePickerDate(2024, 1, 1)
        let dates: Set<DateComponents> = Set(
            (0..<96).map { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: first)!
                return DateComponents(
                    year: calendar.component(.year, from: date), month: calendar.component(.month, from: date),
                    day: calendar.component(.day, from: date))
            })
        let day = try multiDatePickerDay(multiDatePickerDate(2024, 2, 15))
        let selection = try XCTUnwrap(MultiDatePickerDaySelection(day: day, calendar: calendar))
        XCTAssertEqual(dates.count, 96)
        XCTAssertTrue(selection.isSelected(in: dates))
        XCTAssertEqual(
            selection.toggling(in: dates), dates.subtracting([DateComponents(year: 2024, month: 2, day: 15)]))

        let future = try XCTUnwrap(
            MultiDatePickerDaySelection(day: multiDatePickerDay(multiDatePickerDate(2024, 6, 1)), calendar: calendar))
        XCTAssertEqual(future.toggling(in: dates), dates.union([DateComponents(year: 2024, month: 6, day: 1)]))
        XCTAssertEqual(future.toggling(in: dates).count, 97)
    }

    func testAliasConstructionIsBoundedAndEveryAliasRoundTripsToTheExactDay() async throws {
        let fixtures: [(Calendar.Identifier, Date, TimeZone)] = [
            (.gregorian, multiDatePickerDate(2024, 3, 10, hour: 12), TimeZone(identifier: "America/New_York")!),
            (.gregorian, multiDatePickerDate(2024, 11, 3, hour: 12), TimeZone(identifier: "America/New_York")!),
            (.buddhist, multiDatePickerDate(2024, 2, 29), TimeZone(secondsFromGMT: 0)!),
            (.coptic, multiDatePickerDate(2024, 9, 6), TimeZone(secondsFromGMT: 0)!),
            (.japanese, multiDatePickerDate(1990, 5, 1), TimeZone(secondsFromGMT: 0)!),
            (.chinese, multiDatePickerDate(2023, 3, 22), TimeZone(secondsFromGMT: 0)!),
        ]
        for (identifier, date, timeZone) in fixtures {
            let calendar = multiDatePickerCalendar(identifier, timeZone: timeZone)
            let day = try multiDatePickerDay(date, calendar: calendar)
            let selection = try XCTUnwrap(MultiDatePickerDaySelection(day: day, calendar: calendar))
            XCTAssertFalse(selection.aliases.isEmpty)
            XCTAssertLessThanOrEqual(selection.aliases.count, 16)
            XCTAssertTrue(selection.aliases.contains(selection.insertion))
            for alias in selection.aliases {
                XCTAssertEqual(calendar.date(from: alias), day.start)
                XCTAssertNil(alias.hour)
                XCTAssertNil(alias.minute)
                XCTAssertNil(alias.weekday)
            }
        }
    }
}
