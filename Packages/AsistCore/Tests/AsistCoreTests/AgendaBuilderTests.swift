import Foundation
import XCTest
@testable import AsistCore

/// 04 §3.5.5: Today sections, spoken answers (03 §5.9), briefing with overdue titles (05b B3), end-of-day candidates
/// (05b B6), the open-items text (05b A1) and the notification copy table (03 §3.2 as amended by 04 §5.5).
/// Reference instant: Sun 2026-09-27 10:30 (Europe/Istanbul).
final class AgendaBuilderTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let now = TestSupport.date("2026-09-27T10:30")
    private let settings = AppSettings()

    private func makeItem(_ kind: ItemKind, _ title: String, due: String? = nil, hasTime: Bool = true,
                          priority: Priority = .normal, person: String? = nil, projectID: UUID? = nil,
                          original: String? = nil, created: String = "2026-09-27T10:30") -> Item {
        Item(kind: kind, title: title, originalText: original, priority: priority,
             dueDate: due.map { TestSupport.date($0) }, hasTime: hasTime, person: person, projectID: projectID,
             createdAt: TestSupport.date(created))
    }

    private struct Fixture {
        var overdueNormal: Item
        var overdueCritical: Item
        var todayTimed: Item
        var todayUntimed: Item
        var followUp: Item
        var tomorrow: Item
        var tuesday: Item
        var note: Item
        var unscheduled: Item
        var doneThisWeek: Item
        var doneLastWeek: Item

        var all: [Item] {
            [overdueNormal, overdueCritical, todayTimed, todayUntimed, followUp, tomorrow, tuesday, note,
             unscheduled, doneThisWeek, doneLastWeek]
        }
    }

    private func fixture() -> Fixture {
        var doneThisWeek = makeItem(.task, "Pano şeması", due: "2026-09-25T09:00")
        doneThisWeek.status = .done
        doneThisWeek.completedAt = TestSupport.date("2026-09-25T11:00")
        var doneLastWeek = makeItem(.task, "Eski iş", due: "2026-09-18T09:00")
        doneLastWeek.status = .done
        doneLastWeek.completedAt = TestSupport.date("2026-09-20T18:00")
        return Fixture(
            overdueNormal: makeItem(.reminder, "Ahmet'i ara", due: "2026-09-26T15:00", person: "Ahmet"),
            overdueCritical: makeItem(.reminder, "Pano ısınması", due: "2026-09-27T09:00", priority: .critical),
            todayTimed: makeItem(.reminder, "ABB toplantısı", due: "2026-09-27T14:00"),
            todayUntimed: makeItem(.task, "Sipariş formu", due: "2026-09-27T09:00", hasTime: false),
            followUp: makeItem(.waiting, "I/O listesi", due: "2026-09-27T10:00", hasTime: false, person: "Mehmet"),
            tomorrow: makeItem(.reminder, "Haftalık rapor", due: "2026-09-28T09:00"),
            tuesday: makeItem(.reminder, "Teklif konusu", due: "2026-09-29T15:00"),
            note: makeItem(.note, "Işık perdesi notu"),
            unscheduled: makeItem(.task, "Kalibrasyon"),
            doneThisWeek: doneThisWeek,
            doneLastWeek: doneLastWeek)
    }

    // MARK: - Snapshot

    func testSnapshotSections() {
        let f = fixture()
        var review = f.tuesday
        review.needsReview = true
        var items = f.all
        items[6] = review
        let snap = AgendaBuilder.snapshot(items: items, now: now, settings: settings, calendar: calendar)

        XCTAssertEqual(snap.overdue.map { $0.id }, [f.overdueCritical.id, f.overdueNormal.id])
        XCTAssertEqual(snap.overdueCount, 2)
        XCTAssertEqual(snap.today.map { $0.id }, [f.todayTimed.id, f.todayUntimed.id])
        XCTAssertEqual(snap.followUps.map { $0.id }, [f.followUp.id])
        XCTAssertEqual(snap.review.map { $0.id }, [f.tuesday.id])
        XCTAssertEqual(snap.upcomingTotal, 2)
        XCTAssertEqual(snap.upcoming.count, 2)
        XCTAssertEqual(snap.upcoming.first?.title, "Yarın")
        XCTAssertEqual(snap.upcoming.first?.day, TestSupport.date("2026-09-28T00:00"))
        XCTAssertEqual(snap.upcoming.first?.items.map { $0.id }, [f.tomorrow.id])
        XCTAssertEqual(snap.unscheduled.map { $0.id }, [f.unscheduled.id])
        XCTAssertEqual(snap.doneThisWeek, 1)
    }

    func testUpcomingIsLimitedToFiveRowsAndSevenDays() {
        var items: [Item] = []
        let dues = ["2026-09-28T09:00", "2026-09-28T11:00", "2026-09-29T09:00", "2026-09-29T10:00",
                    "2026-09-30T09:00", "2026-10-01T09:00", "2026-10-04T09:00", "2026-10-05T09:00"]
        for (index, due) in dues.enumerated() {
            items.append(makeItem(.reminder, "İş " + String(index), due: due))
        }
        let snap = AgendaBuilder.snapshot(items: items, now: now, settings: settings, calendar: calendar)
        XCTAssertEqual(snap.upcomingTotal, 7)          // 10-05 is 8 days ahead → outside YAKLAŞAN
        let rows = snap.upcoming.reduce(0) { $0 + $1.items.count }
        XCTAssertEqual(rows, 5)
        XCTAssertEqual(snap.upcoming.map { $0.items.count }, [2, 2, 1])
    }

    func testEventsAreNeverOverdue() {
        var event = makeItem(.reminder, "ABB toplantısı", due: "2026-09-27T09:00")
        event.isEvent = true
        let snap = AgendaBuilder.snapshot(items: [event], now: now, settings: settings, calendar: calendar)
        XCTAssertTrue(snap.overdue.isEmpty)
        XCTAssertEqual(snap.today.map { $0.id }, [event.id])
    }

    // MARK: - Spoken answers

    func testTodaySpoken() {
        let f = fixture()
        let answer = AgendaBuilder.todaySpoken(items: f.all, projects: [], now: now, settings: settings, calendar: calendar)
        XCTAssertEqual(answer.title, "Bugünün ajandası")
        XCTAssertEqual(answer.text,
                       "Bugün beş işin var. İki geciken iş: Pano ısınması; Ahmet'i ara. "
                       + "Sıradaki, öğleden sonra ikide: ABB toplantısı. Gün içinde: Sipariş formu. "
                       + "Ayrıca bir takip var: Mehmet, I/O listesi.")
        XCTAssertEqual(answer.itemIDs, [f.overdueCritical.id, f.overdueNormal.id, f.todayTimed.id,
                                        f.todayUntimed.id, f.followUp.id])
    }

    func testTodaySpokenLimitsToFiveItems() {
        var items: [Item] = []
        for hour in 11...17 {
            items.append(makeItem(.reminder, "İş " + String(hour), due: "2026-09-27T" + String(hour) + ":00"))
        }
        let answer = AgendaBuilder.todaySpoken(items: items, projects: [], now: now, settings: settings, calendar: calendar)
        XCTAssertTrue(answer.text.hasPrefix("Bugün yedi işin var. Sıradaki, sabah on birde: İş 11."))
        XCTAssertTrue(answer.text.hasSuffix("Diğerleri ekranda."))
        XCTAssertEqual(answer.itemIDs.count, 7)
        XCTAssertFalse(answer.text.contains("İş 16"))
    }

    func testTodaySpokenEmpty() {
        let answer = AgendaBuilder.todaySpoken(items: [], projects: [], now: now, settings: settings, calendar: calendar)
        XCTAssertEqual(answer.text, "Bugün planlı bir işin yok.")
        XCTAssertEqual(answer.itemIDs, [])
    }

    func testOverdueSpoken() {
        let f = fixture()
        let answer = AgendaBuilder.overdueSpoken(items: f.all, now: now, settings: settings, calendar: calendar)
        XCTAssertEqual(answer.title, "Gecikenler")
        XCTAssertEqual(answer.text, "İki geciken iş var: Pano ısınması; Ahmet'i ara.")
        XCTAssertEqual(AgendaBuilder.overdueSpoken(items: [], now: now, settings: settings, calendar: calendar).text,
                       "Geciken işin yok.")
    }

    func testAnswerScopes() {
        let f = fixture()
        func answer(_ command: ParsedCommand, projects: [Project] = [], items: [Item]? = nil) -> SpokenAnswer {
            AgendaBuilder.answer(to: command, items: items ?? f.all, projects: projects, now: now,
                                 settings: settings, calendar: calendar)
        }
        let tomorrow = answer(ParsedCommand(type: .query, scope: .tomorrow))
        XCTAssertEqual(tomorrow.title, "Yarının ajandası")
        XCTAssertEqual(tomorrow.text, "Yarın bir işin var. Sabah dokuzda: Haftalık rapor.")

        let tuesday = answer(ParsedCommand(type: .query, scope: .date, date: TestSupport.date("2026-09-29T00:00")))
        XCTAssertEqual(tuesday.text, "Salı günü bir işin var. Öğleden sonra üçte: Teklif konusu.")
        XCTAssertTrue(tuesday.title.hasSuffix("ajandası"))

        let waiting = answer(ParsedCommand(type: .query, scope: .waiting))
        XCTAssertEqual(waiting.title, "Beklenenler")
        XCTAssertEqual(waiting.text, "Bir takip var: Mehmet, I/O listesi.")

        let overdue = answer(ParsedCommand(type: .query, scope: .overdue))
        XCTAssertEqual(overdue.text, "İki geciken iş var: Pano ısınması; Ahmet'i ara.")

        let notes = answer(ParsedCommand(type: .query, scope: .notes))
        XCTAssertEqual(notes.text, "Bir notun var: Işık perdesi notu.")

        let week = answer(ParsedCommand(type: .query, scope: .nextWeek))
        XCTAssertEqual(week.text,
                       "Gelecek hafta iki işin var. Yarın sabah dokuzda: Haftalık rapor. "
                       + "Salı öğleden sonra üçte: Teklif konusu.")

        let today = answer(ParsedCommand(type: .query, scope: nil))
        XCTAssertEqual(today.title, "Bugünün ajandası")
    }

    func testAnswerFilters() {
        let f = fixture()
        let project = Project(name: "Arka Cep", aliases: ["Kocaeli"], createdAt: TestSupport.date("2026-09-01T09:00"))
        var tuesday = f.tuesday
        tuesday.projectID = project.id
        var items = f.all
        items[6] = tuesday

        let byProject = AgendaBuilder.answer(to: ParsedCommand(type: .query, scope: .all, project: "kocaeli"),
                                             items: items, projects: [project], now: now, settings: settings,
                                             calendar: calendar)
        XCTAssertEqual(byProject.title, "Proje: Arka Cep")
        XCTAssertEqual(byProject.text, "Arka Cep projesinde bir açık kayıt var: Teklif konusu.")
        XCTAssertEqual(byProject.itemIDs, [tuesday.id])

        let byPerson = AgendaBuilder.answer(to: ParsedCommand(type: .query, scope: .all, person: "Ahmet"),
                                            items: items, projects: [project], now: now, settings: settings,
                                            calendar: calendar)
        XCTAssertEqual(byPerson.text, "Ahmet ile ilgili bir açık kayıt var: Ahmet'i ara.")

        let missing = AgendaBuilder.answer(to: ParsedCommand(type: .query, scope: .tomorrow, queryText: "toplantı"),
                                           items: items, projects: [project], now: now, settings: settings,
                                           calendar: calendar)
        XCTAssertEqual(missing.text,
                       "“toplantı” ile ilgili bir kayıt bulamadım. Yarın bir işin var. Sabah dokuzda: Haftalık rapor.")

        let found = AgendaBuilder.answer(to: ParsedCommand(type: .query, scope: .tomorrow, queryText: "rapor"),
                                         items: items, projects: [project], now: now, settings: settings,
                                         calendar: calendar)
        XCTAssertEqual(found.text, "Yarın bir işin var. Sabah dokuzda: Haftalık rapor.")
    }

    // MARK: - Briefing (05b B3)

    func testBriefingListsOverdueTitlesAtFireTime() throws {
        let f = fixture()
        let items = [f.overdueNormal, f.tomorrow, f.tuesday]
        let monday = try XCTUnwrap(AgendaBuilder.briefing(items: items, at: TestSupport.date("2026-09-28T08:00"),
                                                          settings: settings, calendar: calendar))
        XCTAssertEqual(monday.title, "Günaydın — bugün 2 iş")
        XCTAssertEqual(monday.subtitle, "1 geciken")
        XCTAssertEqual(monday.body, "Geciken: Ahmet'i ara\nBugün 1 iş · İlk: 09:00 Haftalık rapor")

        // Projected two days later without any app activity: everything is overdue.
        let wednesday = try XCTUnwrap(AgendaBuilder.briefing(items: items, at: TestSupport.date("2026-09-30T08:00"),
                                                             settings: settings, calendar: calendar))
        XCTAssertEqual(wednesday.title, "Günaydın — bugün 3 iş")
        XCTAssertEqual(wednesday.body, "Geciken: Ahmet'i ara, Haftalık rapor, Teklif konusu\nBugün için yeni iş yok")
    }

    func testBriefingOverflowAndName() throws {
        var items: [Item] = []
        for day in 21...24 {
            items.append(makeItem(.reminder, "Eski " + String(day), due: "2026-09-" + String(day) + "T09:00"))
        }
        var named = settings
        named.userName = "Gökhan"
        let text = try XCTUnwrap(AgendaBuilder.briefing(items: items, at: TestSupport.date("2026-09-28T08:00"),
                                                        settings: named, calendar: calendar))
        XCTAssertEqual(text.title, "Günaydın, Gökhan — bugün 4 iş")
        XCTAssertTrue(text.body.hasPrefix("Geciken: Eski 21, Eski 22, Eski 23 +1"))
    }

    func testBriefingWhenEmpty() {
        let fire = TestSupport.date("2026-09-28T08:00")
        XCTAssertNil(AgendaBuilder.briefing(items: [], at: fire, settings: settings, calendar: calendar))
        var always = settings
        always.briefingWhenEmpty = true
        XCTAssertNotNil(AgendaBuilder.briefing(items: [], at: fire, settings: always, calendar: calendar))
    }

    // MARK: - End of day (05b B6)

    private func endOfDayItems() -> [Item] {
        var recurring = makeItem(.reminder, "İlacımı iç", due: "2026-09-28T09:00")
        recurring.recurrence = Recurrence(frequency: .daily)
        var event = makeItem(.reminder, "Toplantı", due: "2026-09-28T16:00")
        event.isEvent = true
        return [
            makeItem(.reminder, "Ahmet'i ara", due: "2026-09-26T15:00"),
            makeItem(.reminder, "Rapor", due: "2026-09-28T14:00"),
            makeItem(.task, "Sipariş formu", due: "2026-09-28T09:00", hasTime: false),
            makeItem(.reminder, "Ekmek al", due: "2026-09-28T18:00"),
            makeItem(.note, "Not"),
            recurring,
            event
        ]
    }

    func testEndOfDayCandidatesExcludeLaterTodayRecurringAndEvents() {
        let items = endOfDayItems()
        let fire = TestSupport.date("2026-09-28T17:45")
        let candidates = AgendaBuilder.endOfDayCandidates(items: items, now: fire, calendar: calendar)
        XCTAssertEqual(candidates.map { $0.title }, ["Ahmet'i ara", "Sipariş formu", "Rapor"])
    }

    func testEndOfDayNotification() throws {
        let items = endOfDayItems()
        let text = try XCTUnwrap(AgendaBuilder.endOfDay(items: items, at: TestSupport.date("2026-09-28T17:45"),
                                                        settings: settings, calendar: calendar))
        XCTAssertEqual(text.title, "Gün sonu — 3 iş açık kaldı")
        XCTAssertEqual(text.body, "Yarına taşıyayım mı? Ahmet'i ara, Sipariş formu, Rapor\nBu akşam: 18:00 Ekmek al")

        let friday = [makeItem(.task, "Sipariş formu", due: "2026-10-02T09:00", hasTime: false)]
        let fridayText = try XCTUnwrap(AgendaBuilder.endOfDay(items: friday, at: TestSupport.date("2026-10-02T17:45"),
                                                              settings: settings, calendar: calendar))
        XCTAssertTrue(fridayText.body.hasPrefix("Sonraki iş gününe taşıyayım mı? Sipariş formu"))

        let later = [makeItem(.reminder, "Ekmek al", due: "2026-09-28T18:00")]
        XCTAssertNil(AgendaBuilder.endOfDay(items: later, at: TestSupport.date("2026-09-28T17:45"),
                                            settings: settings, calendar: calendar))
    }

    func testMovedToTomorrowSkipsWeekend() {
        let fire = TestSupport.date("2026-10-02T17:45")
        var timed = makeItem(.reminder, "Rapor", due: "2026-10-02T15:00")
        timed.snoozedUntil = TestSupport.date("2026-10-02T16:10")
        timed.snoozeCount = 2
        timed.hasTime = true
        let moved = AgendaBuilder.movedToTomorrow(timed, now: fire, settings: settings, calendar: calendar)
        XCTAssertEqual(moved.dueDate, TestSupport.date("2026-10-05T16:10"))
        XCTAssertTrue(moved.hasTime)
        XCTAssertNil(moved.snoozedUntil)
        XCTAssertEqual(moved.snoozeCount, 0)
        XCTAssertEqual(moved.history.last?.event, .movedEndOfDay)
        XCTAssertEqual(moved.updatedAt, fire)

        let untimed = makeItem(.task, "Sipariş formu", due: "2026-10-02T09:00", hasTime: false)
        let movedUntimed = AgendaBuilder.movedToTomorrow(untimed, now: fire, settings: settings, calendar: calendar)
        XCTAssertEqual(movedUntimed.dueDate, TestSupport.date("2026-10-05T09:00"))
        XCTAssertFalse(movedUntimed.hasTime)

        var calendarDays = settings
        calendarDays.moveSkipsWeekend = false
        let saturday = AgendaBuilder.movedToTomorrow(untimed, now: fire, settings: calendarDays, calendar: calendar)
        XCTAssertEqual(saturday.dueDate, TestSupport.date("2026-10-03T09:00"))
    }

    // MARK: - Open-items text (05b A1)

    func testOpenItemsText() {
        let project = Project(name: "Arka Cep", createdAt: TestSupport.date("2026-09-01T09:00"))
        let items = [
            makeItem(.reminder, "Teklif konusu", due: "2026-09-29T15:00", priority: .high, person: "Ahmet",
                     projectID: project.id),
            makeItem(.task, "Kalibrasyon"),
            makeItem(.reminder, "Ahmet'i ara", due: "2026-09-26T15:00"),
            makeItem(.task, "Sipariş formu", due: "2026-09-28T09:00", hasTime: false),
            makeItem(.note, "Gizli not")
        ]
        let text = AgendaBuilder.openItemsText(items: items, projects: [project], now: now, calendar: calendar)
        let expected = [
            "Asist — açık işler (27 Eylül 2026 10:30)",
            "GECİKEN · Cumartesi 26.09 15:00 · Ahmet'i ara",
            "Pazartesi 28.09 · Sipariş formu",
            "Salı 29.09 15:00 · Teklif konusu · Ahmet · Arka Cep · Önemli",
            "Zamanı belirsiz · Kalibrasyon"
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(text, expected)
    }

    // MARK: - Notification copy (03 §3.2, 04 §5.5)

    private var teklif: Item {
        makeItem(.reminder, "Teklif konusu", due: "2026-09-29T15:00", priority: .high,
                 original: "Salı günü teklif konusunu bana saat 3'te hatırlat")
    }

    func testFirstAlertCopy() {
        let item = teklif
        let text = NotificationCopy.itemContent(item: item, projectName: "Arka Cep", attempt: 0,
                                                fireDate: TestSupport.date("2026-09-29T15:00"),
                                                nextFireDate: TestSupport.date("2026-09-29T15:05"),
                                                isLastOfDay: false, calendar: calendar)
        XCTAssertEqual(text.title, "Teklif konusu")
        XCTAssertEqual(text.subtitle, "Salı 15:00 · Arka Cep · Önemli")
        XCTAssertEqual(text.body, "“Salı günü teklif konusunu bana saat 3'te hatırlat”\n"
                       + "“✓ Yaptım” diyene kadar hatırlatmaya devam edeceğim.")
    }

    func testNagCopy() {
        let item = teklif
        let nag = NotificationCopy.itemContent(item: item, projectName: nil, attempt: 2,
                                               fireDate: TestSupport.date("2026-09-29T15:30"),
                                               nextFireDate: TestSupport.date("2026-09-29T16:00"),
                                               isLastOfDay: false, calendar: calendar)
        XCTAssertEqual(nag.subtitle, "30 dakikadır bekliyor · 3. hatırlatma")
        XCTAssertEqual(nag.body, "“Salı günü teklif konusunu bana saat 3'te hatırlat”\nSonraki: 16:00")

        let hours = NotificationCopy.itemContent(item: item, projectName: nil, attempt: 5,
                                                 fireDate: TestSupport.date("2026-09-29T17:00"),
                                                 nextFireDate: TestSupport.date("2026-09-30T08:30"),
                                                 isLastOfDay: false, calendar: calendar)
        XCTAssertEqual(hours.subtitle, "2 saattir bekliyor · 6. hatırlatma")
        XCTAssertTrue(hours.body.hasSuffix("Sonraki: Yarın 08:30"))

        let days = NotificationCopy.itemContent(item: item, projectName: nil, attempt: 12,
                                                fireDate: TestSupport.date("2026-10-01T08:30"),
                                                nextFireDate: TestSupport.date("2026-10-01T09:30"),
                                                isLastOfDay: false, calendar: calendar)
        XCTAssertEqual(days.subtitle, "2 gündür bekliyor · 13. hatırlatma")

        var critical = item
        critical.priority = .critical
        let criticalNag = NotificationCopy.itemContent(item: critical, projectName: nil, attempt: 1,
                                                       fireDate: TestSupport.date("2026-09-29T15:05"),
                                                       nextFireDate: TestSupport.date("2026-09-29T15:10"),
                                                       isLastOfDay: false, calendar: calendar)
        XCTAssertEqual(criticalNag.subtitle, "KRİTİK · 5 dakikadır bekliyor · 2. hatırlatma")
    }

    func testSpecialSubtitlesAndLastLine() {
        var snoozed = teklif
        snoozed.snoozeCount = 3
        snoozed.snoozedUntil = TestSupport.date("2026-09-29T17:00")
        let snoozedText = NotificationCopy.itemContent(item: snoozed, projectName: nil, attempt: 0,
                                                       fireDate: TestSupport.date("2026-09-29T17:00"),
                                                       nextFireDate: TestSupport.date("2026-09-29T17:05"),
                                                       isLastOfDay: false, calendar: calendar)
        XCTAssertEqual(snoozedText.subtitle, "3. erteleme · başka bir gün mü?")

        let last = NotificationCopy.itemContent(item: teklif, projectName: nil, attempt: 9,
                                                fireDate: TestSupport.date("2026-09-29T17:30"),
                                                nextFireDate: TestSupport.date("2026-09-30T08:30"),
                                                isLastOfDay: true, calendar: calendar)
        XCTAssertEqual(last.subtitle, "Bugünlük son hatırlatma · yarın sabah yine")

        let finalText = NotificationCopy.itemContent(item: teklif, projectName: nil, attempt: 4,
                                                 fireDate: TestSupport.date("2026-09-29T16:00"),
                                                 nextFireDate: nil, isLastOfDay: false, calendar: calendar)
        XCTAssertTrue(finalText.body.hasSuffix("Asist'i bir kez açarsan hatırlatmaya devam ederim."))
    }

    func testTitleTruncationAndNotesFallback() {
        var item = makeItem(.task, String(repeating: "Uzun başlık kelimesi ", count: 6), due: "2026-09-29T15:00")
        item.notes = "Birinci satır\n\nİkinci satır\nÜçüncü satır"
        let text = NotificationCopy.itemContent(item: item, projectName: nil, attempt: 0,
                                                fireDate: TestSupport.date("2026-09-29T15:00"),
                                                nextFireDate: TestSupport.date("2026-09-29T15:10"),
                                                isLastOfDay: false, calendar: calendar)
        XCTAssertLessThanOrEqual(text.title.count, 60)
        XCTAssertTrue(text.title.hasSuffix("…"))
        XCTAssertTrue(text.body.hasPrefix("Birinci satır\nİkinci satır\n"))
    }

    func testFollowUpCopy() {
        let waiting = makeItem(.waiting, "I/O listesi", due: "2026-09-29T10:00", hasTime: false, person: "Mehmet")
        let first = NotificationCopy.followUpContent(item: waiting, attempt: 0,
                                                     fireDate: TestSupport.date("2026-09-29T10:00"), calendar: calendar)
        XCTAssertEqual(first.title, "Takip · Mehmet: I/O listesi")
        XCTAssertEqual(first.subtitle, "Geldi mi? · 2 gündür bekliyor")

        let again = NotificationCopy.followUpContent(item: waiting, attempt: 1,
                                                     fireDate: TestSupport.date("2026-09-30T16:00"), calendar: calendar)
        XCTAssertEqual(again.subtitle, "2. kez soruyorum — geldi mi?")

        var deadline = makeItem(.waiting, "Çizimler", due: "2026-10-02T16:00")
        deadline.person = nil
        let withDeadline = NotificationCopy.followUpContent(item: deadline, attempt: 0,
                                                            fireDate: TestSupport.date("2026-10-02T16:00"),
                                                            calendar: calendar)
        XCTAssertEqual(withDeadline.title, "Takip: Çizimler")
        XCTAssertTrue(withDeadline.subtitle.hasPrefix("Geldi mi? · Son tarih: "))
    }

    func testEventAndPreAlertCopy() {
        var event = makeItem(.reminder, "ABB ile toplantı", due: "2026-10-01T14:00")
        event.isEvent = true
        let start = NotificationCopy.eventContent(item: event, projectName: "Arka Cep", calendar: calendar)
        XCTAssertEqual(start.title, "ABB ile toplantı")
        XCTAssertEqual(start.subtitle, "Perşembe 14:00 · Arka Cep")

        let pre = NotificationCopy.preAlertContent(item: event, projectName: "Arka Cep", leadMinutes: 30, calendar: calendar)
        XCTAssertEqual(pre.title, "30 dakika sonra: ABB ile toplantı")
        XCTAssertEqual(pre.subtitle, "Perşembe 14:00 · Arka Cep")
    }

    func testStaticCopy() {
        let item = teklif
        XCTAssertEqual(NotificationCopy.longTailContent(item: item, projectName: nil).subtitle,
                       "Hâlâ açık · her sabah soracağım")
        var daily = item
        daily.recurrence = Recurrence(frequency: .daily)
        let carrier = NotificationCopy.recurrenceCarrierContent(item: daily, projectName: nil, calendar: calendar)   // WP0-FIX: D29 injected calendar
        XCTAssertTrue(carrier.subtitle.hasPrefix("Her gün"))
        XCTAssertTrue(carrier.subtitle.contains("tekrarlayan"))
        XCTAssertEqual(NotificationCopy.budgetSentinelLine(extraCount: 3),
                       "+3 hatırlatma daha — planı tazelemek için Asist'i aç")
        let horizon = NotificationCopy.horizonSentinelContent(openCount: 4)
        XCTAssertEqual(horizon.title, "Asist'i bir kez aç")
        XCTAssertEqual(horizon.subtitle, "4 açık iş var")
        XCTAssertEqual(NotificationCopy.movedFeedbackContent(count: 3).body,
                       "3 iş sonraki iş gününe taşındı. Geri almak için dokun.")
        XCTAssertEqual(NotificationCopy.backupContent().title, "Yedek zamanı")
        XCTAssertEqual(NotificationCopy.testContent().title, "Deneme: Asist çalışıyor")
        XCTAssertEqual(NotificationCopy.signingExpiredContent().title, "Asist'in imzası doldu")
    }
}
