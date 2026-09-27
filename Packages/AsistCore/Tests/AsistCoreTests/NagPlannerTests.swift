// NagPlannerTests.swift — WP3: the tests 04 §6.4 requires (worked examples, continuity, long-tails, recurrence
// carriers, tiers/budget + sentinels, rate limiter, signing clamp, mute, time-sensitive fallback, sounds, k-stability,
// snooze, determinism, quiet hours, takip, events, immediateRequests) plus the public helpers.
// Every date is built with TestSupport (Europe/Istanbul); nothing reads Date() or the device time zone.
// Expectations that depend on WP1/WP2 behaviour (RecurrenceEngine rules beyond daily, briefing text) are derived
// from those APIs at test time, so the tests hold for both the WP0 stubs and the final implementations.
import Foundation
import XCTest
@testable import AsistCore

final class NagPlannerTests: XCTestCase {
    private let calendar = TestSupport.calendar

    // MARK: - Helpers

    private func d(_ text: String) -> Date {
        TestSupport.date(text)
    }

    private func f(_ date: Date) -> String {
        TestSupport.format(date)
    }

    private func fs(_ dates: [Date]) -> [String] {
        dates.map { TestSupport.format($0) }
    }

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-" + AsistCalendar.pad(n, 12))!
    }

    private func makeItem(_ n: Int, title: String = "Teklif konusu", kind: ItemKind = .reminder,
                          priority: Priority = .normal, due: String?, hasTime: Bool = true) -> Item {
        var item = Item(id: uuid(n), kind: kind, title: title, createdAt: TestSupport.date("2026-09-20T09:00"))
        item.priority = priority
        if let due = due {
            item.dueDate = TestSupport.date(due)
        }
        item.hasTime = hasTime
        return item
    }

    private func makeInput(_ items: [Item], now: String, settings: AppSettings = AppSettings(),
                           signingExpiry: Date? = nil, allowTimeSensitive: Bool = true,
                           totalBudget: Int = 64) -> PlanInput {
        PlanInput(items: items, projects: [], places: [], settings: settings, now: d(now), calendar: calendar,
                  signingExpiry: signingExpiry, allowTimeSensitive: allowTimeSensitive, totalBudget: totalBudget)
    }

    private func plan(_ items: [Item], now: String, settings: AppSettings = AppSettings(),
                      signingExpiry: Date? = nil, allowTimeSensitive: Bool = true,
                      totalBudget: Int = 64) -> PlanResult {
        NagPlanner.plan(makeInput(items, now: now, settings: settings, signingExpiry: signingExpiry,
                                  allowTimeSensitive: allowTimeSensitive, totalBudget: totalBudget))
    }

    private func chain(_ anchor: String, _ profile: NagProfile, _ kind: NagProfileKind, critical: Bool = false,
                       settings: AppSettings = AppSettings(), now: String = "2026-09-27T10:00") -> [Date] {
        NagPlanner.chain(anchor: d(anchor), profile: profile, profileKind: kind, isCritical: critical,
                         settings: settings, now: d(now), calendar: calendar)
    }

    /// Item notifications (sentinel excluded), chronological.
    private func itemNotifications(_ result: PlanResult, _ id: UUID) -> [PlannedNotification] {
        let mine = result.notifications.filter { $0.itemID == id && $0.kind != .sentinel }
        return mine.sorted { (lhs: PlannedNotification, rhs: PlannedNotification) -> Bool in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.id < rhs.id
        }
    }

    private func oneShots(_ list: [PlannedNotification]) -> [PlannedNotification] {
        list.filter { $0.rule == .once }
    }

    private func notification(_ result: PlanResult, id: String) -> PlannedNotification? {
        result.notifications.first { $0.id == id }
    }

    private func fireText(_ result: PlanResult, id: String) -> String? {
        guard let found = notification(result, id: id) else { return nil }
        return f(found.fireDate)
    }

    private func isWeekend(_ date: Date) -> Bool {
        AsistCalendar.isoWeekday(date, calendar: calendar) >= 6
    }

    private func assertStrictlyIncreasing(_ dates: [Date], _ message: String) {
        var index = 1
        while index < dates.count {
            XCTAssertLessThan(dates[index - 1], dates[index], message + " at index \(index)")
            index += 1
        }
    }

    private func assertPlanOrder(_ result: PlanResult) {
        let list = result.notifications
        var index = 1
        while index < list.count {
            let previous = list[index - 1]
            let current = list[index]
            var ordered = false
            if previous.tier != current.tier {
                ordered = previous.tier < current.tier
            } else if previous.fireDate != current.fireDate {
                ordered = previous.fireDate < current.fireDate
            } else {
                ordered = previous.id < current.id
            }
            XCTAssertTrue(ordered, "output order (tier, fireDate, id) broken at \(current.id)")
            index += 1
        }
    }

    private func assertUniqueIDs(_ result: PlanResult) {
        let ids = result.notifications.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate notification ids")
    }

    /// Sounded one-shots that take part in the rate limiter (sentinels are added afterwards).
    private func limitedSounded(_ result: PlanResult) -> [PlannedNotification] {
        result.notifications.filter { (n: PlannedNotification) -> Bool in
            n.rule == .once && n.playsSound && n.kind != .sentinel && n.kind != .horizon
        }
    }

    private func assertHourlyCap(_ result: PlanResult) {
        let sounded = limitedSounded(result).map { $0.fireDate }.sorted()
        for start in sounded {
            let end = start.addingTimeInterval(3600)
            var count = 0
            for date in sounded where date >= start && date < end {
                count += 1
            }
            XCTAssertLessThanOrEqual(count, 8, "more than 8 sounded notifications in the hour from \(f(start))")
        }
    }

    // MARK: - Worked examples (04 §6.4)

    func testWorkedExampleNazikAfternoon() {
        let result = chain("2026-09-29T15:00", .nazik, .nazik)
        let expected: [String] = [
            "2026-09-29T15:00", "2026-09-29T15:10", "2026-09-29T15:30", "2026-09-29T16:30",
            "2026-09-30T08:30", "2026-09-30T10:30", "2026-09-30T12:30", "2026-09-30T14:30", "2026-09-30T16:30",
            "2026-10-01T08:30", "2026-10-01T10:30", "2026-10-01T12:30", "2026-10-01T14:30", "2026-10-01T16:30",
            "2026-10-02T08:30", "2026-10-02T10:30", "2026-10-02T12:30", "2026-10-02T14:30", "2026-10-02T16:30",
            "2026-10-03T09:00", "2026-10-04T09:00", "2026-10-05T08:30"
        ]
        XCTAssertEqual(Array(fs(result).prefix(expected.count)), expected)
        assertStrictlyIncreasing(result, "nazik")
    }

    func testWorkedExampleIsrarciHasNoEveningRepeats() {
        let result = chain("2026-09-29T15:00", .israrci, .israrci)
        let expected: [String] = [
            "2026-09-29T15:00", "2026-09-29T15:05", "2026-09-29T15:15", "2026-09-29T15:30", "2026-09-29T16:00",
            "2026-09-29T17:00",
            "2026-09-30T08:30", "2026-09-30T09:30", "2026-09-30T10:30", "2026-09-30T11:30", "2026-09-30T12:30",
            "2026-09-30T13:30", "2026-09-30T14:30", "2026-09-30T15:30", "2026-09-30T16:30", "2026-09-30T17:30",
            "2026-10-01T08:30"
        ]
        XCTAssertEqual(Array(fs(result).prefix(expected.count)), expected)
        for date in result {
            let minute = AsistCalendar.minuteOfDay(date, calendar: calendar)
            XCTAssertLessThan(minute, 18 * 60, "Israrcı must not repeat in the evening: \(f(date))")
        }
    }

    func testWorkedExampleNazikEvening() {
        let result = chain("2026-09-29T20:30", .nazik, .nazik)
        let expected: [String] = [
            "2026-09-29T20:30", "2026-09-29T20:40", "2026-09-29T21:00", "2026-09-29T22:00",
            "2026-09-30T08:30", "2026-09-30T10:30", "2026-09-30T12:30", "2026-09-30T14:30", "2026-09-30T16:30",
            "2026-10-01T08:30"
        ]
        XCTAssertEqual(Array(fs(result).prefix(expected.count)), expected)
    }

    func testWorkedExampleBirakmazAtNightRespectsQuietHoursAndCap() {
        let result = chain("2026-09-29T23:00", .birakmaz, .birakmaz, critical: true)
        var expected: [String] = ["2026-09-29T23:00"]
        let wednesdayStart = d("2026-09-30T07:30")
        for step in 0..<30 {
            expected.append(f(wednesdayStart.addingTimeInterval(TimeInterval(step * 15 * 60))))
        }
        expected.append("2026-10-01T08:30")
        XCTAssertEqual(Array(fs(result).prefix(expected.count)), expected)
        XCTAssertEqual(expected[30], "2026-09-30T14:45")
    }

    func testWorkedExampleTakipSkipsWeekends() {
        let result = chain("2026-10-02T16:00", .takip, .takip)
        let expected: [String] = ["2026-10-02T16:00", "2026-10-05T16:00", "2026-10-06T16:00"]
        XCTAssertEqual(Array(fs(result).prefix(expected.count)), expected)
        for date in result {
            XCTAssertFalse(isWeekend(date), "takip must skip weekends: \(f(date))")
            XCTAssertEqual(AsistCalendar.minuteOfDay(date, calendar: calendar), 16 * 60)
        }
    }

    func testWorkedExampleEtkinlikIsFirstAlertOnly() {
        let result = chain("2026-10-01T14:00", .etkinlik, .etkinlik)
        XCTAssertEqual(fs(result), ["2026-10-01T14:00"])
    }

    func testWorkedExampleMuteCollapsesNagsIntoMuteEnd() {
        var settings = AppSettings()
        settings.muteUntil = d("2026-09-29T11:30")
        let result = chain("2026-09-29T10:00", .nazik, .nazik, settings: settings, now: "2026-09-29T10:05")
        let expected: [String] = [
            "2026-09-29T10:00", "2026-09-29T11:30", "2026-09-29T13:30", "2026-09-29T15:30", "2026-09-29T17:30",
            "2026-09-30T08:30"
        ]
        XCTAssertEqual(Array(fs(result).prefix(expected.count)), expected)

        // Mute is only active while now < muteUntil.
        let expired = chain("2026-09-29T10:00", .nazik, .nazik, settings: settings, now: "2026-09-29T12:00")
        let unmuted: [String] = ["2026-09-29T10:00", "2026-09-29T10:10", "2026-09-29T10:30", "2026-09-29T11:30",
                                 "2026-09-29T13:30"]
        XCTAssertEqual(Array(fs(expired).prefix(unmuted.count)), unmuted)
    }

    func testNightAnchorKeepsNaggingThroughTheNextWorkday() {
        // DEVIATION(04 §6.4 phase 2): after the 07:30 quiet exit the next repeat is the same day's work start.
        let result = chain("2026-09-29T23:00", .nazik, .nazik)
        let expected: [String] = [
            "2026-09-29T23:00", "2026-09-30T07:30", "2026-09-30T08:30", "2026-09-30T10:30", "2026-09-30T12:30",
            "2026-09-30T14:30", "2026-09-30T16:30", "2026-10-01T08:30"
        ]
        XCTAssertEqual(Array(fs(result).prefix(expected.count)), expected)
        let israrci = chain("2026-09-29T23:59", .israrci, .israrci)
        XCTAssertEqual(Array(fs(israrci).prefix(4)), ["2026-09-29T23:59", "2026-09-30T07:30", "2026-09-30T08:30",
                                                     "2026-09-30T09:30"])
    }

    func testChainTerminatesWithEmptyWorkdays() {
        var settings = AppSettings()
        settings.workdays = []
        let kinds: [NagProfileKind] = [.nazik, .israrci, .birakmaz, .takip]
        let profiles = NagProfiles()
        for kind in kinds {
            let result = chain("2026-10-02T16:00", profiles[kind], kind, critical: kind == .birakmaz,
                               settings: settings)
            XCTAssertFalse(result.isEmpty)
            XCTAssertLessThanOrEqual(result.count, 401)
            assertStrictlyIncreasing(result, "empty workdays \(kind.rawValue)")
        }
        let waiting = makeItem(1, kind: .waiting, due: "2026-10-02T16:00", hasTime: false)
        let planned = plan([waiting], now: "2026-10-02T10:00", settings: settings)
        XCTAssertFalse(itemNotifications(planned, waiting.id).isEmpty)
    }

    func testChainsAreBoundedAndStartAtTheAnchor() {
        let profiles = NagProfiles()
        let anchors: [String] = ["2026-09-29T00:10", "2026-09-29T07:45", "2026-09-29T12:00", "2026-09-29T23:59",
                                 "2026-10-03T13:00"]
        for kind in NagProfileKind.allCases {
            for anchor in anchors {
                let result = chain(anchor, profiles[kind], kind, critical: kind == .birakmaz)
                XCTAssertEqual(result.first, d(anchor))
                XCTAssertLessThanOrEqual(result.count, 401)
                assertStrictlyIncreasing(result, "\(kind.rawValue) \(anchor)")
                var perDay: [String: Int] = [:]
                for date in result {
                    let key = AsistCalendar.dayKey(date, calendar: calendar)
                    perDay[key] = (perDay[key] ?? 0) + 1
                }
                for count in perDay.values {
                    XCTAssertLessThanOrEqual(count, profiles[kind].dailyCap)
                }
            }
        }
    }

    // MARK: - Quiet hours

    func testQuietHoursWithoutWrapAround() {
        var settings = AppSettings()
        settings.quietStart = ClockTime(1, 0)
        settings.quietEnd = ClockTime(6, 0)
        let result = chain("2026-09-29T00:50", .birakmaz, .birakmaz, critical: true, settings: settings)
        let expected: [String] = ["2026-09-29T00:50", "2026-09-29T00:53", "2026-09-29T00:56", "2026-09-29T06:00",
                                  "2026-09-29T06:15", "2026-09-29T06:30"]
        XCTAssertEqual(Array(fs(result).prefix(expected.count)), expected)
    }

    func testCriticalMayIgnoreQuietHours() {
        var settings = AppSettings()
        settings.criticalIgnoresQuietHours = true
        let result = chain("2026-09-29T23:00", .birakmaz, .birakmaz, critical: true, settings: settings)
        let expected: [String] = ["2026-09-29T23:00", "2026-09-29T23:03", "2026-09-29T23:06", "2026-09-29T23:10",
                                  "2026-09-29T23:15", "2026-09-29T23:30", "2026-09-29T23:45", "2026-09-30T00:00"]
        XCTAssertEqual(Array(fs(result).prefix(expected.count)), expected)
        // Not critical → quiet hours apply even with the setting on.
        let normal = chain("2026-09-29T23:00", .birakmaz, .birakmaz, critical: false, settings: settings)
        XCTAssertEqual(normal.count > 1 ? f(normal[1]) : "-", "2026-09-30T07:30")
    }

    // MARK: - Continuity without any reconcile (05a #2)

    func testContinuityWithoutAnyReconcile() {
        let item = makeItem(1, priority: .high, due: "2026-09-29T15:00")
        let settings = AppSettings()
        let result = plan([item], now: "2026-09-27T10:00", settings: settings)
        let notes = oneShots(itemNotifications(result, item.id))
        let expected: [(Int, String)] = [
            (0, "2026-09-29T15:00"), (1, "2026-09-29T15:05"), (2, "2026-09-29T15:15"), (3, "2026-09-29T15:30"),
            (4, "2026-09-29T16:00"), (5, "2026-09-29T17:00"), (6, "2026-09-30T08:30"), (7, "2026-09-30T09:30"),
            (8, "2026-09-30T10:30"),
            (16, "2026-10-01T08:30"), (26, "2026-10-02T08:30"), (36, "2026-10-03T09:00")
        ]
        XCTAssertEqual(notes.map { $0.id }, expected.map { NotificationID.chain(item.id, $0.0) })
        XCTAssertEqual(fs(notes.map { $0.fireDate }), expected.map { $0.1 })
        XCTAssertEqual(notes.first?.kind, PlannedNotification.Kind.first)
        for note in notes.dropFirst() {
            XCTAssertEqual(note.kind, PlannedNotification.Kind.nag)
            XCTAssertEqual(note.categoryID, NotificationCategoryID.item)
            XCTAssertEqual(note.threadID, NotificationID.thread(item.id))
        }
        // F = Mon 08:30 is before A → no long-tail yet.
        XCTAssertNil(notification(result, id: NotificationID.longTail(item.id)))
        // Horizon sentinel one hour after the last planned item notification.
        XCTAssertEqual(fireText(result, id: NotificationID.horizonSentinel), "2026-10-03T10:00")
        XCTAssertEqual(notification(result, id: NotificationID.horizonSentinel)?.kind, PlannedNotification.Kind.horizon)

        // Briefings Mon–Fri 08:00, content projected at the fire date (planned exactly when AgendaBuilder has text).
        let workdays: [String] = ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02"]
        for (index, day) in workdays.enumerated() {
            let fire = d(day + "T08:00")
            let id = NotificationID.briefing(dayKey: AsistCalendar.dayKey(fire, calendar: calendar))
            let planned = notification(result, id: id)
            if let text = AgendaBuilder.briefing(items: [item], at: fire, settings: settings, calendar: calendar) {
                XCTAssertEqual(planned?.body, text.body)
                XCTAssertEqual(planned?.title, text.title)
                XCTAssertEqual(planned.map { f($0.fireDate) }, day + "T08:00")
                XCTAssertEqual(planned?.categoryID, NotificationCategoryID.briefing)
                XCTAssertEqual(planned?.threadID, NotificationID.digestThread)
                if index >= 2 {
                    let all = text.title + " " + text.subtitle + " " + text.body
                    XCTAssertTrue(all.contains("Teklif konusu"), "Wed–Fri briefings list the overdue item")
                }
            } else {
                XCTAssertNil(planned)
            }
        }
        let briefings = result.notifications.filter { $0.kind == .briefing }
        XCTAssertLessThanOrEqual(briefings.count, 5)
        XCTAssertFalse(briefings.contains { isWeekend($0.fireDate) })
        assertPlanOrder(result)
        assertUniqueIDs(result)
    }

    // MARK: - Long-tails (05a #2, 05b C3)

    func testLongTailForHighItemDedupesMorningNags() {
        let high = makeItem(1, priority: .high, due: "2026-09-29T15:00")
        let normal = makeItem(2, title: "Ahmet'i ara", due: "2026-09-29T15:00")
        let result = plan([high, normal], now: "2026-09-29T10:00")
        let tail = notification(result, id: NotificationID.longTail(high.id))
        XCTAssertEqual(tail?.kind, PlannedNotification.Kind.longTail)
        XCTAssertEqual(tail?.rule, PlannedNotification.Rule.daily(hour: 8, minute: 30))
        XCTAssertEqual(tail.map { f($0.fireDate) }, "2026-09-30T08:30")
        XCTAssertEqual(tail?.tier, 0)
        XCTAssertNil(tail?.badge)
        XCTAssertEqual(tail?.soundName, "asist-onemli.wav")
        // Wed 08:30 (k = 6) and the Thu/Fri 08:30 day-tails are covered by the repeat.
        let nags = itemNotifications(result, high.id).filter { $0.kind == .nag }
        XCTAssertFalse(nags.contains { AsistCalendar.minuteOfDay($0.fireDate, calendar: calendar) == 8 * 60 + 30 })
        XCTAssertNil(notification(result, id: NotificationID.chain(high.id, 6)))
        XCTAssertNotNil(notification(result, id: NotificationID.chain(high.id, 7)))
        // Normal items get no long-tail.
        XCTAssertNil(notification(result, id: NotificationID.longTail(normal.id)))
    }

    func testAtMostFiveStaggeredLongTails() {
        var items: [Item] = []
        for n in 1...6 {
            let priority: Priority = n <= 3 ? .critical : .high
            items.append(makeItem(n, title: "Acil iş \(n)", priority: priority, due: "2026-09-28T09:0\(n)"))
        }
        let result = plan(items, now: "2026-09-29T10:00")
        let tails = result.notifications.filter { $0.kind == .longTail }
        XCTAssertEqual(tails.count, 5)
        let expected: [(Int, Int)] = [(1, 30), (2, 32), (3, 34), (4, 36), (5, 38)]
        for (n, minute) in expected {
            let tail = notification(result, id: NotificationID.longTail(uuid(n)))
            XCTAssertEqual(tail?.rule, PlannedNotification.Rule.daily(hour: 8, minute: minute))
            XCTAssertEqual(tail.map { f($0.fireDate) }, "2026-09-30T08:" + String(minute))
        }
        XCTAssertNil(notification(result, id: NotificationID.longTail(uuid(6))))
    }

    // MARK: - Recurrence (D27)

    func testDailyRecurrenceUsesCarrier() {
        var item = makeItem(1, title: "İlaç al", due: "2026-09-29T09:00")
        item.recurrence = Recurrence(frequency: .daily)
        let result = plan([item], now: "2026-09-29T10:00")
        let carrier = notification(result, id: NotificationID.carrier(item.id, suffix: "d"))
        XCTAssertEqual(carrier?.kind, PlannedNotification.Kind.carrier)
        XCTAssertEqual(carrier?.rule, PlannedNotification.Rule.daily(hour: 9, minute: 0))
        XCTAssertEqual(carrier.map { f($0.fireDate) }, "2026-09-30T09:00")
        XCTAssertEqual(carrier?.tier, 1)
        XCTAssertNil(carrier?.badge)
        let notes = itemNotifications(result, item.id)
        XCTAssertFalse(notes.contains { $0.kind == .occurrence })
        XCTAssertTrue(notes.contains { $0.kind == .nag })
        let nextOccurrence = d("2026-09-30T09:00")
        XCTAssertFalse(notes.contains { $0.kind == .nag && $0.fireDate >= nextOccurrence })
        XCTAssertNil(notification(result, id: NotificationID.longTail(item.id)))
    }

    func testRecurrenceCompletedEarlyUsesSevenOccurrences() {
        var item = makeItem(1, title: "İlaç al", due: "2026-09-30T09:00")
        item.recurrence = Recurrence(frequency: .daily)
        let result = plan([item], now: "2026-09-29T08:00")
        let notes = itemNotifications(result, item.id)
        XCTAssertFalse(notes.contains { $0.kind == .carrier })
        let occurrences = notes.filter { $0.kind == .occurrence }
        var expected: [String] = []
        for day in 1...7 {
            let date = d("2026-10-0" + String(day) + "T09:00")
            expected.append(NotificationID.occurrence(item.id, minuteKey: AsistCalendar.minuteKey(date, calendar: calendar)))
        }
        XCTAssertEqual(occurrences.map { $0.id }, expected)
        XCTAssertEqual(occurrences.first?.categoryID, NotificationCategoryID.item)
        XCTAssertEqual(fireText(result, id: NotificationID.chain(item.id, 0)), "2026-09-30T09:00")
    }

    func testWeeklyRecurrenceCarriersReplaceFirstAlert() {
        var item = makeItem(1, title: "Haftalık rapor", due: "2026-09-28T09:00")
        item.recurrence = Recurrence(frequency: .weekly, weekdays: [1, 4])
        let result = plan([item], now: "2026-09-27T10:00")
        let monday = notification(result, id: NotificationID.carrier(item.id, suffix: "w2"))
        let thursday = notification(result, id: NotificationID.carrier(item.id, suffix: "w5"))
        XCTAssertEqual(monday?.rule, PlannedNotification.Rule.weekly(weekday: 2, hour: 9, minute: 0))
        XCTAssertEqual(thursday?.rule, PlannedNotification.Rule.weekly(weekday: 5, hour: 9, minute: 0))
        XCTAssertEqual(monday.map { f($0.fireDate) }, "2026-09-28T09:00")
        XCTAssertEqual(thursday.map { f($0.fireDate) }, "2026-10-01T09:00")
        XCTAssertNil(notification(result, id: NotificationID.chain(item.id, 0)), "the carrier delivers the due date")
        XCTAssertFalse(itemNotifications(result, item.id).contains { $0.kind == .occurrence })
    }

    func testMonthlyDay31UsesOneShotOccurrences() {
        var item = makeItem(1, title: "Aylık bakım", due: "2026-09-30T09:00")
        let rule = Recurrence(frequency: .monthly, monthDay: 31)
        item.recurrence = rule
        let now = d("2026-09-27T10:00")
        let result = plan([item], now: "2026-09-27T10:00")
        let notes = itemNotifications(result, item.id)
        XCTAssertFalse(notes.contains { $0.kind == .carrier })

        // Expected ids derived from RecurrenceEngine (≤ 14 days + the first one beyond).
        let due = d("2026-09-30T09:00")
        let engine = RecurrenceEngine.occurrences(of: rule, time: ClockTime(9, 0), after: due, anchor: due, count: 7,
                                                  calendar: calendar)
        let horizon = now.addingTimeInterval(14 * 86_400)
        var expected: [String] = []
        for occurrence in engine where occurrence > now {
            expected.append(NotificationID.occurrence(item.id, minuteKey: AsistCalendar.minuteKey(occurrence,
                                                                                                    calendar: calendar)))
            if occurrence > horizon { break }
        }
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(notes.filter { $0.kind == .occurrence }.map { $0.id }, expected)
    }

    func testOccurrenceCopyPromisesNoMorningRepeat() {
        // Every 2 days → no carrier; several one-shot occurrences 2 days apart. The next kept element after an
        // occurrence is the next occurrence, so the copy must not say "yarın sabah yine" / "devam edeceğim".
        var item = makeItem(1, title: "Filtreleri kontrol et", due: "2026-09-29T09:00")
        item.recurrence = Recurrence(frequency: .daily, interval: 2)
        let result = plan([item], now: "2026-09-29T10:00")
        let occurrences = itemNotifications(result, item.id).filter { $0.kind == .occurrence }
        XCTAssertGreaterThanOrEqual(occurrences.count, 2)
        for occurrence in occurrences {
            XCTAssertFalse(occurrence.subtitle.contains("Bugünlük son"), occurrence.id)
            XCTAssertTrue(occurrence.subtitle.contains("09:00"), "k0 subtitle keeps the occurrence time: \(occurrence.subtitle)")
            XCTAssertEqual(occurrence.body.components(separatedBy: "\n").last,
                           "Asist'i bir kez açarsan hatırlatmaya devam ederim.")
        }
    }

    // MARK: - Tiers, budget and sentinels

    func testBudgetKeepsTierOrderAndSentinelCopiesEarliestDrop() {
        let item = makeItem(1, due: "2026-09-29T15:00")
        let far = makeItem(2, title: "Yıllık denetim", due: "2026-10-19T10:00")
        let result = plan([item, far], now: "2026-09-29T10:00", totalBudget: 19)
        XCTAssertEqual(result.itemBudget, 5)

        let kept = itemNotifications(result, item.id)
        XCTAssertEqual(kept.map { $0.id }, (0...4).map { NotificationID.chain(item.id, $0) })
        XCTAssertEqual(fs(kept.map { $0.fireDate }), ["2026-09-29T15:00", "2026-09-29T15:10", "2026-09-29T15:30",
                                                     "2026-09-29T16:30", "2026-09-30T08:30"])
        XCTAssertEqual(kept.map { $0.tier }, [0, 1, 1, 1, 1])
        XCTAssertTrue(itemNotifications(result, far.id).isEmpty, "tier-4 first alert does not fit")

        // Dropped: k5 Wed 10:30, k6 Wed 12:30 and the Thu/Fri/Sat day-tails (tier 3); the tier-4 drop is not counted.
        XCTAssertEqual(result.droppedCount, 5)
        XCTAssertEqual(result.earliestDroppedDate.map { f($0) }, "2026-09-30T10:30")
        let withoutFar = plan([item], now: "2026-09-29T10:00", totalBudget: 19)
        XCTAssertEqual(withoutFar.droppedCount, result.droppedCount)

        guard let sentinel = notification(result, id: NotificationID.sentinel) else {
            XCTFail("budget sentinel missing")
            return
        }
        XCTAssertEqual(sentinel.kind, PlannedNotification.Kind.sentinel)
        XCTAssertEqual(sentinel.itemID, item.id)
        XCTAssertEqual(sentinel.attempt, 5)
        XCTAssertEqual(f(sentinel.fireDate), "2026-09-30T10:30")
        XCTAssertEqual(sentinel.rule, PlannedNotification.Rule.once)
        XCTAssertEqual(sentinel.categoryID, NotificationCategoryID.item)
        XCTAssertEqual(sentinel.threadID, NotificationID.thread(item.id))
        XCTAssertEqual(sentinel.interruption, PlannedNotification.Interruption.active)
        XCTAssertEqual(sentinel.relevance, 0.7)
        XCTAssertTrue(sentinel.playsSound)
        XCTAssertEqual(sentinel.body.components(separatedBy: "\n").last,
                       NotificationCopy.budgetSentinelLine(extraCount: 4))
        XCTAssertEqual(sentinel.title, kept.first?.title)
        assertPlanOrder(result)
        assertUniqueIDs(result)
    }

    func testMoreThanFiftyCandidatesFillTheBudgetByTier() {
        var items: [Item] = []
        let base = d("2026-09-30T08:30")
        for index in 0..<60 {
            var item = makeItem(100 + index, title: "İş \(index)", due: nil)
            item.dueDate = base.addingTimeInterval(TimeInterval(index * 600))
            items.append(item)
        }
        let result = plan(items, now: "2026-09-29T10:00")
        XCTAssertEqual(result.itemBudget, 50)
        let itemNotes = result.notifications.filter { $0.itemID != nil && $0.kind != .sentinel }
        XCTAssertEqual(itemNotes.count, 50)
        for note in itemNotes {
            XCTAssertEqual(note.tier, 0)
            XCTAssertEqual(note.kind, PlannedNotification.Kind.first)
        }
        XCTAssertGreaterThan(result.droppedCount, 0)
        XCTAssertGreaterThan(result.rateLimitedCount, 0)
        let sentinel = notification(result, id: NotificationID.sentinel)
        XCTAssertNotNil(sentinel?.itemID)
        XCTAssertEqual(sentinel?.fireDate, result.earliestDroppedDate)
        XCTAssertEqual(sentinel?.body.components(separatedBy: "\n").last,
                       NotificationCopy.budgetSentinelLine(extraCount: result.droppedCount - 1))
        XCTAssertLessThanOrEqual(result.notifications.count, 64)
        assertPlanOrder(result)
        assertUniqueIDs(result)
    }

    func testOverdueItemKeepsItsNextFourPendingNagsInTierOne() {
        // Overdue since Monday 15:00 (Nazik): k0…k4 are past, the pending follow-ups start at k5 (Tue 10:30).
        let overdue = makeItem(1, title: "Unutulan iş", due: "2026-09-28T15:00")
        // Three items due tomorrow: 3 first alerts (tier 0) + 12 nags k1…k4 (tier 1) exceed the budget of 12.
        let fillers = [makeItem(10, title: "İş A", due: "2026-09-30T11:00"),
                       makeItem(11, title: "İş B", due: "2026-09-30T13:00"),
                       makeItem(12, title: "İş C", due: "2026-09-30T15:00")]
        let result = plan([overdue] + fillers, now: "2026-09-29T10:00", totalBudget: 26)
        XCTAssertEqual(result.itemBudget, 12)

        // DEVIATION(04 §6.4 step 6): tier 1 = the first 4 *pending* follow-ups, so the forgotten item keeps nagging.
        let kept = itemNotifications(result, overdue.id)
        XCTAssertEqual(kept.map { $0.id }, (5...8).map { NotificationID.chain(overdue.id, $0) })
        XCTAssertEqual(fs(kept.map { $0.fireDate }), ["2026-09-29T10:30", "2026-09-29T12:30", "2026-09-29T14:30",
                                                     "2026-09-29T16:30"])
        XCTAssertEqual(kept.map { $0.tier }, [1, 1, 1, 1])
        XCTAssertEqual(kept.map { $0.attempt }, [5, 6, 7, 8], "attempt stays the absolute k")
        XCTAssertNil(notification(result, id: NotificationID.chain(overdue.id, 9)), "5th pending nag is tier 3")
        for filler in fillers {
            XCTAssertNotNil(notification(result, id: NotificationID.chain(filler.id, 0)), "first alerts stay")
        }
        XCTAssertGreaterThan(result.droppedCount, 0)
        assertPlanOrder(result)
        assertUniqueIDs(result)
    }

    func testHorizonSentinelForStaleItemsAndNoneWithoutItems() {
        let stale = makeItem(1, due: "2026-09-01T10:00")
        let result = plan([stale], now: "2026-09-29T10:00")
        XCTAssertTrue(oneShots(itemNotifications(result, stale.id)).isEmpty)
        let horizon = notification(result, id: NotificationID.horizonSentinel)
        XCTAssertEqual(horizon.map { f($0.fireDate) }, "2026-10-12T08:30")
        XCTAssertNil(horizon?.itemID)
        XCTAssertEqual(horizon?.categoryID, NotificationCategoryID.system)
        XCTAssertEqual(horizon?.threadID, NotificationID.systemThread)
        XCTAssertEqual(horizon?.title, NotificationCopy.horizonSentinelContent(openCount: 1).title)

        let empty = plan([], now: "2026-09-29T10:00")
        XCTAssertNil(notification(empty, id: NotificationID.horizonSentinel))
        XCTAssertNil(notification(empty, id: NotificationID.sentinel))
        var note = makeItem(2, title: "Kablo kesitleri", kind: .note, due: nil)
        note.notes = "4 mm²"
        let notesOnly = plan([note], now: "2026-09-29T10:00")
        XCTAssertNil(notification(notesOnly, id: NotificationID.horizonSentinel))
        XCTAssertTrue(itemNotifications(notesOnly, note.id).isEmpty)
    }

    // MARK: - Rate limiter (05b C2)

    func testRateLimiterSpacesNagsAndCapsTheHour() {
        let items = [makeItem(1, priority: .high, due: "2026-09-29T15:00"),
                     makeItem(2, title: "Ahmet'i ara", priority: .high, due: "2026-09-29T15:00"),
                     makeItem(3, title: "Siparişi onayla", priority: .high, due: "2026-09-29T15:00")]
        let result = plan(items, now: "2026-09-29T10:00")
        for item in items {
            XCTAssertEqual(fireText(result, id: NotificationID.chain(item.id, 0)), "2026-09-29T15:00", "k0 never moves")
        }
        var firstNags: [String] = []
        for item in items {
            firstNags.append(fireText(result, id: NotificationID.chain(item.id, 1)) ?? "-")
        }
        XCTAssertEqual(firstNags, ["2026-09-29T15:05", "2026-09-29T15:08", "2026-09-29T15:11"])
        assertHourlyCap(result)

        let sounded = limitedSounded(result)
        for nag in sounded where nag.kind == .nag {
            for other in sounded where other.id != nag.id {
                let gap = abs(nag.fireDate.timeIntervalSince(other.fireDate))
                XCTAssertGreaterThanOrEqual(gap, 180, "\(nag.id) too close to \(other.id)")
            }
        }
        XCTAssertGreaterThan(result.rateLimitedCount, 0)
        XCTAssertEqual(result.droppedCount, 0, "rate-limited nags are not budget drops")
        XCTAssertNil(notification(result, id: NotificationID.sentinel))
    }

    func testShiftedNagSurvivesReconcileBetweenChainAndShiftedDate() {
        let first = makeItem(1, title: "Ahmet'i ara", due: "2026-09-29T15:00")
        let second = makeItem(2, title: "Siparişi onayla", due: "2026-09-29T14:50")
        let shiftedID = NotificationID.chain(second.id, 1)
        let before = plan([first, second], now: "2026-09-29T10:00")
        // B.k1 (15:00) collides with A.k0 (15:00, fixed) and is moved to 15:03.
        XCTAssertEqual(fireText(before, id: shiftedID), "2026-09-29T15:03")
        let pendingDate = d("2026-09-29T15:03")

        // A fired and was completed at 15:01: the fixed neighbour is gone on the replan.
        var done = first
        done.status = .done
        var input = makeInput([done, second], now: "2026-09-29T15:01")
        let withoutPending = NagPlanner.plan(input)
        XCTAssertNil(notification(withoutPending, id: shiftedID), "without pending dates the chain cutoff drops it")

        input.pendingNagDates = [shiftedID: pendingDate]
        let carried = NagPlanner.plan(input)
        let kept = notification(carried, id: shiftedID)
        XCTAssertEqual(kept.map { f($0.fireDate) }, "2026-09-29T15:03", "the pending shifted nag is kept at its date")
        XCTAssertEqual(kept?.kind, PlannedNotification.Kind.nag)
        XCTAssertEqual(kept?.attempt, 1)
        XCTAssertEqual(kept?.tier, 1)
        XCTAssertEqual(fireText(carried, id: NotificationID.chain(second.id, 2)), "2026-09-29T15:20")
        assertPlanOrder(carried)
        assertUniqueIDs(carried)

        // A pending date more than 15 minutes after the chain date is not a rate-limiter shift: not carried.
        input.pendingNagDates = [shiftedID: d("2026-09-29T15:16")]
        XCTAssertNil(notification(NagPlanner.plan(input), id: shiftedID))
    }

    // MARK: - Signing (D17, 05b A1)

    func testSigningClampKeepsFirstAlertsAndLongTails() {
        let item = makeItem(1, priority: .high, due: "2026-09-29T11:00")
        let expiry = d("2026-09-29T13:00")
        let result = plan([item], now: "2026-09-29T10:00", signingExpiry: expiry)
        let limit = expiry.addingTimeInterval(-300)
        XCTAssertFalse(result.notifications.contains { $0.kind == .nag && $0.fireDate > limit })
        XCTAssertEqual(fireText(result, id: NotificationID.chain(item.id, 0)), "2026-09-29T11:00")
        XCTAssertNotNil(notification(result, id: NotificationID.longTail(item.id)))
        let nags = itemNotifications(result, item.id).filter { $0.kind == .nag }
        XCTAssertEqual(fs(nags.map { $0.fireDate }), ["2026-09-29T11:05", "2026-09-29T11:15", "2026-09-29T11:30",
                                                     "2026-09-29T12:00"])
        let signing = result.notifications.filter { $0.kind == .signing }
        XCTAssertEqual(signing.map { $0.id }, [NotificationID.signing(minuteKey: "202609291301")])
        XCTAssertEqual(signing.first?.title, NotificationCopy.signingExpiredContent().title)
    }

    func testSigningWarningsAndExpiryNotice() {
        let expiry = d("2026-09-29T12:00")
        let result = plan([], now: "2026-09-27T10:00", signingExpiry: expiry)
        let signing = result.notifications.filter { $0.kind == .signing }.sorted { $0.fireDate < $1.fireDate }
        XCTAssertEqual(fs(signing.map { $0.fireDate }), ["2026-09-27T12:00", "2026-09-28T12:00", "2026-09-29T08:00",
                                                        "2026-09-29T12:01"])
        for note in signing {
            XCTAssertEqual(note.interruption, PlannedNotification.Interruption.timeSensitive)
            XCTAssertEqual(note.relevance, 0.9)
            XCTAssertEqual(note.categoryID, NotificationCategoryID.system)
            XCTAssertEqual(note.threadID, NotificationID.systemThread)
            XCTAssertEqual(note.id, NotificationID.signing(minuteKey: AsistCalendar.minuteKey(note.fireDate,
                                                                                             calendar: calendar)))
            XCTAssertNil(note.itemID)
        }
        XCTAssertEqual(signing.last?.title, NotificationCopy.signingExpiredContent().title)
        // No signing notifications without a readable profile.
        XCTAssertFalse(plan([], now: "2026-09-27T10:00").notifications.contains { $0.kind == .signing })
    }

    // MARK: - Mute (D32)

    func testMuteSilencesFirstAlertsAndCollapsesNags() {
        var settings = AppSettings()
        settings.muteUntil = d("2026-09-29T11:30")
        let item = makeItem(1, due: "2026-09-29T10:30")
        let result = plan([item], now: "2026-09-29T10:00", settings: settings)
        let notes = oneShots(itemNotifications(result, item.id))
        guard notes.count >= 3 else {
            XCTFail("expected k0, k1, k2")
            return
        }
        XCTAssertEqual(notes[0].id, NotificationID.chain(item.id, 0))
        XCTAssertEqual(f(notes[0].fireDate), "2026-09-29T10:30")
        XCTAssertFalse(notes[0].playsSound)
        XCTAssertEqual(notes[0].interruption, PlannedNotification.Interruption.passive)
        XCTAssertNil(notes[0].soundName)
        XCTAssertEqual(notes[1].id, NotificationID.chain(item.id, 1))
        XCTAssertEqual(f(notes[1].fireDate), "2026-09-29T11:30")
        XCTAssertTrue(notes[1].playsSound)
        XCTAssertEqual(notes[1].interruption, PlannedNotification.Interruption.active)
        XCTAssertEqual(notes[2].id, NotificationID.chain(item.id, 2))
        XCTAssertEqual(f(notes[2].fireDate), "2026-09-29T12:00")
        let windowStart = d("2026-09-29T10:30")
        let windowEnd = d("2026-09-29T11:30")
        XCTAssertFalse(notes.contains { $0.fireDate > windowStart && $0.fireDate < windowEnd })
    }

    func testMuteKeepsCriticalFirstAlertSound() {
        var settings = AppSettings()
        settings.muteUntil = d("2026-09-29T11:30")
        let item = makeItem(1, priority: .critical, due: "2026-09-29T10:40")
        let result = plan([item], now: "2026-09-29T10:00", settings: settings)
        let first = notification(result, id: NotificationID.chain(item.id, 0))
        XCTAssertEqual(first?.playsSound, true)
        XCTAssertEqual(first?.interruption, PlannedNotification.Interruption.timeSensitive)
        XCTAssertEqual(first?.soundName, "asist-kritik.wav")
        XCTAssertEqual(fireText(result, id: NotificationID.chain(item.id, 1)), "2026-09-29T11:30")
        XCTAssertEqual(fireText(result, id: NotificationID.chain(item.id, 2)), "2026-09-29T11:45")
    }

    // MARK: - Attributes and sounds (03 §3.2, 05b B7, D37)

    func testTimeSensitiveFallbackAndSounds() {
        let high = makeItem(1, priority: .high, due: "2026-09-29T15:00")
        let critical = makeItem(2, title: "Pano enerjisini kes", priority: .critical, due: "2026-09-29T16:00")
        let normal = makeItem(3, title: "Ekmek al", due: "2026-09-29T14:00")
        let expiry = d("2026-09-30T12:00")
        let result = plan([high, critical, normal], now: "2026-09-29T10:00", signingExpiry: expiry,
                          allowTimeSensitive: false)
        XCTAssertFalse(result.notifications.contains { $0.interruption == .timeSensitive })
        XCTAssertTrue(result.notifications.contains { $0.kind == .signing })

        XCTAssertEqual(notification(result, id: NotificationID.chain(high.id, 0))?.soundName, "asist-onemli.wav")
        XCTAssertNil(notification(result, id: NotificationID.chain(high.id, 1))?.soundName)
        XCTAssertEqual(notification(result, id: NotificationID.chain(high.id, 3))?.soundName, "asist-onemli.wav")
        XCTAssertNotNil(notification(result, id: NotificationID.chain(high.id, 1)))
        XCTAssertNotNil(notification(result, id: NotificationID.chain(high.id, 3)))
        XCTAssertEqual(notification(result, id: NotificationID.longTail(high.id))?.soundName, "asist-onemli.wav")
        XCTAssertEqual(notification(result, id: NotificationID.chain(critical.id, 0))?.soundName, "asist-kritik.wav")
        let normalFirst = notification(result, id: NotificationID.chain(normal.id, 0))
        XCTAssertNotNil(normalFirst)
        XCTAssertNil(normalFirst?.soundName)
        XCTAssertEqual(normalFirst?.interruption, PlannedNotification.Interruption.active)
        XCTAssertEqual(normalFirst?.relevance, 0.5)

        // With the setting enabled: high → timeSensitive 0.8, critical → timeSensitive 1.0.
        let allowed = plan([high, critical], now: "2026-09-29T10:00")
        let highFirst = notification(allowed, id: NotificationID.chain(high.id, 0))
        XCTAssertEqual(highFirst?.interruption, PlannedNotification.Interruption.timeSensitive)
        XCTAssertEqual(highFirst?.relevance, 0.8)
        let criticalFirst = notification(allowed, id: NotificationID.chain(critical.id, 0))
        XCTAssertEqual(criticalFirst?.relevance, 1.0)
        // Nags of items overdue at their fire date carry relevance 1.0.
        XCTAssertEqual(notification(allowed, id: NotificationID.chain(high.id, 1))?.relevance, 1.0)
    }

    // MARK: - Identity and stability

    func testIdsStayStableWhenNowAdvances() {
        let item = makeItem(1, priority: .high, due: "2026-09-29T15:00")
        let fullChain = chain("2026-09-29T15:00", .israrci, .israrci, now: "2026-09-29T10:00")
        let early = plan([item], now: "2026-09-29T10:00")
        let late = plan([item], now: "2026-09-29T15:20")
        for result in [early, late] {
            for note in itemNotifications(result, item.id) where note.kind == .nag || note.kind == .first {
                XCTAssertEqual(note.id, NotificationID.chain(item.id, note.attempt))
                XCTAssertLessThan(note.attempt, fullChain.count)
                if note.attempt < fullChain.count {
                    XCTAssertEqual(note.fireDate, fullChain[note.attempt], "k = \(note.attempt)")
                }
            }
        }
        let lateNotes = itemNotifications(late, item.id)
        let lateIDs = Set(lateNotes.map { $0.id })
        for k in 0...2 {
            XCTAssertFalse(lateIDs.contains(NotificationID.chain(item.id, k)), "k = \(k) is in the past")
        }
        XCTAssertTrue(lateIDs.contains(NotificationID.chain(item.id, 3)))
        for note in itemNotifications(early, item.id) where note.rule == .once {
            if let again = lateNotes.first(where: { $0.id == note.id }) {
                XCTAssertEqual(again.fireDate, note.fireDate)
            }
        }
    }

    func testSnoozeRestartsChainAtZero() {
        var item = makeItem(1, due: "2026-09-29T15:00")
        item.snoozedUntil = d("2026-09-29T15:40")
        item.snoozeCount = 1
        let result = plan([item], now: "2026-09-29T15:10")
        let notes = oneShots(itemNotifications(result, item.id))
        guard notes.count >= 2 else {
            XCTFail("expected the re-based chain")
            return
        }
        XCTAssertEqual(notes[0].id, NotificationID.chain(item.id, 0))
        XCTAssertEqual(notes[0].kind, PlannedNotification.Kind.first)
        XCTAssertEqual(f(notes[0].fireDate), "2026-09-29T15:40")
        XCTAssertEqual(notes[1].id, NotificationID.chain(item.id, 1))
        XCTAssertEqual(f(notes[1].fireDate), "2026-09-29T15:50")
    }

    func testIdenticalInputGivesIdenticalOutput() {
        var settings = AppSettings()
        settings.muteUntil = d("2026-09-29T10:30")
        var project = Project(name: "Arka Cep", createdAt: d("2026-09-01T09:00"))
        project.id = uuid(900)
        var high = makeItem(1, priority: .high, due: "2026-09-29T15:00")
        high.projectID = project.id
        high.originalText = "Salı günü teklif konusunu bana saat 3'te hatırlat"
        let critical = makeItem(2, title: "Pano", priority: .critical, due: "2026-09-29T11:00")
        let overdue = makeItem(3, title: "Ahmet'i ara", due: "2026-09-28T09:00")
        let waiting = makeItem(4, title: "Teklif", kind: .waiting, due: "2026-09-30T10:00", hasTime: false)
        var event = makeItem(5, title: "ABB ile toplantı", due: "2026-10-01T14:00")
        event.isEvent = true
        event.leadTimesMinutes = [15]
        var daily = makeItem(6, title: "İlaç al", due: "2026-09-29T09:00")
        daily.recurrence = Recurrence(frequency: .daily)
        let plainNote = makeItem(7, title: "Not", kind: .note, due: nil)
        let items = [high, critical, overdue, waiting, event, daily, plainNote]
        let input = PlanInput(items: items, projects: [project], places: [], settings: settings,
                              now: d("2026-09-29T10:00"), calendar: calendar, signingExpiry: d("2026-10-01T12:00"))
        let first = NagPlanner.plan(input)
        let second = NagPlanner.plan(input)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.notifications.isEmpty)
        for planned in first.notifications {
            XCTAssertEqual(planned.fingerprint, planned.computeFingerprint())
        }
        assertPlanOrder(first)
        assertUniqueIDs(first)
        XCTAssertLessThanOrEqual(first.notifications.count, 64)
        XCTAssertTrue(first.notifications.contains { $0.kind == .preAlert && $0.itemID == event.id })
        XCTAssertTrue(first.notifications.contains { $0.categoryID == NotificationCategoryID.followUp })
    }

    // MARK: - Takip and events

    func testTakipPlanUsesFollowUpCategoryAndWorkdays() {
        let waiting = makeItem(1, title: "Hakan teklif gönderecek", kind: .waiting, due: "2026-10-02T16:00",
                               hasTime: false)
        let result = plan([waiting], now: "2026-10-02T10:00")
        let notes = oneShots(itemNotifications(result, waiting.id))
        let expected: [(Int, String)] = [
            (0, "2026-10-02T16:00"), (1, "2026-10-05T16:00"), (2, "2026-10-06T16:00"), (3, "2026-10-07T16:00"),
            (4, "2026-10-08T16:00"), (5, "2026-10-09T16:00"), (6, "2026-10-12T16:00"), (7, "2026-10-13T16:00")
        ]
        XCTAssertEqual(notes.map { $0.id }, expected.map { NotificationID.chain(waiting.id, $0.0) })
        XCTAssertEqual(fs(notes.map { $0.fireDate }), expected.map { $0.1 })
        for note in notes {
            XCTAssertEqual(note.categoryID, NotificationCategoryID.followUp)
            XCTAssertFalse(isWeekend(note.fireDate))
        }
    }

    func testEventsNeverNag() {
        var event = makeItem(1, title: "ABB ile toplantı", priority: .high, due: "2026-10-01T14:00")
        event.isEvent = true
        event.leadTimesMinutes = [15]
        var audit = makeItem(2, title: "Denetim", priority: .critical, due: "2026-10-01T16:00")
        audit.isEvent = true
        let result = plan([event, audit], now: "2026-09-29T10:00")
        let notes = itemNotifications(result, event.id)
        XCTAssertEqual(notes.map { $0.kind }, [PlannedNotification.Kind.preAlert, PlannedNotification.Kind.first])
        XCTAssertEqual(notes.map { $0.id }, [NotificationID.preAlert(event.id, minutes: 15),
                                             NotificationID.chain(event.id, 0)])
        XCTAssertEqual(fs(notes.map { $0.fireDate }), ["2026-10-01T13:45", "2026-10-01T14:00"])
        XCTAssertEqual(notes.first?.categoryID, NotificationCategoryID.preAlert)
        XCTAssertEqual(notes.last?.categoryID, NotificationCategoryID.item)
        for item in [event, audit] {
            let own = itemNotifications(result, item.id)
            XCTAssertFalse(own.contains { $0.kind == .nag || $0.kind == .longTail }, item.title)
        }
        // An event that already started produces nothing.
        let started = plan([event], now: "2026-10-01T14:30")
        XCTAssertTrue(itemNotifications(started, event.id).isEmpty)
    }

    func testPreAlertsNeedLeadAndUsePreCategory() {
        var item = makeItem(1, due: "2026-09-29T15:00")
        item.leadTimesMinutes = [30, 1440]
        let result = plan([item], now: "2026-09-29T10:00")
        let pre = notification(result, id: NotificationID.preAlert(item.id, minutes: 30))
        XCTAssertEqual(pre?.kind, PlannedNotification.Kind.preAlert)
        XCTAssertEqual(pre.map { f($0.fireDate) }, "2026-09-29T14:30")
        XCTAssertEqual(pre?.categoryID, NotificationCategoryID.preAlert)
        XCTAssertEqual(pre?.threadID, NotificationID.thread(item.id))
        XCTAssertNil(notification(result, id: NotificationID.preAlert(item.id, minutes: 1440)), "already past")
    }

    // MARK: - immediateRequests (05b B1)

    func testImmediateRequestsMatchSingleItemPlan() {
        let normal = makeItem(1, due: "2026-09-29T15:00")
        let high = makeItem(2, priority: .high, due: "2026-09-29T15:00")
        var snoozed = makeItem(3, due: "2026-09-29T09:00")
        snoozed.snoozedUntil = d("2026-09-29T10:10")
        snoozed.snoozeCount = 1
        for item in [normal, high, snoozed] {
            let input = makeInput([item], now: "2026-09-29T10:00")
            let planned = oneShots(itemNotifications(NagPlanner.plan(input), item.id))
            for limit in [1, 2, 5] {
                let immediate = NagPlanner.immediateRequests(for: item, input: input, limit: limit)
                let expected = Array(planned.prefix(limit))
                XCTAssertEqual(immediate.map { $0.id }, expected.map { $0.id }, "\(item.title) limit \(limit)")
                XCTAssertEqual(immediate.map { $0.fingerprint }, expected.map { $0.fingerprint },
                               "\(item.title) limit \(limit)")
            }
            XCTAssertTrue(NagPlanner.immediateRequests(for: item, input: input, limit: 0).isEmpty)
        }
        var done = normal
        done.status = .done
        XCTAssertTrue(NagPlanner.immediateRequests(for: done, input: makeInput([done], now: "2026-09-29T10:00"),
                                                   limit: 2).isEmpty)
    }

    // MARK: - Badge

    func testBadgesAreProjectedPerFireDate() {
        let item = makeItem(1, due: "2026-09-29T15:00")
        let result = plan([item], now: "2026-09-29T10:00")
        XCTAssertEqual(result.badgeNow, 0)
        XCTAssertEqual(notification(result, id: NotificationID.chain(item.id, 0))?.badge, 1)
        for note in result.notifications where note.rule != .once {
            XCTAssertNil(note.badge)
        }
        var settings = AppSettings()
        settings.badgeMode = .off
        let off = plan([item], now: "2026-09-29T16:00", settings: settings)
        XCTAssertEqual(off.badgeNow, 0)
        for note in off.notifications where note.rule == .once {
            XCTAssertEqual(note.badge, 0)
        }
        XCTAssertEqual(NagPlanner.badgeCount(items: [item], at: d("2026-09-29T16:00"), settings: AppSettings(),
                                             calendar: calendar), 1)
    }

    // MARK: - Helpers used by actions and UI

    func testSnoozeTargetHelpers() {
        let settings = AppSettings()
        XCTAssertEqual(f(NagPlanner.tomorrowMorning(after: d("2026-09-27T10:00"), settings: settings,
                                                    calendar: calendar)), "2026-09-28T08:30")
        XCTAssertEqual(f(NagPlanner.tomorrowMorning(after: d("2026-09-28T04:00"), settings: settings,
                                                    calendar: calendar)), "2026-09-28T08:30")
        XCTAssertEqual(f(NagPlanner.tomorrowMorning(after: d("2026-10-02T20:00"), settings: settings,
                                                    calendar: calendar)), "2026-10-03T09:00")
        XCTAssertEqual(f(NagPlanner.followUpAsk(after: d("2026-10-02T10:00"), workdays: 1, settings: settings,
                                                calendar: calendar)), "2026-10-05T16:00")
        XCTAssertEqual(f(NagPlanner.followUpAsk(after: d("2026-10-02T10:00"), workdays: 2, settings: settings,
                                                calendar: calendar)), "2026-10-06T16:00")
        XCTAssertEqual(NagPlanner.thisEvening(now: d("2026-09-29T17:00"), settings: settings, calendar: calendar)
                        .map { f($0) }, "2026-09-29T19:00")
        XCTAssertNil(NagPlanner.thisEvening(now: d("2026-09-29T18:45"), settings: settings, calendar: calendar))
        XCTAssertEqual(f(NagPlanner.nextMonday(now: d("2026-09-28T10:00"), settings: settings, calendar: calendar)),
                       "2026-10-05T08:30")
        XCTAssertEqual(f(NagPlanner.nextMonday(now: d("2026-09-27T10:00"), settings: settings, calendar: calendar)),
                       "2026-09-28T08:30")
        XCTAssertEqual(f(NagPlanner.muteUntilWorkEnd(now: d("2026-09-29T10:00"), settings: settings,
                                                     calendar: calendar)), "2026-09-29T18:00")
        XCTAssertEqual(f(NagPlanner.muteUntilWorkEnd(now: d("2026-09-29T19:00"), settings: settings,
                                                     calendar: calendar)), "2026-09-29T21:00")
        XCTAssertEqual(f(NagPlanner.muteUntilWorkEnd(now: d("2026-10-03T10:00"), settings: settings,
                                                     calendar: calendar)), "2026-10-03T12:00")
    }
}
