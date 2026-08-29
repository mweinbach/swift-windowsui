import Foundation
import XCTest

@testable import WinSwiftUI

final class DatePickerCalendarModelTests: XCTestCase {
    func testGregorianLeapAndNonLeapFebruaryHaveExpectedCivilDays() async throws {
        let fixtures: [(year: Int, days: Int)] = [(1900, 28), (2000, 29), (2023, 28), (2024, 29)]

        for fixture in fixtures {
            let model = try calendarModel(containing: calendarUTCDate(fixture.year, 2, 15))
            let days = model.cells.compactMap { $0 }

            XCTAssertEqual(model.month.start, calendarUTCDate(fixture.year, 2, 1))
            XCTAssertEqual(model.month.end, calendarUTCDate(fixture.year, 3, 1))
            XCTAssertEqual(days.map(\.number), Array(1...fixture.days), "February \(fixture.year)")
            for (day, number) in zip(days, 1...fixture.days) {
                let expectedEnd =
                    number == fixture.days
                    ? calendarUTCDate(fixture.year, 3, 1)
                    : calendarUTCDate(fixture.year, 2, number + 1)
                XCTAssertEqual(day.start, calendarUTCDate(fixture.year, 2, number))
                XCTAssertEqual(day.end, expectedEnd)
            }
        }
    }

    func testMonthGridUsesConfiguredFirstWeekday() async throws {
        // January 1, 2024 was Monday, independently of the presentation locale.
        let fixtures: [(firstWeekday: Int, leading: Int)] = [(1, 1), (2, 0), (7, 2)]

        for fixture in fixtures {
            let model = try calendarModel(
                containing: calendarUTCDate(2024, 1, 15),
                firstWeekday: fixture.firstWeekday,
                locale: Locale(identifier: "fr_FR")
            )

            XCTAssertEqual(model.cells.firstIndex { $0 != nil }, fixture.leading)
            XCTAssertEqual(model.cells.firstIndex { $0?.number == 1 }, fixture.leading)
            XCTAssertTrue(model.cells.prefix(fixture.leading).allSatisfy { $0 == nil })
            XCTAssertEqual(model.weekdaySymbols.count, 7)
            XCTAssertEqual(model.cells.compactMap { $0?.number }, Array(1...31))
        }
    }

    func testShortAndLongMonthsHaveExpectedWeekRows() async throws {
        let fixtures: [(year: Int, month: Int, days: Int, rows: Int, leading: Int)] = [
            (2026, 2, 28, 4, 0),
            (2021, 2, 28, 5, 1),
            (2024, 4, 30, 5, 1),
            (2024, 6, 30, 6, 6),
            (2024, 8, 31, 5, 4),
            (2024, 3, 31, 6, 5),
        ]

        for fixture in fixtures {
            let model = try calendarModel(containing: calendarUTCDate(fixture.year, fixture.month, 15))

            XCTAssertEqual(model.rowCount, fixture.rows, "\(fixture.year)-\(fixture.month)")
            XCTAssertEqual(model.cells.count, fixture.rows * 7)
            XCTAssertEqual(model.cells.firstIndex { $0 != nil }, fixture.leading)
            XCTAssertEqual(model.cells.compactMap { $0?.number }, Array(1...fixture.days))
            XCTAssertTrue(model.cells.prefix(fixture.leading).allSatisfy { $0 == nil })
            XCTAssertTrue(model.cells.dropFirst(fixture.leading + fixture.days).allSatisfy { $0 == nil })
        }
    }

    func testMonthNavigationCrossesYearWithoutDayOverflow() async throws {
        let january = try calendarModel(containing: calendarUTCDate(2024, 1, 31, hour: 23, minute: 59))
        let december = try calendarModel(containing: calendarUTCDate(2024, 12, 31))

        XCTAssertEqual(january.adjacentMonth(direction: 1, range: .unbounded), calendarUTCDate(2024, 2, 1))
        XCTAssertEqual(january.adjacentMonth(direction: -1, range: .unbounded), calendarUTCDate(2023, 12, 1))
        XCTAssertEqual(december.adjacentMonth(direction: 1, range: .unbounded), calendarUTCDate(2025, 1, 1))
        XCTAssertEqual(december.adjacentMonth(direction: -1, range: .unbounded), calendarUTCDate(2024, 11, 1))
        for direction in [0, 2, -2, Int.max, Int.min] {
            XCTAssertNil(january.adjacentMonth(direction: direction, range: .unbounded))
        }
    }

    func testTimeZoneSelectsCorrectDisplayedMonth() async throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let instant = calendarUTCDate(2024, 3, 1, minute: 30)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        calendar.firstWeekday = 1

        let western = try XCTUnwrap(
            DatePickerCalendarModel(
                containing: instant,
                calendar: calendar,
                timeZone: losAngeles,
                locale: Locale(identifier: "en_US_POSIX")
            )
        )
        let utc = try calendarModel(containing: instant)
        let lastWesternDay = try calendarDay(29, in: western)

        XCTAssertEqual(western.month.start, calendarUTCDate(2024, 2, 1, hour: 8))
        XCTAssertEqual(western.month.end, calendarUTCDate(2024, 3, 1, hour: 8))
        XCTAssertEqual(western.cells.compactMap { $0?.number }, Array(1...29))
        XCTAssertEqual(lastWesternDay.start, calendarUTCDate(2024, 2, 29, hour: 8))
        XCTAssertEqual(lastWesternDay.end, calendarUTCDate(2024, 3, 1, hour: 8))
        XCTAssertEqual(utc.month.start, calendarUTCDate(2024, 3, 1))
        XCTAssertEqual(utc.month.end, calendarUTCDate(2024, 4, 1))
        XCTAssertEqual(calendar.timeZone, tokyo)
    }

    func testNonGregorianCalendarUsesBuddhistYear() async throws {
        let model = try calendarModel(
            containing: calendarUTCDate(2024, 2, 15),
            identifier: .buddhist
        )
        let leapDay = try calendarDay(29, in: model)

        XCTAssertEqual(model.month.start, calendarUTCDate(2024, 2, 1))
        XCTAssertEqual(model.month.end, calendarUTCDate(2024, 3, 1))
        XCTAssertEqual(model.cells.compactMap { $0?.number }, Array(1...29))
        XCTAssertTrue(model.title.contains("2567"))
        XCTAssertFalse(model.title.contains("2024"))
        XCTAssertTrue(leapDay.accessibilityLabel.contains("2567"))
        XCTAssertEqual(leapDay.start, calendarUTCDate(2024, 2, 29))

        // ICU's Coptic epoch is 1_824_665; 1740/13/1 has Julian day 2_460_560.
        // Gregorian 2024-09-06 has the same Julian day. Coptic 1741/1/1 is
        // Julian day 2_460_565, so this thirteenth month has exactly five days.
        let coptic = try calendarModel(containing: calendarUTCDate(2024, 9, 6), identifier: .coptic)
        let firstCopticDay = try calendarDay(1, in: coptic)
        let lastCopticDay = try calendarDay(5, in: coptic)

        XCTAssertEqual(coptic.month.start, calendarUTCDate(2024, 9, 6))
        XCTAssertEqual(coptic.month.end, calendarUTCDate(2024, 9, 11))
        XCTAssertEqual(coptic.cells.compactMap { $0?.number }, [1, 2, 3, 4, 5])
        XCTAssertEqual(coptic.rowCount, 4)
        XCTAssertEqual(coptic.cells.count, 28)
        XCTAssertEqual(coptic.cells.firstIndex { $0?.number == 1 }, 5)
        XCTAssertTrue(coptic.cells.dropFirst(10).allSatisfy { $0 == nil })
        XCTAssertTrue(coptic.title.contains("1740"))
        XCTAssertTrue(firstCopticDay.accessibilityLabel.contains("1740"))
        XCTAssertEqual(firstCopticDay.start, calendarUTCDate(2024, 9, 6))
        XCTAssertEqual(firstCopticDay.end, calendarUTCDate(2024, 9, 7))
        XCTAssertEqual(lastCopticDay.start, calendarUTCDate(2024, 9, 10))
        XCTAssertEqual(lastCopticDay.end, calendarUTCDate(2024, 9, 11))
        XCTAssertEqual(coptic.adjacentMonth(direction: -1, range: .unbounded), calendarUTCDate(2024, 8, 7))
        XCTAssertEqual(coptic.adjacentMonth(direction: 1, range: .unbounded), calendarUTCDate(2024, 9, 11))
    }

    func testLocaleProvidesMonthAndWeekdayNames() async throws {
        let model = try calendarModel(
            containing: calendarUTCDate(2024, 3, 15),
            firstWeekday: 2,
            locale: Locale(identifier: "fr_FR")
        )
        let friday = try calendarDay(15, in: model)
        let weekdayInitials = model.weekdaySymbols.map { String($0.lowercased().prefix(1)) }
        let accessibleDate = friday.accessibilityLabel.lowercased()

        XCTAssertTrue(model.title.lowercased().contains("mars"))
        XCTAssertTrue(model.title.contains("2024"))
        XCTAssertEqual(weekdayInitials, ["l", "m", "m", "j", "v", "s", "d"])
        XCTAssertEqual(friday.label, "15")
        XCTAssertTrue(accessibleDate.contains("vendredi"))
        XCTAssertTrue(accessibleDate.contains("mars"))
        XCTAssertTrue(accessibleDate.contains("15"))
        XCTAssertTrue(accessibleDate.contains("2024"))
    }

    func testDaySelectionPreservesSubsecondWallTime() async throws {
        let model = try calendarModel(containing: calendarUTCDate(2024, 2, 15))
        let leapDay = try calendarDay(29, in: model)
        let fixtures: [(hour: Int, minute: Int, second: Int, fraction: TimeInterval)] = [
            (14, 23, 45, 0.125),
            (0, 0, 0, 0.625),
            (23, 59, 59, 0.875),
        ]

        for fixture in fixtures {
            let selected = calendarUTCDate(
                2024, 1, 15,
                hour: fixture.hour, minute: fixture.minute, second: fixture.second,
                fraction: fixture.fraction
            )
            let expected = calendarUTCDate(
                2024, 2, 29,
                hour: fixture.hour, minute: fixture.minute, second: fixture.second,
                fraction: fixture.fraction
            )

            XCTAssertEqual(model.selectedDate(for: leapDay, preserving: selected, range: .unbounded), expected)
            XCTAssertEqual(model.selectedDate(for: leapDay, preserving: expected, range: .unbounded), expected)
        }

        // Half a nanosecond survives Date's Double representation near its epoch,
        // but converting through an integer nanosecond component would discard it.
        let fractionalSecond: TimeInterval = 0.000_000_000_5
        let nearReference = Date(timeIntervalSinceReferenceDate: fractionalSecond)
        let referenceModel = try calendarModel(containing: Date(timeIntervalSinceReferenceDate: 0))
        let secondReferenceDay = try calendarDay(2, in: referenceModel)
        let candidate = try XCTUnwrap(
            referenceModel.selectedDate(for: secondReferenceDay, preserving: nearReference, range: .unbounded)
        )
        let expected = Date(timeIntervalSinceReferenceDate: 86_400 + fractionalSecond)

        XCTAssertEqual(candidate, expected)
        XCTAssertGreaterThan(candidate, Date(timeIntervalSinceReferenceDate: 86_400))

        // A fraction representable in 2001 can round to the following midnight
        // in 2024. The enabled day still chooses its last representable instant.
        let almostReferenceMidnight = Date(timeIntervalSinceReferenceDate: 86_400.0.nextDown)
        let lastLeapInstant = Date(timeIntervalSinceReferenceDate: leapDay.end.timeIntervalSinceReferenceDate.nextDown)
        XCTAssertEqual(
            model.selectedDate(for: leapDay, preserving: almostReferenceMidnight, range: .unbounded),
            lastLeapInstant)
    }

    func testSpringDSTGapMovesToNextMatchingTimeWithinDay() async throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let model = try calendarModel(
            containing: calendarUTCDate(2024, 3, 10, hour: 12),
            timeZone: newYork
        )
        let springDay = try calendarDay(10, in: model)
        // March 9 is EST; March 10's missing 02:37 becomes 03:37 EDT, not 03:00.
        let selected = calendarUTCDate(2024, 3, 9, hour: 7, minute: 37, second: 12, fraction: 0.125)
        let expected = calendarUTCDate(2024, 3, 10, hour: 7, minute: 37, second: 12, fraction: 0.125)

        XCTAssertEqual(springDay.start, calendarUTCDate(2024, 3, 10, hour: 5))
        XCTAssertEqual(springDay.end, calendarUTCDate(2024, 3, 11, hour: 4))
        XCTAssertEqual(springDay.end.timeIntervalSince(springDay.start), 23 * 60 * 60)
        XCTAssertEqual(model.selectedDate(for: springDay, preserving: selected, range: .unbounded), expected)
    }

    func testAutumnDSTRepeatUsesFirstMatchingInstant() async throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let model = try calendarModel(
            containing: calendarUTCDate(2024, 11, 3, hour: 12),
            timeZone: newYork
        )
        let autumnDay = try calendarDay(3, in: model)
        let firstOccurrence = calendarUTCDate(2024, 11, 3, hour: 5, minute: 37, second: 12, fraction: 0.125)
        let secondOccurrence = calendarUTCDate(2024, 11, 3, hour: 6, minute: 37, second: 12, fraction: 0.125)
        let selectedDates = [
            calendarUTCDate(2024, 11, 2, hour: 5, minute: 37, second: 12, fraction: 0.125),
            calendarUTCDate(2024, 11, 4, hour: 6, minute: 37, second: 12, fraction: 0.125),
        ]

        XCTAssertEqual(autumnDay.start, calendarUTCDate(2024, 11, 3, hour: 4))
        XCTAssertEqual(autumnDay.end, calendarUTCDate(2024, 11, 4, hour: 5))
        XCTAssertEqual(autumnDay.end.timeIntervalSince(autumnDay.start), 25 * 60 * 60)
        for selected in selectedDates {
            let candidate = model.selectedDate(for: autumnDay, preserving: selected, range: .unbounded)
            XCTAssertEqual(candidate, firstOccurrence)
            XCTAssertNotEqual(candidate, secondOccurrence)
        }
    }

    func testClosedRangeClampsPartialDaysAndExcludesDisjointDays() async throws {
        let model = try calendarModel(containing: calendarUTCDate(2024, 6, 15))
        let lowerBound = calendarUTCDate(2024, 6, 10, hour: 12, fraction: 0.25)
        let upperBound = calendarUTCDate(2024, 6, 12, hour: 8, fraction: 0.75)
        let range = DatePickerRange(lowerBound: lowerBound, upperBound: upperBound)
        let early = calendarUTCDate(2024, 6, 1, hour: 6, minute: 45, second: 12, fraction: 0.5)
        let late = calendarUTCDate(2024, 6, 1, hour: 14)
        let lowerDay = try calendarDay(10, in: model)
        let middleDay = try calendarDay(11, in: model)
        let upperDay = try calendarDay(12, in: model)

        for number in 1...30 {
            XCTAssertEqual(
                model.isEnabled(try calendarDay(number, in: model), range: range),
                (10...12).contains(number)
            )
        }
        XCTAssertEqual(model.selectedDate(for: lowerDay, preserving: early, range: range), lowerBound)
        XCTAssertEqual(
            model.selectedDate(for: middleDay, preserving: early, range: range),
            calendarUTCDate(2024, 6, 11, hour: 6, minute: 45, second: 12, fraction: 0.5)
        )
        XCTAssertEqual(model.selectedDate(for: upperDay, preserving: late, range: range), upperBound)
        XCTAssertNil(model.selectedDate(for: try calendarDay(9, in: model), preserving: early, range: range))
        XCTAssertNil(model.selectedDate(for: try calendarDay(13, in: model), preserving: early, range: range))

        let pointRange = DatePickerRange(lowerBound: upperBound, upperBound: upperBound)
        XCTAssertTrue(model.isEnabled(upperDay, range: pointRange))
        XCTAssertFalse(model.isEnabled(middleDay, range: pointRange))
        XCTAssertEqual(model.selectedDate(for: upperDay, preserving: late, range: pointRange), upperBound)
    }

    func testFromAndThroughRangesAllowExactBoundaryInstants() async throws {
        let model = try calendarModel(containing: calendarUTCDate(2024, 6, 15))
        let boundary = calendarUTCDate(2024, 6, 10, hour: 12, fraction: 0.25)
        let from = DatePickerRange(lowerBound: boundary)
        let through = DatePickerRange(upperBound: boundary)
        let day = try calendarDay(10, in: model)
        let earlierDay = try calendarDay(9, in: model)
        let laterDay = try calendarDay(11, in: model)

        XCTAssertTrue(model.isEnabled(day, range: from))
        XCTAssertFalse(model.isEnabled(earlierDay, range: from))
        XCTAssertTrue(model.isEnabled(laterDay, range: from))
        XCTAssertEqual(
            model.selectedDate(for: day, preserving: calendarUTCDate(2024, 6, 1), range: from),
            boundary
        )
        XCTAssertTrue(model.isEnabled(day, range: through))
        XCTAssertTrue(model.isEnabled(earlierDay, range: through))
        XCTAssertFalse(model.isEnabled(laterDay, range: through))
        XCTAssertEqual(
            model.selectedDate(for: day, preserving: calendarUTCDate(2024, 6, 1, hour: 23), range: through),
            boundary
        )

        let midnight = calendarUTCDate(2024, 6, 10)
        let fromMidnight = DatePickerRange(lowerBound: midnight)
        let throughMidnight = DatePickerRange(upperBound: midnight)
        XCTAssertFalse(model.isEnabled(earlierDay, range: fromMidnight))
        XCTAssertTrue(model.isEnabled(day, range: fromMidnight))
        XCTAssertTrue(model.isEnabled(day, range: throughMidnight))
        XCTAssertFalse(model.isEnabled(laterDay, range: throughMidnight))
        XCTAssertEqual(
            model.selectedDate(for: day, preserving: calendarUTCDate(2024, 6, 1, hour: 23), range: throughMidnight),
            midnight
        )
    }

    func testExclusiveUpperRangeDoesNotAdmitFollowingMidnight() async throws {
        let midnight = calendarUTCDate(2024, 1, 1)
        let range = DatePickerRange(upperBound: midnight, includesUpperBound: false)
        let december = try calendarModel(containing: calendarUTCDate(2023, 12, 31))
        let january = try calendarModel(containing: midnight)
        let previousDay = try calendarDay(31, in: december)
        let followingDay = try calendarDay(1, in: january)

        XCTAssertTrue(december.isEnabled(previousDay, range: range))
        XCTAssertFalse(january.isEnabled(followingDay, range: range))
        XCTAssertNil(january.selectedDate(for: followingDay, preserving: midnight, range: range))
        XCTAssertNil(december.adjacentMonth(direction: 1, range: range))

        // The reference-date and Unix-epoch coordinate systems have different ULPs.
        for year in [1970, 2001] {
            let model = try calendarModel(containing: calendarUTCDate(year, 1, 1))
            let day = try calendarDay(1, in: model)
            let upperBound = calendarUTCDate(year, 1, 1, hour: 12, fraction: 0.125)
            let previousInstant = Date(
                timeIntervalSinceReferenceDate: upperBound.timeIntervalSinceReferenceDate.nextDown
            )
            let tinyRange = DatePickerRange(
                lowerBound: previousInstant,
                upperBound: upperBound,
                includesUpperBound: false
            )
            let candidate = try XCTUnwrap(
                model.selectedDate(
                    for: day,
                    preserving: calendarUTCDate(year, 1, 3, hour: 18),
                    range: tinyRange
                )
            )

            XCTAssertTrue(model.isEnabled(day, range: tinyRange))
            XCTAssertEqual(candidate, previousInstant)
            XCTAssertEqual(candidate.timeIntervalSinceReferenceDate.nextUp, upperBound.timeIntervalSinceReferenceDate)
            XCTAssertLessThan(candidate, upperBound)
            XCTAssertTrue(tinyRange.contains(candidate))

            let emptyRange = DatePickerRange(
                lowerBound: upperBound,
                upperBound: upperBound,
                includesUpperBound: false
            )
            XCTAssertFalse(model.isEnabled(day, range: emptyRange))
            XCTAssertNil(model.selectedDate(for: day, preserving: upperBound, range: emptyRange))
        }
    }

    func testOutOfRangeSelectionDoesNotPreventBrowsingTowardAllowedMonth() async throws {
        let range = DatePickerRange(
            lowerBound: calendarUTCDate(2024, 4, 10, hour: 12),
            upperBound: calendarUTCDate(2024, 6, 20, hour: 12)
        )

        for month in [1, 2, 3] {
            let model = try calendarModel(containing: calendarUTCDate(2024, month, 15))
            XCTAssertNil(model.adjacentMonth(direction: -1, range: range))
            XCTAssertEqual(model.adjacentMonth(direction: 1, range: range), calendarUTCDate(2024, month + 1, 1))
        }
        for month in [9, 8, 7] {
            let model = try calendarModel(containing: calendarUTCDate(2024, month, 15))
            XCTAssertNil(model.adjacentMonth(direction: 1, range: range))
            XCTAssertEqual(model.adjacentMonth(direction: -1, range: range), calendarUTCDate(2024, month - 1, 1))
        }

        let lowerMonth = try calendarModel(containing: calendarUTCDate(2024, 4, 1))
        let upperMonth = try calendarModel(containing: calendarUTCDate(2024, 6, 30))
        XCTAssertNil(lowerMonth.adjacentMonth(direction: -1, range: range))
        XCTAssertEqual(lowerMonth.adjacentMonth(direction: 1, range: range), calendarUTCDate(2024, 5, 1))
        XCTAssertNil(upperMonth.adjacentMonth(direction: 1, range: range))
        XCTAssertEqual(upperMonth.adjacentMonth(direction: -1, range: range), calendarUTCDate(2024, 5, 1))
    }

    func testInvalidDatesFailClosedWithoutCalendarLoop() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = calendarModelUTC
        calendar.firstWeekday = 1
        let validModel = try calendarModel(containing: calendarUTCDate(2024, 1, 15))
        let validDay = try calendarDay(15, in: validModel)
        let invalidIntervals = [
            Double.nan,
            Double.infinity,
            -Double.infinity,
            Double.greatestFiniteMagnitude,
            -Double.greatestFiniteMagnitude,
        ]

        for interval in invalidIntervals {
            let invalidDate = Date(timeIntervalSinceReferenceDate: interval)
            XCTAssertNil(
                DatePickerCalendarModel(
                    containing: invalidDate,
                    calendar: calendar,
                    timeZone: calendarModelUTC,
                    locale: Locale(identifier: "en_US_POSIX")
                ),
                "Invalid reference interval \(interval)"
            )
            XCTAssertNil(
                validModel.selectedDate(for: validDay, preserving: invalidDate, range: .unbounded),
                "Invalid preserved reference interval \(interval)"
            )
        }
    }
}

private let calendarModelUTC = TimeZone(secondsFromGMT: 0)!

private func calendarUTCDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0,
    second: Int = 0,
    fraction: TimeInterval = 0
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = calendarModelUTC
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    return calendar.date(from: components)!.addingTimeInterval(fraction)
}

private func calendarModel(
    containing date: Date,
    identifier: Calendar.Identifier = .gregorian,
    firstWeekday: Int = 1,
    timeZone: TimeZone = calendarModelUTC,
    locale: Locale = Locale(identifier: "en_US_POSIX"),
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> DatePickerCalendarModel {
    var calendar = Calendar(identifier: identifier)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    calendar.firstWeekday = firstWeekday
    return try XCTUnwrap(
        DatePickerCalendarModel(containing: date, calendar: calendar, timeZone: timeZone, locale: locale),
        file: file,
        line: line
    )
}

private func calendarDay(
    _ number: Int,
    in model: DatePickerCalendarModel,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> DatePickerCalendarModel.Day {
    try XCTUnwrap(model.cells.compactMap { $0 }.first { $0.number == number }, file: file, line: line)
}
