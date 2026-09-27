import Foundation
import XCTest
@testable import AsistCore

/// 07 §7.2 / §13: the weekly status report builder, its text format and the Smart Mode polish prompt.
/// Reference instant: Sun 2026-09-27 10:30 (Europe/Istanbul); this week = Mon 21 – Sun 27 Eylül 2026.
final class WeeklyReportTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let now = TestSupport.date("2026-09-27T10:30")

    private func makeItem(_ kind: ItemKind, _ title: String, due: String? = nil, hasTime: Bool = true,
                          person: String? = nil, projectID: UUID? = nil,
                          created: String = "2026-09-20T09:00") -> Item {
        Item(kind: kind, title: title, dueDate: due.map { TestSupport.date($0) }, hasTime: hasTime, person: person,
             projectID: projectID, createdAt: TestSupport.date(created))
    }

    private func done(_ title: String, at completed: String, projectID: UUID? = nil) -> Item {
        var item = makeItem(.task, title, due: "2026-09-18T09:00", projectID: projectID)
        item.status = .done
        item.completedAt = TestSupport.date(completed)
        return item
    }

    private func project(_ name: String, _ index: Int) -> Project {
        let id = UUID(uuidString: "00000000-0000-4000-8000-00000000000" + String(index)) ?? UUID()
        return Project(id: id, name: name, createdAt: TestSupport.date("2026-09-01T09:00"))
    }

    private func build(_ items: [Item], projects: [Project] = [], weekOffset: Int = 0,
                       at instant: Date? = nil) -> WeeklyReport {
        WeeklyReportBuilder.build(items: items, projects: projects, now: instant ?? now, weekOffset: weekOffset,
                                  calendar: calendar)
    }

    private func allLines(_ report: WeeklyReport) -> [WeeklyReport.Line] {
        var lines: [WeeklyReport.Line] = []
        for section in report.sections {
            lines.append(contentsOf: section.done)
            lines.append(contentsOf: section.overdue)
            lines.append(contentsOf: section.open)
            lines.append(contentsOf: section.nextWeek)
            for group in section.waiting {
                lines.append(contentsOf: group.lines)
            }
        }
        return lines
    }

    // MARK: - Week bounds and titles

    func testWeekStartIsMondayMidnight() {
        let monday = TestSupport.date("2026-09-21T00:00")
        XCTAssertEqual(WeeklyReportBuilder.weekStart(containing: monday, calendar: calendar), monday)
        XCTAssertEqual(WeeklyReportBuilder.weekStart(containing: TestSupport.date("2026-09-27T23:59"),
                                                     calendar: calendar), monday)
        XCTAssertEqual(WeeklyReportBuilder.weekStart(containing: TestSupport.date("2026-09-23T12:00"),
                                                     calendar: calendar), monday)
        XCTAssertEqual(WeeklyReportBuilder.weekStart(containing: TestSupport.date("2026-09-20T23:59"),
                                                     calendar: calendar), TestSupport.date("2026-09-14T00:00"))
    }

    func testRangeTitles() {
        let thisWeek = build([])
        XCTAssertEqual(thisWeek.rangeTitle, "21–27 Eylül 2026")
        XCTAssertEqual(thisWeek.weekStart, TestSupport.date("2026-09-21T00:00"))
        XCTAssertEqual(thisWeek.weekEnd, TestSupport.date("2026-09-28T00:00"))
        XCTAssertEqual(build([], weekOffset: -1).rangeTitle, "14–20 Eylül 2026")
        XCTAssertEqual(build([], at: TestSupport.date("2026-09-30T10:00")).rangeTitle, "28 Eylül – 4 Ekim 2026")
        XCTAssertEqual(build([], at: TestSupport.date("2026-12-30T10:00")).rangeTitle,
                       "28 Aralık 2026 – 3 Ocak 2027")
    }

    // MARK: - Done

    func testDoneBoundaryBetweenThisAndLastWeek() {
        let mondayStart = done("Pazartesi ilk dakika", at: "2026-09-21T00:00")
        let sundayEnd = done("Pazar son dakika", at: "2026-09-20T23:59")
        let today = done("Bugün bitti", at: "2026-09-27T10:00")
        var deleted = done("Silinen iş", at: "2026-09-24T10:00")
        deleted.status = .deleted
        var note = makeItem(.note, "Bir not")
        note.status = .done
        note.completedAt = TestSupport.date("2026-09-24T10:00")
        let items = [mondayStart, sundayEnd, today, deleted, note]

        let thisWeek = build(items)
        XCTAssertEqual(allLines(thisWeek).map { $0.title }, ["Pazartesi ilk dakika", "Bugün bitti"])
        XCTAssertEqual(thisWeek.totals.done, 2)

        let lastWeek = build(items, weekOffset: -1)
        XCTAssertEqual(allLines(lastWeek).map { $0.title }, ["Pazar son dakika"])
        XCTAssertEqual(lastWeek.totals.done, 1)
    }

    func testOccurrenceDoneHistoryCountsAsRepeatLine() {
        var daily = makeItem(.reminder, "Günlük kontrol", due: "2026-09-28T09:00")
        daily.recurrence = Recurrence(frequency: .daily)
        daily.history = [
            HistoryEntry(date: TestSupport.date("2026-09-19T09:05"), event: .occurrenceDone),
            HistoryEntry(date: TestSupport.date("2026-09-25T09:10"), event: .occurrenceDone),
            HistoryEntry(date: TestSupport.date("2026-09-26T09:00"), event: .occurrenceMissed)
        ]
        let report = build([daily])
        XCTAssertEqual(report.sections.count, 1)
        let section = report.sections[0]
        XCTAssertEqual(section.done.map { $0.title }, ["Günlük kontrol (tekrar)"])
        XCTAssertEqual(section.done.first?.detail, "25 Eylül Cuma")
        XCTAssertEqual(section.done.first?.id, daily.id.uuidString + "#202609250910")
        // The open occurrence itself (tomorrow 09:00) is next week's work.
        XCTAssertEqual(section.nextWeek.map { $0.title }, ["Günlük kontrol"])
        XCTAssertEqual(section.nextWeek.first?.detail, "Yarın 09:00")
    }

    // MARK: - Open items

    func testOpenItemClassification() {
        let overdue = makeItem(.reminder, "Geciken", due: "2026-09-26T15:00")
        let todayLater = makeItem(.reminder, "Bugün sonra", due: "2026-09-27T14:00")
        let todayUntimed = makeItem(.task, "Bugün saatsiz", due: "2026-09-27T09:00", hasTime: false)
        let undated = makeItem(.task, "Saatsiz iş")
        let tuesday = makeItem(.reminder, "Salı işi", due: "2026-09-29T10:00")
        let farAway = makeItem(.reminder, "Uzak iş", due: "2026-10-06T10:00")
        let report = build([overdue, todayLater, todayUntimed, undated, tuesday, farAway])
        XCTAssertEqual(report.sections.count, 1)
        let section = report.sections[0]
        XCTAssertEqual(section.id, WeeklyReportBuilder.noProjectID)
        XCTAssertEqual(section.title, "Projesiz")
        XCTAssertEqual(section.overdue.map { $0.title }, ["Geciken"])
        XCTAssertEqual(section.overdue.first?.detail, "Dün 15:00")
        XCTAssertEqual(section.open.map { $0.title }, ["Bugün saatsiz", "Bugün sonra", "Saatsiz iş"])
        XCTAssertEqual(section.open.map { $0.detail }, ["Bugün", "Bugün 14:00", "Zamanı belirsiz"])
        XCTAssertEqual(section.nextWeek.map { $0.title }, ["Salı işi"])
        XCTAssertEqual(section.nextWeek.first?.detail, "Salı 10:00")
        XCTAssertEqual(report.totals, WeeklyReport.Totals(done: 0, overdue: 1, open: 3, nextWeek: 1, waiting: 0))
        XCTAssertEqual(report.totals.summaryLine, "0 tamamlandı · 1 geciken · 3 açık · 1 gelecek hafta · 0 bekleniyor")
    }

    func testWaitingIsGroupedByPerson() {
        let first = makeItem(.waiting, "I/O listesi", due: "2026-09-29T10:00", hasTime: false, person: "Ahmet",
                             created: "2026-09-24T09:00")
        let second = makeItem(.waiting, "Fiyat teklifi", due: "2026-09-29T10:00", hasTime: false, person: "ahmet ",
                              created: "2026-09-27T08:00")
        let third = makeItem(.waiting, "Numune", due: "2026-09-29T10:00", hasTime: false, person: "AHMET",
                             created: "2026-09-25T09:00")
        let noPerson = makeItem(.waiting, "Kablo", due: "2026-09-29T10:00", hasTime: false,
                                created: "2026-09-26T09:00")
        let cagri = makeItem(.waiting, "Sipariş onayı", due: "2026-09-29T10:00", hasTime: false, person: "Çağrı",
                             created: "2026-09-26T09:00")
        let cagriFolded = makeItem(.waiting, "Fatura", due: "2026-09-29T10:00", hasTime: false, person: "cagri",
                                   created: "2026-09-26T10:00")
        let report = build([first, second, third, noPerson, cagri, cagriFolded])
        let groups = report.sections[0].waiting
        XCTAssertEqual(groups.map { $0.person }, ["Ahmet", "Çağrı", "Kişi belirtilmemiş"])
        XCTAssertEqual(groups[0].lines.map { $0.title }, ["I/O listesi", "Numune", "Fiyat teklifi"])
        XCTAssertEqual(groups[0].lines.map { $0.detail }, ["3 gündür", "2 gündür", "bugün"])
        XCTAssertEqual(groups[1].lines.map { $0.title }, ["Sipariş onayı", "Fatura"])
        XCTAssertEqual(report.totals.waiting, 6)
        let text = WeeklyReportBuilder.text(report, userName: "")
        XCTAssertTrue(text.contains("Beklenenler (6)\n- Ahmet: I/O listesi · 3 gündür"))
        XCTAssertTrue(text.contains("\n- Kablo · 1 gündür"))
    }

    // MARK: - Sections

    func testProjectOrderByWeightAndProjesizLast() {
        let kocaeli = project("Kocaeli hattı", 1)
        let ankara = project("Ankara", 2)
        let bursa = project("Bursa", 3)
        let items = [
            makeItem(.reminder, "K geciken", due: "2026-09-26T15:00", projectID: kocaeli.id),     // weight 3
            makeItem(.task, "A1", projectID: ankara.id),                                           // weight 2
            makeItem(.task, "A2", projectID: ankara.id),
            makeItem(.task, "B1", projectID: bursa.id),                                            // weight 3
            makeItem(.task, "B2", projectID: bursa.id),
            makeItem(.task, "B3", projectID: bursa.id),
            makeItem(.task, "P1"), makeItem(.task, "P2"), makeItem(.task, "P3"), makeItem(.task, "P4"),
            makeItem(.task, "Silinmiş proje", projectID: UUID(uuidString: "00000000-0000-4000-8000-000000000099"))
        ]
        let report = build(items, projects: [kocaeli, ankara, bursa])
        XCTAssertEqual(report.sections.map { $0.title }, ["Bursa", "Kocaeli hattı", "Ankara", "Projesiz"])
        XCTAssertEqual(report.sections.map { $0.id },
                       [bursa.id.uuidString, kocaeli.id.uuidString, ankara.id.uuidString, "projesiz"])
        XCTAssertEqual(report.sections[3].open.count, 5)
    }

    func testTextCapsListsAtTwelveLines() {
        var items: [Item] = []
        for index in 1...14 {
            items.append(makeItem(.task, "İş " + String(index), created: "2026-09-20T09:" + AsistCalendar.pad(index, 2)))
        }
        let report = build(items)
        XCTAssertEqual(report.totals.open, 14)
        XCTAssertEqual(report.sections[0].open.count, 14)
        let text = WeeklyReportBuilder.text(report, userName: "")
        let lines = text.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("Açık (14)"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("- ") }.count, 13)
        XCTAssertEqual(lines.last, "- … ve 2 iş daha")
        XCTAssertTrue(lines.contains("- İş 12 · Zamanı belirsiz"))
        XCTAssertFalse(lines.contains("- İş 13 · Zamanı belirsiz"))
    }

    func testExactTextForAFourItemFixture() {
        let kocaeli = project("Kocaeli hattı", 1)
        var fat = makeItem(.task, "Pano FAT tarihini netleştir", due: "2026-09-23T09:00", projectID: kocaeli.id)
        fat.status = .done
        fat.completedAt = TestSupport.date("2026-09-23T11:00")
        let revision = makeItem(.reminder, "Teklif revizyonu", due: "2026-09-25T17:00", projectID: kocaeli.id)
        let io = makeItem(.waiting, "I/O listesi", due: "2026-09-28T10:00", hasTime: false, person: "Ahmet",
                          projectID: kocaeli.id, created: "2026-09-24T09:00")
        let sat = makeItem(.reminder, "SAT hazırlığı", due: "2026-09-29T10:00")
        let report = build([fat, revision, io, sat], projects: [kocaeli])
        let expected = """
        HAFTALIK DURUM · 21–27 Eylül 2026
        1 tamamlandı · 1 geciken · 0 açık · 1 gelecek hafta · 1 bekleniyor

        KOCAELİ HATTI
        Tamamlanan (1)
        - Pano FAT tarihini netleştir · 23 Eylül Çarşamba
        Geciken (1)
        - Teklif revizyonu · 25 Eylül Cuma 17:00
        Beklenenler (1)
        - Ahmet: I/O listesi · 3 gündür

        PROJESİZ
        Gelecek hafta (1)
        - SAT hazırlığı · Salı 10:00

        Gökhan
        """
        XCTAssertEqual(WeeklyReportBuilder.text(report, userName: "  Gökhan "), expected)
    }

    func testEmptyReportText() {
        let report = build([])
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.totals, WeeklyReport.Totals())
        XCTAssertEqual(WeeklyReportBuilder.text(report, userName: ""),
                       "HAFTALIK DURUM · 21–27 Eylül 2026\nBu hafta için raporlanacak kayıt yok.")
        XCTAssertEqual(WeeklyReportBuilder.text(report, userName: "Gökhan"),
                       "HAFTALIK DURUM · 21–27 Eylül 2026\nBu hafta için raporlanacak kayıt yok.\n\nGökhan")
    }

    func testLastWeekTreatsThisWeekAsNextWeek() {
        let lastWeekDone = done("Geçen hafta biten", at: "2026-09-16T14:00")
        let today = makeItem(.reminder, "Bugünkü toplantı hazırlığı", due: "2026-09-27T14:00")
        let tuesday = makeItem(.reminder, "Salı işi", due: "2026-09-29T10:00")
        let report = build([lastWeekDone, today, tuesday], weekOffset: -1)
        XCTAssertEqual(report.rangeTitle, "14–20 Eylül 2026")
        XCTAssertEqual(report.totals, WeeklyReport.Totals(done: 1, overdue: 0, open: 0, nextWeek: 1, waiting: 0))
        XCTAssertEqual(report.sections[0].done.first?.detail, "16 Eylül Çarşamba")
        XCTAssertEqual(report.sections[0].nextWeek.map { $0.title }, ["Bugünkü toplantı hazırlığı"])
    }

    // MARK: - Smart Mode prompt

    func testReportPolishUserMessage() {
        let message = SmartModePrompts.reportPolishUserMessage(report: "HAFTALIK DURUM · x", userName: " Gökhan ")
        XCTAssertEqual(message, "İmza adı: Gökhan\nRapor:\nHAFTALIK DURUM · x")
        XCTAssertTrue(SmartModePrompts.reportPolishUserMessage(report: "r", userName: "").hasPrefix("İmza adı: yok\n"))
        XCTAssertTrue(SmartModePrompts.reportPolishSystem.contains("message"))
    }
}
