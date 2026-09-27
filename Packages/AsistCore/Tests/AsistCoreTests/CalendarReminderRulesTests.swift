import Foundation
import XCTest
@testable import AsistCore

/// 07 §10.2 / §13: rules behind the Bugün "TAKVİM" section and "Öncesinde hatırlat".
final class CalendarReminderRulesTests: XCTestCase {
    let calendar = TestSupport.calendar

    func d(_ s: String) -> Date {
        return TestSupport.date(s)
    }

    // MARK: - Keys and tags

    func testEventKeySeparatesOccurrencesOfRecurringEvent() {
        let monday = CalendarReminderRules.eventKey(identifier: "ABC:123", start: d("2026-09-28T10:00"),
                                                    calendar: calendar)
        let nextMonday = CalendarReminderRules.eventKey(identifier: "ABC:123", start: d("2026-10-05T10:00"),
                                                        calendar: calendar)
        XCTAssertEqual(monday, "ABC:123@202609281000")
        XCTAssertNotEqual(monday, nextMonday)
        XCTAssertNotEqual(CalendarReminderRules.tag(forEventKey: monday),
                          CalendarReminderRules.tag(forEventKey: nextMonday))
    }

    func testTagIsStable() {
        let key = "ABC:123@202609281000"
        let tag = CalendarReminderRules.tag(forEventKey: key)
        XCTAssertEqual(tag, CalendarReminderRules.tag(forEventKey: key))
        XCTAssertEqual(tag, "takvim:" + StableHash.fnv1a64(key))
        XCTAssertTrue(tag.hasPrefix(CalendarReminderRules.tagPrefix))
    }

    // MARK: - canRemind

    func testCanRemind() {
        let now = d("2026-09-28T09:00")
        XCTAssertFalse(CalendarReminderRules.canRemind(start: d("2026-09-28T10:00"), isAllDay: true, now: now))
        XCTAssertFalse(CalendarReminderRules.canRemind(start: now.addingTimeInterval(30), isAllDay: false, now: now))
        XCTAssertFalse(CalendarReminderRules.canRemind(start: now.addingTimeInterval(60), isAllDay: false, now: now))
        XCTAssertTrue(CalendarReminderRules.canRemind(start: now.addingTimeInterval(120), isAllDay: false, now: now))
        XCTAssertFalse(CalendarReminderRules.canRemind(start: d("2026-09-28T08:30"), isAllDay: false, now: now))
    }

    // MARK: - makeItem

    func testMakeItemCreatesEventItemWithPreAlert() {
        let now = d("2026-09-28T09:00")
        let key = "ABC:123@202609281000"
        let item = CalendarReminderRules.makeItem(title: "  Proje toplantısı\n", start: d("2026-09-28T10:00"),
                                                  end: d("2026-09-28T11:00"), location: "Toplantı Odası 3",
                                                  eventKey: key, leadMinutes: 15, now: now, calendar: calendar)
        XCTAssertEqual(item.kind, .reminder)
        XCTAssertEqual(item.title, "Proje toplantısı")
        XCTAssertEqual(item.notes, "Takvim: 10:00–11:00 · Toplantı Odası 3")
        XCTAssertEqual(item.dueDate, d("2026-09-28T10:00"))
        XCTAssertTrue(item.hasTime)
        XCTAssertTrue(item.isEvent)
        XCTAssertEqual(item.leadTimesMinutes, [15])
        XCTAssertEqual(item.tags, [CalendarReminderRules.tag(forEventKey: key)])
        XCTAssertEqual(item.source, .calendar)
        XCTAssertEqual(item.status, .open)
        XCTAssertEqual(item.priority, .normal)
        XCTAssertNil(item.recurrence)
        XCTAssertEqual(item.createdAt, now)
        XCTAssertEqual(item.updatedAt, now)
        XCTAssertEqual(item.history.count, 1)
        XCTAssertEqual(item.history.first?.event, .created)
        XCTAssertEqual(item.history.first?.date, now)
        // D31: an event item is never "geciken" and closes itself two hours after the start.
        XCTAssertNil(item.overdueStart(calendar: calendar))
        XCTAssertEqual(item.eventEnd, d("2026-09-28T12:00"))
        XCTAssertEqual(item.profileKind(settings: AppSettings()), .etkinlik)
    }

    func testMakeItemWithoutLocationTitleOrLead() {
        let now = d("2026-09-28T09:00")
        let item = CalendarReminderRules.makeItem(title: "   ", start: d("2026-09-28T14:30"),
                                                  end: d("2026-09-28T15:00"), location: "  ",
                                                  eventKey: "X@1", leadMinutes: 0, now: now, calendar: calendar)
        XCTAssertEqual(item.title, "Toplantı")
        XCTAssertEqual(item.notes, "Takvim: 14:30–15:00")
        XCTAssertEqual(item.leadTimesMinutes, [])
        let noLocation = CalendarReminderRules.makeItem(title: "Ziyaret", start: d("2026-09-28T14:30"),
                                                        end: d("2026-09-28T15:00"), location: nil,
                                                        eventKey: "X@1", leadMinutes: 60, now: now,
                                                        calendar: calendar)
        XCTAssertEqual(noLocation.notes, "Takvim: 14:30–15:00")
        XCTAssertEqual(noLocation.leadTimesMinutes, [60])
    }

    func testMakeItemFloorsStartToWholeMinute() {
        let start = d("2026-09-28T10:00").addingTimeInterval(42)
        let item = CalendarReminderRules.makeItem(title: "FAT", start: start, end: start.addingTimeInterval(3600),
                                                  location: nil, eventKey: "K", leadMinutes: 10,
                                                  now: d("2026-09-28T09:00"), calendar: calendar)
        XCTAssertEqual(item.dueDate, d("2026-09-28T10:00"))
    }

    // MARK: - hasReminder

    func testHasReminderIgnoresDeletedAndDone() {
        let key = "ABC:123@202609281000"
        let now = d("2026-09-28T09:00")
        let reminder = CalendarReminderRules.makeItem(title: "Toplantı", start: d("2026-09-28T10:00"),
                                                      end: d("2026-09-28T11:00"), location: nil, eventKey: key,
                                                      leadMinutes: 15, now: now, calendar: calendar)
        XCTAssertTrue(CalendarReminderRules.hasReminder(items: [reminder], eventKey: key))
        XCTAssertFalse(CalendarReminderRules.hasReminder(items: [reminder], eventKey: "ABC:123@202610051000"))
        XCTAssertFalse(CalendarReminderRules.hasReminder(items: [], eventKey: key))

        var done = reminder
        done.status = .done
        XCTAssertFalse(CalendarReminderRules.hasReminder(items: [done], eventKey: key))
        var deleted = reminder
        deleted.status = .deleted
        deleted.deletedAt = now
        XCTAssertFalse(CalendarReminderRules.hasReminder(items: [deleted], eventKey: key))
        let unrelated = Item(kind: .task, title: "Rapor", tags: ["takvim:0"], createdAt: now)
        XCTAssertFalse(CalendarReminderRules.hasReminder(items: [unrelated, done], eventKey: key))
        XCTAssertTrue(CalendarReminderRules.hasReminder(items: [unrelated, done, reminder], eventKey: key))
    }

    // MARK: - Ranges and alert time

    func testTimeRange() {
        XCTAssertEqual(CalendarReminderRules.timeRange(start: d("2026-09-28T10:00"), end: d("2026-09-28T11:00"),
                                                       isAllDay: false, calendar: calendar), "10:00–11:00")
        XCTAssertEqual(CalendarReminderRules.timeRange(start: d("2026-09-28T22:00"), end: d("2026-09-29T02:00"),
                                                       isAllDay: false, calendar: calendar), "22:00–…")
        XCTAssertEqual(CalendarReminderRules.timeRange(start: d("2026-09-28T23:00"), end: d("2026-09-29T00:00"),
                                                       isAllDay: false, calendar: calendar), "23:00–00:00")
        XCTAssertEqual(CalendarReminderRules.timeRange(start: d("2026-09-28T09:30"), end: d("2026-09-28T09:30"),
                                                       isAllDay: false, calendar: calendar), "09:30")
        XCTAssertEqual(CalendarReminderRules.timeRange(start: d("2026-09-28T00:00"), end: d("2026-09-29T00:00"),
                                                       isAllDay: true, calendar: calendar), "Tüm gün")
    }

    func testDisplayRangeForEventsStartedEarlier() {
        let dayStart = d("2026-09-28T00:00")
        XCTAssertEqual(CalendarReminderRules.displayRange(start: d("2026-09-27T20:00"), end: d("2026-09-28T09:00"),
                                                          isAllDay: false, dayStart: dayStart, calendar: calendar),
                       "…–09:00")
        XCTAssertEqual(CalendarReminderRules.displayRange(start: d("2026-09-27T09:00"), end: d("2026-09-29T18:00"),
                                                          isAllDay: false, dayStart: dayStart, calendar: calendar),
                       "Tüm gün")
        XCTAssertEqual(CalendarReminderRules.displayRange(start: d("2026-09-28T10:00"), end: d("2026-09-28T11:30"),
                                                          isAllDay: false, dayStart: dayStart, calendar: calendar),
                       "10:00–11:30")
        XCTAssertEqual(CalendarReminderRules.displayRange(start: d("2026-09-27T00:00"), end: d("2026-09-29T00:00"),
                                                          isAllDay: true, dayStart: dayStart, calendar: calendar),
                       "Tüm gün")
    }

    func testAlertTime() {
        let now = d("2026-09-28T09:00")
        // Pre-alert still ahead → start − lead.
        XCTAssertEqual(CalendarReminderRules.alertTime(start: d("2026-09-28T10:00"), leadMinutes: 15, now: now),
                       d("2026-09-28T09:45"))
        // Pre-alert already past → the start itself.
        XCTAssertEqual(CalendarReminderRules.alertTime(start: d("2026-09-28T09:10"), leadMinutes: 15, now: now),
                       d("2026-09-28T09:10"))
        // Pre-alert within the next minute → the start.
        XCTAssertEqual(CalendarReminderRules.alertTime(start: d("2026-09-28T09:31"), leadMinutes: 30, now: now),
                       d("2026-09-28T09:31"))
        XCTAssertEqual(CalendarReminderRules.alertTime(start: d("2026-09-28T10:00"), leadMinutes: 0, now: now),
                       d("2026-09-28T10:00"))
        XCTAssertEqual(CalendarReminderRules.alertTime(start: d("2026-09-28T11:00"), leadMinutes: 60, now: now),
                       d("2026-09-28T10:00"))
    }
}
