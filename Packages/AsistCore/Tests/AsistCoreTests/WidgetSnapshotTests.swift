import Foundation
import XCTest
@testable import AsistCore

/// 07 §5.3–5.4, §13: widget snapshot selection, counters, time-driven counters, timeline instants, JSON round trip.
/// Reference instant: Sun 2026-09-27 10:30 (Europe/Istanbul).
final class WidgetSnapshotTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let now = TestSupport.date("2026-09-27T10:30")
    private let settings = AppSettings()

    private func makeItem(_ kind: ItemKind, _ title: String, due: String? = nil, hasTime: Bool = true,
                          priority: Priority = .normal, isEvent: Bool = false,
                          created: String = "2026-09-20T09:00") -> Item {
        Item(kind: kind, title: title, priority: priority, dueDate: due.map { TestSupport.date($0) },
             hasTime: hasTime, isEvent: isEvent, createdAt: TestSupport.date(created))
    }

    private struct Fixture {
        var overdueReminder: Item        // 26 Eyl 15:00, normal
        var overdueCritical: Item        // bugün 09:00, kritik
        var overdueUntimedTask: Item     // 25 Eyl, saatsiz görev → 26 Eyl 00:00'da gecikti
        var overdueFollowUp: Item        // 24 Eyl takip → 25 Eyl 00:00'da gecikti
        var todayTimed: Item             // bugün 14:00
        var todayUntimed: Item           // bugün, saatsiz görev
        var todayFollowUp: Item          // bugün takip
        var tomorrow: Item               // 28 Eyl 09:00
        var event: Item                  // 29 Eyl 15:00 etkinlik
        var note: Item
        var undated: Item
        var beyondHorizon: Item          // 5 Eki
        var done: Item
        var deleted: Item

        var all: [Item] {
            [overdueReminder, overdueCritical, overdueUntimedTask, overdueFollowUp, todayTimed, todayUntimed,
             todayFollowUp, tomorrow, event, note, undated, beyondHorizon, done, deleted]
        }
    }

    private func fixture() -> Fixture {
        var done = makeItem(.reminder, "Tamamlanan iş", due: "2026-09-27T12:00")
        done.status = .done
        done.completedAt = TestSupport.date("2026-09-27T08:00")
        var deleted = makeItem(.reminder, "Silinen iş", due: "2026-09-27T13:00")
        deleted.status = .deleted
        deleted.deletedAt = TestSupport.date("2026-09-27T08:00")
        return Fixture(
            overdueReminder: makeItem(.reminder, "Ahmet'i ara", due: "2026-09-26T15:00"),
            overdueCritical: makeItem(.reminder, "Pano ısınması", due: "2026-09-27T09:00", priority: .critical),
            overdueUntimedTask: makeItem(.task, "Eski iş", due: "2026-09-25T09:00", hasTime: false),
            overdueFollowUp: makeItem(.waiting, "Teklif dönüşü", due: "2026-09-24T10:00", hasTime: false),
            todayTimed: makeItem(.reminder, "ABB toplantısı", due: "2026-09-27T14:00"),
            todayUntimed: makeItem(.task, "Sipariş formu", due: "2026-09-27T09:00", hasTime: false),
            todayFollowUp: makeItem(.waiting, "I/O listesi", due: "2026-09-27T10:00", hasTime: false),
            tomorrow: makeItem(.reminder, "Haftalık rapor", due: "2026-09-28T09:00"),
            event: makeItem(.reminder, "FAT toplantısı", due: "2026-09-29T15:00", isEvent: true),
            note: makeItem(.note, "Işık perdesi notu", due: "2026-09-27T16:00"),
            undated: makeItem(.task, "Kalibrasyon"),
            beyondHorizon: makeItem(.reminder, "SAT hazırlığı", due: "2026-10-05T10:00"),
            done: done,
            deleted: deleted)
    }

    private func build(_ items: [Item], settings: AppSettings? = nil) -> WidgetSnapshot {
        WidgetSnapshotBuilder.build(items: items, settings: settings ?? self.settings, now: now, calendar: calendar)
    }

    // MARK: Builder

    func testNotesDoneAndDeletedAreExcluded() {
        let f = fixture()
        let snapshot = build(f.all)
        let ids = Set(snapshot.entries.map { $0.id })
        XCTAssertFalse(ids.contains(f.note.id))
        XCTAssertFalse(ids.contains(f.done.id))
        XCTAssertFalse(ids.contains(f.deleted.id))
        XCTAssertFalse(ids.contains(f.undated.id), "zamanı belirsiz kayıt listede yer almaz")
        XCTAssertFalse(ids.contains(f.beyondHorizon.id), "7 günden sonrası listede yer almaz")
    }

    func testOrderOverdueFirstByPriorityThenOldestThenUpcomingByAnchor() {
        let f = fixture()
        let snapshot = build(f.all)
        XCTAssertEqual(snapshot.entries.map { $0.id }, [
            f.overdueCritical.id,       // kritik önce
            f.overdueFollowUp.id,       // 25 Eyl 00:00
            f.overdueUntimedTask.id,    // 26 Eyl 00:00
            f.overdueReminder.id,       // 26 Eyl 15:00
            f.todayUntimed.id,          // bugün 09:00
            f.todayFollowUp.id,         // bugün 10:00
            f.todayTimed.id,            // bugün 14:00
            f.tomorrow.id,              // 28 Eyl
            f.event.id                  // 29 Eyl
        ])
        let event = snapshot.entries.last
        XCTAssertEqual(event?.isEvent, true)
        XCTAssertNil(event?.overdueAt, "etkinlik hiçbir zaman geciken olmaz")
        let untimed = snapshot.entries.first { $0.id == f.overdueUntimedTask.id }
        XCTAssertEqual(untimed?.overdueAt, TestSupport.date("2026-09-26T00:00"))
        XCTAssertEqual(untimed?.anchor, TestSupport.date("2026-09-25T09:00"))
        XCTAssertEqual(untimed?.hasTime, false)
        XCTAssertEqual(untimed?.kind, .task)
    }

    func testCounts() {
        let f = fixture()
        let snapshot = build(f.all)
        XCTAssertEqual(snapshot.overdueCount, 4)
        XCTAssertEqual(snapshot.todayCount, 3)          // 14:00, saatsiz görev, bugünkü takip
        XCTAssertEqual(snapshot.followUpCount, 2)       // iki açık takip
        XCTAssertEqual(snapshot.generatedAt, now)
        XCTAssertEqual(snapshot.version, WidgetSnapshot.currentVersion)
    }

    func testHorizonIsSevenCalendarDays() {
        let inside = makeItem(.reminder, "Son gün", due: "2026-10-03T23:59")
        let outside = makeItem(.reminder, "Ufuk dışı", due: "2026-10-04T00:00")
        let snapshot = build([outside, inside])
        XCTAssertEqual(snapshot.entries.map { $0.id }, [inside.id])
    }

    func testEntriesAreCappedAtTwelve() {
        var items: [Item] = []
        for index in 0..<15 {
            let minute = AsistCalendar.pad(index, 2)
            items.append(makeItem(.reminder, "İş \(index)", due: "2026-10-01T09:" + minute))
        }
        let snapshot = build(items.reversed())
        XCTAssertEqual(snapshot.entries.count, WidgetSnapshotBuilder.maxEntries)
        XCTAssertEqual(snapshot.entries.first?.title, "İş 0")
        XCTAssertEqual(snapshot.entries.last?.title, "İş 11")
        XCTAssertEqual(snapshot.overdueCount, 0)
        XCTAssertEqual(snapshot.todayCount, 0)
    }

    func testOverdueAreKeptBeforeUpcomingWhenCapped() {
        var items: [Item] = []
        for index in 0..<14 {
            items.append(makeItem(.reminder, "Gelecek \(index)", due: "2026-09-28T1" + String(index % 10) + ":00"))
        }
        let late = makeItem(.reminder, "Geciken", due: "2026-09-27T08:00")
        items.append(late)
        let snapshot = build(items)
        XCTAssertEqual(snapshot.entries.count, 12)
        XCTAssertEqual(snapshot.entries.first?.id, late.id)
        XCTAssertEqual(snapshot.overdueCount, 1)
    }

    func testTieBreakByCreationThenID() {
        let older = makeItem(.reminder, "Eski", due: "2026-09-28T09:00", created: "2026-09-10T09:00")
        let newer = makeItem(.reminder, "Yeni", due: "2026-09-28T09:00", created: "2026-09-12T09:00")
        let important = makeItem(.reminder, "Önemli", due: "2026-09-28T09:00", priority: .high,
                                 created: "2026-09-15T09:00")
        let snapshot = build([newer, older, important])
        XCTAssertEqual(snapshot.entries.map { $0.id }, [important.id, older.id, newer.id])
    }

    func testTitlesAreTruncatedAndNeverEmpty() {
        let long = String(repeating: "Pano montaj kontrolü ", count: 8)       // 168 karakter
        let items = [
            makeItem(.reminder, long, due: "2026-09-28T09:00"),
            makeItem(.reminder, "   ", due: "2026-09-28T10:00"),
            makeItem(.reminder, "Birinci satır\nİkinci satır", due: "2026-09-28T11:00")
        ]
        let snapshot = build(items)
        XCTAssertEqual(snapshot.entries.count, 3)
        let first = snapshot.entries[0].title
        XCTAssertLessThanOrEqual(first.count, WidgetSnapshotBuilder.maxTitleLength)
        XCTAssertTrue(first.hasSuffix("…"))
        XCTAssertTrue(first.hasPrefix("Pano montaj kontrolü"))
        XCTAssertEqual(snapshot.entries[1].title, "Başlıksız")
        XCTAssertEqual(snapshot.entries[2].title, "Birinci satır İkinci satır")
        XCTAssertEqual(WidgetSnapshotBuilder.displayTitle(""), "Başlıksız")
        XCTAssertEqual(WidgetSnapshotBuilder.displayTitle("  Teklif  "), "Teklif")
    }

    func testHideTitlesMirrorsLockScreenSetting() {
        var hidden = AppSettings()
        hidden.lockScreenShowsContent = false
        XCTAssertTrue(build([], settings: hidden).hideTitlesWhenLocked)
        XCTAssertFalse(build([], settings: AppSettings()).hideTitlesWhenLocked)
    }

    func testEmptyInput() {
        let snapshot = build([])
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertEqual(snapshot.overdueCount, 0)
        XCTAssertEqual(snapshot.todayCount, 0)
        XCTAssertEqual(snapshot.followUpCount, 0)
    }

    func testSnoozeIsTheAnchor() {
        var item = makeItem(.reminder, "Ertelenen", due: "2026-09-27T09:00")
        item.snoozedUntil = TestSupport.date("2026-09-27T16:00")
        let snapshot = build([item])
        XCTAssertEqual(snapshot.overdueCount, 0)
        XCTAssertEqual(snapshot.todayCount, 1)
        XCTAssertEqual(snapshot.entries.first?.anchor, TestSupport.date("2026-09-27T16:00"))
        XCTAssertEqual(snapshot.entries.first?.overdueAt, TestSupport.date("2026-09-27T16:00"))
    }

    // MARK: Time-driven counters

    func testOverdueCountGrowsAsEntriesBecomeOverdue() {
        let snapshot = build(fixture().all)
        XCTAssertEqual(snapshot.overdueCount(at: TestSupport.date("2026-09-27T13:59")), 4)
        XCTAssertEqual(snapshot.overdueCount(at: TestSupport.date("2026-09-27T14:00")), 5)
        XCTAssertEqual(snapshot.overdueCount(at: TestSupport.date("2026-09-28T00:00")), 7)
        XCTAssertEqual(snapshot.overdueCount(at: TestSupport.date("2026-09-28T09:00")), 8)
        XCTAssertEqual(snapshot.overdueCount(at: TestSupport.date("2026-10-01T09:00")), 8, "etkinlik sayılmaz")
    }

    func testTodayCountSameDayAndNextDay() {
        let snapshot = build(fixture().all)
        XCTAssertEqual(snapshot.todayCount(at: TestSupport.date("2026-09-27T13:00"), calendar: calendar), 3)
        XCTAssertEqual(snapshot.todayCount(at: TestSupport.date("2026-09-27T14:00"), calendar: calendar), 2)
        XCTAssertEqual(snapshot.todayCount(at: TestSupport.date("2026-09-27T23:59"), calendar: calendar), 2)
        XCTAssertEqual(snapshot.todayCount(at: TestSupport.date("2026-09-28T08:00"), calendar: calendar), 1)
        XCTAssertEqual(snapshot.todayCount(at: TestSupport.date("2026-09-28T09:30"), calendar: calendar), 0)
        XCTAssertEqual(snapshot.todayCount(at: TestSupport.date("2026-09-29T08:00"), calendar: calendar), 1,
                       "etkinlik o gün bugün sayılır")
    }

    func testIsOverdueUsesOverdueAt() {
        let snapshot = build(fixture().all)
        let meeting = snapshot.entries.first { $0.title == "ABB toplantısı" }
        XCTAssertNotNil(meeting)
        if let abb = meeting {
            XCTAssertFalse(snapshot.isOverdue(abb, at: TestSupport.date("2026-09-27T13:59")))
            XCTAssertTrue(snapshot.isOverdue(abb, at: TestSupport.date("2026-09-27T14:00")))
        }
    }

    // MARK: Ended events

    private func eventFixture() -> (ended: Item, running: Item, later: Item, tomorrowEvent: Item) {
        (ended: makeItem(.reminder, "Sabah toplantısı", due: "2026-09-27T08:00", isEvent: true),    // bitti 10:00
         running: makeItem(.reminder, "Proje toplantısı", due: "2026-09-27T09:00", isEvent: true),  // biter 11:00
         later: makeItem(.reminder, "Teklifi gönder", due: "2026-09-27T14:00"),
         tomorrowEvent: makeItem(.reminder, "Saha ziyareti", due: "2026-09-28T09:00", isEvent: true))
    }

    func testEndedEventIsExcludedFromEntriesAndTodayCount() {
        let f = eventFixture()
        let snapshot = build([f.ended, f.running, f.later, f.tomorrowEvent])
        XCTAssertEqual(snapshot.entries.map { $0.id }, [f.running.id, f.later.id, f.tomorrowEvent.id])
        XCTAssertEqual(snapshot.todayCount, 2, "biten etkinlik bugün sayılmaz")
        XCTAssertEqual(snapshot.overdueCount, 0)
        if let first = snapshot.entries.first {
            XCTAssertEqual(snapshot.eventEnd(first), TestSupport.date("2026-09-27T11:00"))
        }
        let reminder = snapshot.entries.first { $0.id == f.later.id }
        XCTAssertNotNil(reminder)
        if let plain = reminder {
            XCTAssertNil(snapshot.eventEnd(plain))
            XCTAssertFalse(snapshot.isEnded(plain, at: TestSupport.date("2026-10-01T00:00")))
        }
    }

    func testEventDisappearsAndTodayCountDropsAtEventEnd() {
        let f = eventFixture()
        let snapshot = build([f.ended, f.running, f.later, f.tomorrowEvent])
        let beforeEnd = TestSupport.date("2026-09-27T10:59")
        let atEnd = TestSupport.date("2026-09-27T11:00")
        XCTAssertEqual(snapshot.visibleEntries(at: beforeEnd).first?.id, f.running.id)
        XCTAssertEqual(snapshot.visibleEntries(at: atEnd).first?.id, f.later.id)
        XCTAssertEqual(snapshot.visibleEntries(at: atEnd).count, 2)
        XCTAssertEqual(snapshot.todayCount(at: beforeEnd, calendar: calendar), 2)
        XCTAssertEqual(snapshot.todayCount(at: atEnd, calendar: calendar), 1)
        XCTAssertEqual(snapshot.todayCount(at: TestSupport.date("2026-09-27T14:00"), calendar: calendar), 0)
        XCTAssertEqual(snapshot.todayCount(at: TestSupport.date("2026-09-28T10:59"), calendar: calendar), 1)
        XCTAssertEqual(snapshot.todayCount(at: TestSupport.date("2026-09-28T11:00"), calendar: calendar), 0,
                       "ertesi gün de biten etkinlik sayılmaz")
        XCTAssertEqual(snapshot.overdueCount(at: TestSupport.date("2026-09-28T11:00")), 1, "etkinlik gecikmez")
    }

    func testTimelineDatesIncludeEventEnd() {
        let f = eventFixture()
        let snapshot = build([f.ended, f.running, f.later, f.tomorrowEvent])
        XCTAssertEqual(snapshot.timelineDates(after: now, calendar: calendar, limit: 20), [
            TestSupport.date("2026-09-27T11:00"),
            TestSupport.date("2026-09-27T14:00"),
            TestSupport.date("2026-09-28T00:00")
        ])
    }

    // MARK: Timeline

    private func makeEntry(_ title: String, overdueAt: String?) -> WidgetSnapshot.Entry {
        WidgetSnapshot.Entry(id: UUID(), title: title, anchor: overdueAt.map { TestSupport.date($0) },
                             overdueAt: overdueAt.map { TestSupport.date($0) }, hasTime: true, kind: .reminder,
                             priority: .normal, isEvent: false)
    }

    func testTimelineDatesIncludeTransitionsAndMidnight() {
        let snapshot = WidgetSnapshot(generatedAt: now, overdueCount: 1, todayCount: 1, followUpCount: 0,
                                      hideTitlesWhenLocked: false, entries: [
                                        makeEntry("Geçmiş", overdueAt: "2026-09-27T09:00"),
                                        makeEntry("Öğleden sonra", overdueAt: "2026-09-27T14:00"),
                                        makeEntry("Aynı an", overdueAt: "2026-09-27T14:00"),
                                        makeEntry("Gece yarısı", overdueAt: "2026-09-28T00:00"),
                                        makeEntry("Yarın sabah", overdueAt: "2026-09-28T09:00"),
                                        makeEntry("Ufuk sınırı", overdueAt: "2026-09-28T10:30"),
                                        makeEntry("Ufuk dışı", overdueAt: "2026-09-28T10:31"),
                                        makeEntry("Belirsiz", overdueAt: nil)
                                      ])
        let dates = snapshot.timelineDates(after: now, calendar: calendar, limit: 20)
        XCTAssertEqual(dates, [
            TestSupport.date("2026-09-27T14:00"),
            TestSupport.date("2026-09-28T00:00"),
            TestSupport.date("2026-09-28T09:00"),
            TestSupport.date("2026-09-28T10:30")
        ])
        XCTAssertEqual(snapshot.timelineDates(after: now, calendar: calendar, limit: 2), [
            TestSupport.date("2026-09-27T14:00"),
            TestSupport.date("2026-09-28T00:00")
        ])
        XCTAssertEqual(snapshot.timelineDates(after: now, calendar: calendar, limit: 0), [])
        XCTAssertEqual(snapshot.timelineDates(after: now, calendar: calendar, limit: -3), [])
    }

    func testTimelineDatesAlwaysContainNextMidnight() {
        let dates = WidgetSnapshot.empty.timelineDates(after: now, calendar: calendar, limit: 20)
        XCTAssertEqual(dates, [TestSupport.date("2026-09-28T00:00")])
        let atMidnight = WidgetSnapshot.empty.timelineDates(after: TestSupport.date("2026-09-28T00:00"),
                                                            calendar: calendar, limit: 20)
        XCTAssertEqual(atMidnight, [TestSupport.date("2026-09-29T00:00")])
    }

    func testTimelineFromBuiltSnapshot() {
        let snapshot = build(fixture().all)
        XCTAssertEqual(snapshot.timelineDates(after: now, calendar: calendar, limit: 20), [
            TestSupport.date("2026-09-27T14:00"),
            TestSupport.date("2026-09-28T00:00"),
            TestSupport.date("2026-09-28T09:00")
        ])
    }

    // MARK: Coding and equivalence

    func testCodableRoundTripWithISO8601() throws {
        let snapshot = build(fixture().all)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.entries.count, 9)

        let placeholder = WidgetSnapshot.placeholder(now: now)
        let placeholderData = try encoder.encode(placeholder)
        XCTAssertEqual(try decoder.decode(WidgetSnapshot.self, from: placeholderData), placeholder)
        XCTAssertEqual(placeholder.entries.count, 2)
    }

    func testEquivalenceIgnoresGenerationTimeOnTheSameDayOnly() {
        let items = [makeItem(.reminder, "Yarın", due: "2026-09-28T09:00")]
        let first = WidgetSnapshotBuilder.build(items: items, settings: settings, now: now, calendar: calendar)
        let later = WidgetSnapshotBuilder.build(items: items, settings: settings,
                                                now: TestSupport.date("2026-09-27T11:45"), calendar: calendar)
        XCTAssertNotEqual(first, later)
        XCTAssertTrue(WidgetSnapshotBuilder.isEquivalent(first, later, calendar: calendar))

        let nextDay = WidgetSnapshotBuilder.build(items: items, settings: settings,
                                                  now: TestSupport.date("2026-09-28T07:00"), calendar: calendar)
        XCTAssertFalse(WidgetSnapshotBuilder.isEquivalent(first, nextDay, calendar: calendar))

        var hidden = settings
        hidden.lockScreenShowsContent = false
        let redacted = WidgetSnapshotBuilder.build(items: items, settings: hidden, now: now, calendar: calendar)
        XCTAssertFalse(WidgetSnapshotBuilder.isEquivalent(first, redacted, calendar: calendar))

        var renamed = items[0]
        renamed.title = "Yarın sabah"
        let changed = WidgetSnapshotBuilder.build(items: [renamed], settings: settings, now: now, calendar: calendar)
        XCTAssertFalse(WidgetSnapshotBuilder.isEquivalent(first, changed, calendar: calendar))
    }
}
