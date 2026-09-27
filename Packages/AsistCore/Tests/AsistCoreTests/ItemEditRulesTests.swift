import Foundation
import XCTest
@testable import AsistCore

/// 07 §4.3 / §13: the "Düzenle" sheet semantics (ItemEditRules) and the Tekrar presets (RecurrencePresets).
/// Reference instant: Sun 2026-09-27 10:30 (Europe/Istanbul).
final class ItemEditRulesTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let now = TestSupport.date("2026-09-27T10:30")
    private let settings = AppSettings()

    private func reminder() -> Item {
        Item(kind: .reminder, title: "Teklifi gönder", priority: .normal,
             dueDate: TestSupport.date("2026-09-28T15:00"), hasTime: true,
             createdAt: TestSupport.date("2026-09-25T09:00"))
    }

    private func undatedTask() -> Item {
        Item(kind: .task, title: "Kalibrasyon", createdAt: TestSupport.date("2026-09-25T09:00"))
    }

    private func apply(_ original: Item, _ edited: Item, onto current: Item? = nil,
                       settings custom: AppSettings? = nil) -> ItemEditOutcome {
        ItemEditRules.apply(original: original, edited: edited, onto: current ?? original, now: now,
                            settings: custom ?? settings, calendar: calendar)
    }

    // MARK: - Unchanged / title

    func testUnchangedEditIsNotAChange() {
        let base = reminder()
        let outcome = apply(base, base)
        XCTAssertFalse(outcome.changed)
        XCTAssertNil(outcome.event)
        XCTAssertEqual(outcome.item, base)
    }

    func testTitleIsTrimmedAndFlattened() {
        let base = reminder()
        var edited = base
        edited.title = "  Yeni\nbaşlık  "
        let outcome = apply(base, edited)
        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(outcome.event, HistoryEvent.edited)
        XCTAssertEqual(outcome.item.title, "Yeni başlık")
        XCTAssertEqual(outcome.item.dueDate, base.dueDate)
    }

    func testEmptyTitleIsIgnored() {
        let base = reminder()
        var edited = base
        edited.title = "   \n "
        let outcome = apply(base, edited)
        XCTAssertFalse(outcome.changed)
        XCTAssertNil(outcome.event)
        XCTAssertEqual(outcome.item.title, "Teklifi gönder")
    }

    // MARK: - Time

    func testDueChangeReschedulesAndResetsNagState() {
        var base = reminder()
        base.snoozedUntil = TestSupport.date("2026-09-27T12:00")
        base.snoozeCount = 2
        base.lastDismissedAt = TestSupport.date("2026-09-27T09:00")
        var edited = base
        edited.dueDate = TestSupport.date("2026-09-29T10:00").addingTimeInterval(30)   // seconds are floored
        let outcome = apply(base, edited)
        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(outcome.event, HistoryEvent.rescheduled)
        XCTAssertEqual(outcome.item.dueDate, TestSupport.date("2026-09-29T10:00"))
        XCTAssertNil(outcome.item.snoozedUntil)
        XCTAssertEqual(outcome.item.snoozeCount, 0)
        XCTAssertNil(outcome.item.lastDismissedAt)
    }

    func testHasTimeChangeAloneReschedules() {
        let base = Item(kind: .task, title: "Rapor", dueDate: TestSupport.date("2026-09-28T09:00"), hasTime: true,
                        createdAt: TestSupport.date("2026-09-25T09:00"))
        var edited = base
        edited.hasTime = false
        let outcome = apply(base, edited)
        XCTAssertEqual(outcome.event, HistoryEvent.rescheduled)
        XCTAssertFalse(outcome.item.hasTime)
        XCTAssertEqual(outcome.item.dueDate, base.dueDate)
    }

    func testWaitingWithoutDueGetsDefaultWaitingDue() {
        let base = undatedTask()
        var edited = base
        edited.kind = .waiting
        let outcome = apply(base, edited)
        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(outcome.event, HistoryEvent.rescheduled)
        XCTAssertEqual(outcome.item.kind, .waiting)
        XCTAssertFalse(outcome.item.hasTime)
        let expected = ItemFactory.defaultWaitingDue(now: now, settings: settings, calendar: calendar)
        XCTAssertEqual(outcome.item.dueDate, expected)
        XCTAssertEqual(outcome.item.dueDate.map { TestSupport.format($0) }, "2026-09-29T10:00")   // 2 workdays
    }

    func testClearingDueClearsRecurrenceLeadsAndEvent() {
        var base = reminder()
        base.recurrence = Recurrence(frequency: .daily)
        base.leadTimesMinutes = [15]
        base.isEvent = true
        var edited = base
        edited.dueDate = nil
        let outcome = apply(base, edited)
        XCTAssertEqual(outcome.event, HistoryEvent.rescheduled)
        XCTAssertNil(outcome.item.dueDate)
        XCTAssertFalse(outcome.item.hasTime)
        XCTAssertNil(outcome.item.recurrence)
        XCTAssertEqual(outcome.item.leadTimesMinutes, [])
        XCTAssertFalse(outcome.item.isEvent)
    }

    // MARK: - Event, leads, recurrence

    func testEventOnAddsTheDefaultLead() {
        let base = reminder()
        var edited = base
        edited.isEvent = true
        let outcome = apply(base, edited)
        XCTAssertEqual(outcome.event, HistoryEvent.edited)
        XCTAssertTrue(outcome.item.isEvent)
        XCTAssertEqual(outcome.item.leadTimesMinutes, [15])

        var noDefault = AppSettings()
        noDefault.eventDefaultLeadMinutes = 0
        let without = apply(base, edited, settings: noDefault)
        XCTAssertTrue(without.item.isEvent)
        XCTAssertEqual(without.item.leadTimesMinutes, [])
    }

    func testEventNeedsATimeAndAnEventableKind() {
        let untimed = Item(kind: .task, title: "Ziyaret", dueDate: TestSupport.date("2026-09-28T09:00"),
                           hasTime: false, createdAt: TestSupport.date("2026-09-25T09:00"))
        var edited = untimed
        edited.isEvent = true
        let outcome = apply(untimed, edited)
        XCTAssertFalse(outcome.item.isEvent)
        XCTAssertFalse(outcome.changed)

        var base = reminder()
        base.isEvent = true
        var toNote = base
        toNote.kind = .note
        XCTAssertFalse(apply(base, toNote).item.isEvent)
    }

    func testLeadsAreSanitized() {
        let base = reminder()
        var edited = base
        edited.leadTimesMinutes = [30, 10, 30, -5, 0, 600_000]
        let outcome = apply(base, edited)
        XCTAssertEqual(outcome.item.leadTimesMinutes, [10, 30])
        XCTAssertEqual(outcome.event, HistoryEvent.edited)
    }

    func testRecurrenceIsKeptOnlyWithADue() {
        let task = undatedTask()
        var edited = task
        edited.recurrence = Recurrence(frequency: .daily)
        let undated = apply(task, edited)
        XCTAssertNil(undated.item.recurrence)
        XCTAssertFalse(undated.changed)

        let base = reminder()
        var withDue = base
        withDue.recurrence = Recurrence(frequency: .weekly, weekdays: [1])
        let dated = apply(base, withDue)
        XCTAssertEqual(dated.item.recurrence, Recurrence(frequency: .weekly, weekdays: [1]))
        XCTAssertEqual(dated.event, HistoryEvent.edited)
    }

    // MARK: - Review flag, concurrency

    func testNeedsReviewIsClearedOnlyByARealChange() {
        var base = reminder()
        base.needsReview = true
        XCTAssertTrue(apply(base, base).item.needsReview)
        var edited = base
        edited.priority = .high
        let outcome = apply(base, edited)
        XCTAssertFalse(outcome.item.needsReview)
        XCTAssertEqual(outcome.item.priority, .high)
    }

    func testConcurrentChangesOnTheCurrentCopyArePreserved() {
        let original = reminder()
        var current = original
        current.checklist = [ChecklistEntry(text: "Fiyatları kontrol et")]
        current.notes = "Bildirimden eklenen not"
        current.dueDate = TestSupport.date("2026-09-29T15:00")          // e.g. a roll-over in the meantime
        var edited = original
        edited.priority = .critical
        edited.person = "  Ahmet  "
        edited.projectID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")
        let outcome = apply(original, edited, onto: current)
        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(outcome.event, HistoryEvent.edited)                // the due was not edited in the sheet
        XCTAssertEqual(outcome.item.priority, .critical)
        XCTAssertEqual(outcome.item.person, "Ahmet")
        XCTAssertEqual(outcome.item.projectID, edited.projectID)
        XCTAssertEqual(outcome.item.checklist, current.checklist)
        XCTAssertEqual(outcome.item.notes, "Bildirimden eklenen not")
        XCTAssertEqual(outcome.item.dueDate, TestSupport.date("2026-09-29T15:00"))
    }

    func testEmptyPersonBecomesNil() {
        var base = reminder()
        base.person = "Ahmet"
        var edited = base
        edited.person = "   "
        let outcome = apply(base, edited)
        XCTAssertNil(outcome.item.person)
        XCTAssertTrue(outcome.changed)
    }

    // MARK: - RecurrencePresets

    func testRecurrencePresetsForTuesday29September() {
        let due = TestSupport.date("2026-09-29T10:00")        // Salı
        let presets = RecurrencePresets.presets(for: due, calendar: calendar)
        XCTAssertEqual(presets.map { $0.title },
                       ["Her gün", "Hafta içi her gün", "Her Salı", "İki haftada bir Salı", "Her ayın 29'u",
                        "Her yıl 29 Eylül"])
        XCTAssertEqual(presets.map { $0.id }, ["daily", "weekdays", "weekly", "biweekly", "monthly", "yearly"])
        XCTAssertEqual(presets[0].rule, Recurrence(frequency: .daily))
        XCTAssertEqual(presets[1].rule, Recurrence(frequency: .weekly, weekdays: [1, 2, 3, 4, 5]))
        XCTAssertEqual(presets[2].rule, Recurrence(frequency: .weekly, weekdays: [2]))
        XCTAssertEqual(presets[3].rule, Recurrence(frequency: .weekly, interval: 2, weekdays: [2]))
        XCTAssertEqual(presets[4].rule, Recurrence(frequency: .monthly, monthDay: 29))
        XCTAssertEqual(presets[5].rule, Recurrence(frequency: .yearly, monthDay: 29, month: 9))
    }
}
