import Foundation
import XCTest
@testable import AsistCore

/// Stale notification actions (recurring occurrence already completed, end-of-day of an earlier day) and the
/// near-due guard of the diff-apply.
final class NotificationStalenessTests: XCTestCase {
    let calendar = TestSupport.calendar

    func d(_ s: String) -> Date {
        return TestSupport.date(s)
    }

    /// Daily 09:00 item; `doneAt` appends an `.occurrenceDone` entry (as DataStore.markDone does).
    func dailyItem(due: String, doneAt: [String] = []) -> Item {
        var item = Item(kind: .reminder, title: "İlaç", dueDate: d(due), hasTime: true,
                        recurrence: Recurrence(frequency: .daily), createdAt: d("2026-09-20T08:00"))
        item.appendHistory(.created, at: d("2026-09-20T08:00"))
        for s in doneAt {
            item.appendHistory(.occurrenceDone, at: d(s))
        }
        return item
    }

    func testCompletedInAppMakesOlderNagStale() {
        // Nag delivered 09:10, completed in the app 09:20 → dueDate moved to tomorrow; the 09:10 nag is stale.
        let item = dailyItem(due: "2026-09-29T09:00", doneAt: ["2026-09-28T09:20"])
        XCTAssertEqual(NotificationStaleness.lastOccurrenceDone(of: item), d("2026-09-28T09:20"))
        XCTAssertTrue(NotificationStaleness.isCompletedOccurrence(item, deliveredAt: d("2026-09-28T09:10"),
                                                                  now: d("2026-09-28T19:00")))
        // Tomorrow's own notification (delivered after the completion) is not stale.
        XCTAssertFalse(NotificationStaleness.isCompletedOccurrence(item, deliveredAt: d("2026-09-29T09:00"),
                                                                   now: d("2026-09-29T09:05")))
    }

    func testMissedOccurrenceIsNotStale() {
        // Last completion two days ago; today's carrier-delivered occurrence (rolled over) is a real action.
        var item = dailyItem(due: "2026-09-28T09:00", doneAt: ["2026-09-26T09:05"])
        item.appendHistory(.occurrenceMissed, at: d("2026-09-28T10:00"))
        XCTAssertFalse(NotificationStaleness.isCompletedOccurrence(item, deliveredAt: d("2026-09-28T09:00"),
                                                                   now: d("2026-09-28T10:00")))
    }

    func testNonRecurringAndNeverCompletedAreNeverStale() {
        let neverDone = dailyItem(due: "2026-09-28T09:00")
        XCTAssertNil(NotificationStaleness.lastOccurrenceDone(of: neverDone))
        XCTAssertFalse(NotificationStaleness.isCompletedOccurrence(neverDone, deliveredAt: d("2026-09-28T09:00"),
                                                                   now: d("2026-09-28T09:30")))
        var single = Item(kind: .task, title: "Rapor", dueDate: d("2026-09-28T09:00"), hasTime: true,
                          createdAt: d("2026-09-20T08:00"))
        single.appendHistory(.occurrenceDone, at: d("2026-09-28T09:20"))
        XCTAssertNil(NotificationStaleness.lastOccurrenceDone(of: single))
        XCTAssertFalse(NotificationStaleness.isCompletedOccurrence(single, deliveredAt: d("2026-09-28T09:10"),
                                                                   now: d("2026-09-28T19:00")))
    }

    func testFutureDatedCompletionIsIgnored() {
        // A completion stamped in the future (clock was wrong) must not make every notification stale.
        let item = dailyItem(due: "2027-01-02T09:00", doneAt: ["2027-01-01T09:20"])
        XCTAssertFalse(NotificationStaleness.isCompletedOccurrence(item, deliveredAt: d("2026-09-28T09:10"),
                                                                   now: d("2026-09-28T19:00")))
    }

    func testNewestCompletionWins() {
        let item = dailyItem(due: "2026-09-30T09:00", doneAt: ["2026-09-28T09:20", "2026-09-29T09:15"])
        XCTAssertEqual(NotificationStaleness.lastOccurrenceDone(of: item), d("2026-09-29T09:15"))
        XCTAssertTrue(NotificationStaleness.isDeliveredBeforeCompletion(deliveredAt: d("2026-09-29T09:10"),
                                                                        lastOccurrenceDone: d("2026-09-29T09:15")))
        XCTAssertFalse(NotificationStaleness.isDeliveredBeforeCompletion(deliveredAt: d("2026-09-30T09:00"),
                                                                         lastOccurrenceDone: d("2026-09-29T09:15")))
        XCTAssertFalse(NotificationStaleness.isDeliveredBeforeCompletion(deliveredAt: d("2026-09-29T09:10"),
                                                                         lastOccurrenceDone: nil))
    }

    func testEndOfDayActionOnlyOnItsOwnDay() {
        let delivered = d("2026-09-29T17:45")
        XCTAssertFalse(NotificationStaleness.isStaleEndOfDay(deliveredAt: delivered, now: d("2026-09-29T23:59"),
                                                             calendar: calendar))
        XCTAssertTrue(NotificationStaleness.isStaleEndOfDay(deliveredAt: delivered, now: d("2026-09-30T00:30"),
                                                            calendar: calendar))
        XCTAssertTrue(NotificationStaleness.isStaleEndOfDay(deliveredAt: delivered, now: d("2026-09-30T08:00"),
                                                            calendar: calendar))
    }

    func testNearDueGuard() {
        let now = d("2026-09-28T13:59")
        let inOneMinute = d("2026-09-28T14:00")
        XCTAssertTrue(NotificationStaleness.isNearDue(nextFire: inOneMinute, repeats: false, now: now))
        XCTAssertFalse(NotificationStaleness.isNearDue(nextFire: inOneMinute, repeats: true, now: now))
        XCTAssertFalse(NotificationStaleness.isNearDue(nextFire: nil, repeats: false, now: now))
        XCTAssertFalse(NotificationStaleness.isNearDue(nextFire: d("2026-09-28T14:01"), repeats: false, now: now))
    }

    func testNearDueProtectionFollowsItemState() {
        let now = d("2026-09-28T13:59")
        let open = dailyItem(due: "2026-09-28T14:00", doneAt: ["2026-09-27T14:05"])
        XCTAssertTrue(NotificationStaleness.protectsNearDue(open, now: now))

        var done = Item(kind: .task, title: "Toplantı notu", dueDate: d("2026-09-28T14:00"), hasTime: true,
                        createdAt: d("2026-09-20T08:00"))
        done.status = .done
        XCTAssertFalse(NotificationStaleness.protectsNearDue(done, now: now))

        let note = Item(kind: .note, title: "Not", createdAt: d("2026-09-20T08:00"))
        XCTAssertFalse(NotificationStaleness.protectsNearDue(note, now: now))

        // Occurrence completed 30 s ago: the completion re-planned the item on purpose → no protection.
        let justDone = dailyItem(due: "2026-09-29T14:00", doneAt: ["2026-09-28T13:59"])
        XCTAssertFalse(NotificationStaleness.protectsNearDue(justDone, now: now.addingTimeInterval(30)))
    }
}
