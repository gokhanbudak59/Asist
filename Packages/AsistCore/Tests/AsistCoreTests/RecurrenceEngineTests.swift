import Foundation
import XCTest
@testable import AsistCore

/// 04 §3.4.5: month-end, leap year, interval 2, "her 6 ayda bir", roll-over of missed occurrences.
final class RecurrenceEngineTests: XCTestCase {
    let calendar = TestSupport.calendar
    let nine = ClockTime(9, 0)

    func d(_ s: String) -> Date {
        return TestSupport.date(s)
    }

    func f(_ date: Date?) -> String? {
        return date.map { TestSupport.format($0) }
    }

    func next(_ rule: Recurrence, _ time: ClockTime, after: String, anchor: String? = nil) -> String? {
        return f(RecurrenceEngine.nextOccurrence(of: rule, time: time, after: d(after), anchor: anchor.map { d($0) },
                                                 calendar: calendar))
    }

    func list(_ rule: Recurrence, _ time: ClockTime, after: String, count: Int, anchor: String? = nil) -> [String] {
        return RecurrenceEngine.occurrences(of: rule, time: time, after: d(after), anchor: anchor.map { d($0) },
                                            count: count, calendar: calendar).map { TestSupport.format($0) }
    }

    func testDailyIsStrictlyAfter() {
        let daily = Recurrence(frequency: .daily)
        XCTAssertEqual(next(daily, nine, after: "2026-09-28T09:00"), "2026-09-29T09:00")
        XCTAssertEqual(next(daily, nine, after: "2026-09-28T08:59"), "2026-09-28T09:00")
        XCTAssertEqual(list(daily, nine, after: "2026-09-27T10:30", count: 7).count, 7)
        XCTAssertEqual(list(daily, nine, after: "2026-09-27T10:30", count: 3),
                       ["2026-09-28T09:00", "2026-09-29T09:00", "2026-09-30T09:00"])
    }

    func testDailyIntervalCountsFromAnchor() {
        let everyThird = Recurrence(frequency: .daily, interval: 3)
        XCTAssertEqual(next(everyThird, nine, after: "2026-09-28T10:00", anchor: "2026-09-28T09:00"), "2026-10-01T09:00")
        XCTAssertEqual(next(everyThird, nine, after: "2026-09-27T10:30"), "2026-09-28T09:00")
        XCTAssertEqual(list(everyThird, nine, after: "2026-09-27T10:30", count: 3),
                       ["2026-09-28T09:00", "2026-10-01T09:00", "2026-10-04T09:00"])
    }

    func testWeeklySetAndInterval() {
        let monThu = Recurrence(frequency: .weekly, weekdays: [1, 4])
        XCTAssertEqual(list(monThu, nine, after: "2026-09-27T10:30", count: 3),
                       ["2026-09-28T09:00", "2026-10-01T09:00", "2026-10-05T09:00"])
        let biweekly = Recurrence(frequency: .weekly, interval: 2, weekdays: [5])
        let three = ClockTime(15, 0)
        XCTAssertEqual(list(biweekly, three, after: "2026-09-27T10:30", count: 3),
                       ["2026-10-02T15:00", "2026-10-16T15:00", "2026-10-30T15:00"])
        XCTAssertEqual(next(biweekly, three, after: "2026-10-03T00:00", anchor: "2026-10-02T15:00"), "2026-10-16T15:00")
        // Same weekday later today is allowed (02 §9.3: "her salı 10'da" said on Tuesday 09:15).
        let tuesday = Recurrence(frequency: .weekly, weekdays: [2])
        XCTAssertEqual(next(tuesday, ClockTime(10, 0), after: "2026-09-29T09:15"), "2026-09-29T10:00")
    }

    func testMonthEndClamping() {
        let thirtyFirst = Recurrence(frequency: .monthly, monthDay: 31)
        XCTAssertEqual(next(thirtyFirst, nine, after: "2027-01-31T10:00"), "2027-02-28T09:00")
        XCTAssertEqual(list(thirtyFirst, nine, after: "2027-01-01T00:00", count: 4),
                       ["2027-01-31T09:00", "2027-02-28T09:00", "2027-03-31T09:00", "2027-04-30T09:00"])
        let lastDay = Recurrence(frequency: .monthly, monthDay: -1)
        XCTAssertEqual(list(lastDay, nine, after: "2026-09-27T10:30", count: 3),
                       ["2026-09-30T09:00", "2026-10-31T09:00", "2026-11-30T09:00"])
    }

    func testLeapYear() {
        let feb29 = Recurrence(frequency: .yearly, monthDay: 29, month: 2)
        XCTAssertEqual(next(feb29, nine, after: "2027-01-01T00:00"), "2027-02-28T09:00")
        XCTAssertEqual(next(feb29, nine, after: "2027-03-01T00:00"), "2028-02-29T09:00")
        let lastOfFebruary = Recurrence(frequency: .monthly, monthDay: -1)
        XCTAssertEqual(next(lastOfFebruary, nine, after: "2028-02-01T00:00"), "2028-02-29T09:00")
    }

    /// G12 "her 6 ayda bir": the first occurrence is today + 6 months (anchor = today).
    func testEverySixMonths() {
        let halfYear = Recurrence(frequency: .monthly, interval: 6, monthDay: 27)
        XCTAssertEqual(next(halfYear, nine, after: "2026-09-27T09:00", anchor: "2026-09-27T09:00"), "2027-03-27T09:00")
        XCTAssertEqual(next(halfYear, nine, after: "2027-03-27T09:00", anchor: "2026-09-27T09:00"), "2027-09-27T09:00")
    }

    func testYearly() {
        let march3 = Recurrence(frequency: .yearly, monthDay: 3, month: 3)
        XCTAssertEqual(next(march3, nine, after: "2026-09-27T10:30"), "2027-03-03T09:00")
        let everyTwoYears = Recurrence(frequency: .yearly, interval: 2, monthDay: 3, month: 3)
        XCTAssertEqual(next(everyTwoYears, nine, after: "2027-03-04T00:00", anchor: "2027-03-03T09:00"),
                       "2029-03-03T09:00")
    }

    func testInvalidRules() {
        let noDays = Recurrence(frequency: .weekly)
        XCTAssertNil(next(noDays, nine, after: "2026-09-27T10:30"))
        XCTAssertEqual(list(noDays, nine, after: "2026-09-27T10:30", count: 7), [])
        XCTAssertEqual(list(Recurrence(frequency: .daily), nine, after: "2026-09-27T10:30", count: 0), [])
    }

    func testLatestOccurrenceRollsOverMissedOnes() {
        let daily = Recurrence(frequency: .daily)
        XCTAssertEqual(f(RecurrenceEngine.latestOccurrence(of: daily, time: nine, after: d("2026-09-24T09:00"),
                                                           upTo: d("2026-09-27T10:30"), calendar: calendar)),
                       "2026-09-27T09:00")
        XCTAssertNil(RecurrenceEngine.latestOccurrence(of: daily, time: nine, after: d("2026-09-27T09:00"),
                                                       upTo: d("2026-09-27T10:30"), calendar: calendar))
        XCTAssertNil(RecurrenceEngine.latestOccurrence(of: daily, time: nine, after: d("2026-09-28T09:00"),
                                                       upTo: d("2026-09-27T10:30"), calendar: calendar))
        let everyThird = Recurrence(frequency: .daily, interval: 3)
        XCTAssertEqual(f(RecurrenceEngine.latestOccurrence(of: everyThird, time: nine, after: d("2026-09-24T09:00"),
                                                           upTo: d("2026-09-30T08:00"), calendar: calendar)),
                       "2026-09-27T09:00")
        let tuesday = Recurrence(frequency: .weekly, weekdays: [2])
        XCTAssertEqual(f(RecurrenceEngine.latestOccurrence(of: tuesday, time: ClockTime(10, 0),
                                                           after: d("2026-09-15T10:00"), upTo: d("2026-09-27T10:30"),
                                                           calendar: calendar)), "2026-09-22T10:00")
        let biweekly = Recurrence(frequency: .weekly, interval: 2, weekdays: [5])
        XCTAssertEqual(f(RecurrenceEngine.latestOccurrence(of: biweekly, time: ClockTime(15, 0),
                                                           after: d("2026-10-02T15:00"), upTo: d("2026-10-20T10:00"),
                                                           calendar: calendar)), "2026-10-16T15:00")
        let monthly = Recurrence(frequency: .monthly, monthDay: 15)
        XCTAssertEqual(f(RecurrenceEngine.latestOccurrence(of: monthly, time: nine, after: d("2026-08-15T09:00"),
                                                           upTo: d("2026-09-27T10:30"), calendar: calendar)),
                       "2026-09-15T09:00")
        let yearly = Recurrence(frequency: .yearly, monthDay: 3, month: 3)
        XCTAssertEqual(f(RecurrenceEngine.latestOccurrence(of: yearly, time: nine, after: d("2025-03-03T09:00"),
                                                           upTo: d("2026-09-27T10:30"), calendar: calendar)),
                       "2026-03-03T09:00")
    }

    /// The parser's first occurrence uses the same engine (04 §3.4.5).
    func testParserUsesTheEngine() {
        let parser = TurkishParser(settings: ParserSettings(), calendar: calendar)
        let result = parser.parse("her 6 ayda bir kompresör filtrelerini değiştir", now: d("2026-09-27T10:30"))
        XCTAssertEqual(result.item?.recurrence, Recurrence(frequency: .monthly, interval: 6, monthDay: 27))
        XCTAssertEqual(f(result.item?.dueDate), "2027-03-27T09:00")
    }
}
