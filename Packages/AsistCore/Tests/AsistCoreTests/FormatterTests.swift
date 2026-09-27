import Foundation
import XCTest
@testable import AsistCore

/// 02 §13 examples, numeral suffix table 1…31, 03 §7.11/§7.12 row labels.
final class FormatterTests: XCTestCase {
    let calendar = TestSupport.calendar
    let sunday = TestSupport.date("2026-09-27T10:30")

    func testTables() {
        XCTAssertEqual(TurkishDateFormatter.months.count, 12)
        XCTAssertEqual(TurkishDateFormatter.monthsShort.count, 12)
        XCTAssertEqual(TurkishDateFormatter.weekdays, ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma",
                                                       "Cumartesi", "Pazar"])
        XCTAssertEqual(TurkishDateFormatter.weekdaysShort.count, 7)
        XCTAssertEqual(TurkishDateFormatter.hhmm(9, 5), "09:05")
        XCTAssertEqual(TurkishDateFormatter.hhmm(15, 0), "15:00")
        XCTAssertEqual(TurkishDateFormatter.time(TestSupport.date("2026-09-29T15:00"), calendar: calendar), "15:00")
    }

    func testDayLabelAndDatePhrase() {
        XCTAssertEqual(TurkishDateFormatter.dayLabel(TestSupport.date("2026-09-27T20:00"), now: sunday, calendar: calendar),
                       "Bugün")
        XCTAssertEqual(TurkishDateFormatter.dayLabel(TestSupport.date("2026-09-28T02:00"), now: sunday, calendar: calendar),
                       "Yarın")
        XCTAssertEqual(TurkishDateFormatter.dayLabel(TestSupport.date("2026-09-26T09:00"), now: sunday, calendar: calendar),
                       "Dün")
        XCTAssertEqual(TurkishDateFormatter.datePhrase(TestSupport.date("2026-09-27T12:00"), now: sunday,
                                                       calendar: calendar), "Bugün 27 Eylül")
        XCTAssertEqual(TurkishDateFormatter.datePhrase(TestSupport.date("2026-09-28T12:00"), now: sunday,
                                                       calendar: calendar), "Yarın 28 Eylül")
        XCTAssertEqual(TurkishDateFormatter.datePhrase(TestSupport.date("2026-09-29T15:00"), now: sunday,
                                                       calendar: calendar), "Salı 29 Eylül")
        let dec31 = TestSupport.date("2026-12-31T16:00")
        XCTAssertEqual(TurkishDateFormatter.datePhrase(TestSupport.date("2027-01-01T12:00"), now: dec31,
                                                       calendar: calendar), "Yarın 1 Ocak 2027")
    }

    func testRelativePhrase() {
        func phrase(_ s: String) -> String {
            return TurkishDateFormatter.relativePhrase(to: TestSupport.date(s), now: sunday, calendar: calendar)
        }
        XCTAssertEqual(phrase("2026-09-27T10:40"), "(10 dakika sonra)")
        XCTAssertEqual(phrase("2026-09-27T12:00"), "(1 saat 30 dakika sonra)")
        XCTAssertEqual(phrase("2026-09-27T20:00"), "(9 saat 30 dakika sonra)")
        XCTAssertEqual(phrase("2026-09-27T11:30"), "(1 saat sonra)")
        XCTAssertEqual(phrase("2026-09-28T02:00"), "(yarın)")
        XCTAssertEqual(phrase("2026-09-28T09:00"), "(yarın)")
        XCTAssertEqual(phrase("2026-09-29T15:00"), "(2 gün sonra)")
        XCTAssertEqual(phrase("2026-10-15T09:00"), "(yaklaşık 3 hafta sonra)")
        XCTAssertEqual(phrase("2027-01-15T09:00"), "(yaklaşık 4 ay sonra)")
        XCTAssertEqual(phrase("2026-09-27T10:30"), "(şimdi)")
        XCTAssertEqual(phrase("2026-09-27T09:00"), "(geçmiş)")
    }

    func testNumeralPossessiveTable() {
        let expected = ["1'i", "2'si", "3'ü", "4'ü", "5'i", "6'sı", "7'si", "8'i", "9'u", "10'u",
                        "11'i", "12'si", "13'ü", "14'ü", "15'i", "16'sı", "17'si", "18'i", "19'u", "20'si",
                        "21'i", "22'si", "23'ü", "24'ü", "25'i", "26'sı", "27'si", "28'i", "29'u", "30'u", "31'i"]
        for n in 1...31 {
            XCTAssertEqual(TurkishDateFormatter.numeralPossessive(n), expected[n - 1])
        }
        XCTAssertEqual(TurkishDateFormatter.numeralPossessive(40), "40'ı")
        XCTAssertEqual(TurkishDateFormatter.numeralPossessive(100), "100'ü")
    }

    func testRecurrenceText() {
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .daily)), "Her gün")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .daily, interval: 3)), "Her 3 günde bir")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .weekly, weekdays: [1, 2, 3, 4, 5])),
                       "Hafta içi her gün")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .weekly, weekdays: [6, 7])),
                       "Her hafta sonu")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .weekly, weekdays: [1])),
                       "Her Pazartesi")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .weekly, weekdays: [1, 4])),
                       "Her Pazartesi ve Perşembe")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .weekly, weekdays: [1, 3, 5])),
                       "Her Pazartesi, Çarşamba ve Cuma")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .weekly, interval: 2, weekdays: [5])),
                       "2 haftada bir Cuma")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .monthly, monthDay: 1)),
                       "Her ayın 1'i")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .monthly, monthDay: -1)),
                       "Her ayın son günü")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .monthly, monthDay: 31)),
                       "Her ayın 31'i (kısa aylarda son gün)")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .monthly, interval: 6, monthDay: 27)),
                       "6 ayda bir, ayın 27'si")
        XCTAssertEqual(TurkishDateFormatter.recurrenceText(Recurrence(frequency: .yearly, monthDay: 3, month: 3)),
                       "Her yıl 3 Mart")
    }

    func testShortDateTime() {
        func label(_ s: String, _ includeTime: Bool = true) -> String {
            return TurkishDateFormatter.shortDateTime(TestSupport.date(s), now: sunday, calendar: calendar,
                                                      includeTime: includeTime)
        }
        XCTAssertEqual(label("2026-09-27T15:00"), "Bugün 15:00")
        XCTAssertEqual(label("2026-09-28T09:00"), "Yarın 09:00")
        XCTAssertEqual(label("2026-09-29T15:00"), "Salı 15:00")
        XCTAssertEqual(label("2026-10-06T15:00"), "6 Ekim Salı 15:00")
        XCTAssertEqual(label("2026-09-26T08:00"), "Dün 08:00")
        XCTAssertEqual(label("2026-09-20T08:00"), "20 Eylül Pazar 08:00")
        XCTAssertEqual(label("2027-01-04T08:00", false), "4 Ocak 2027 Pazartesi")
    }

    func testRelativeShort() {
        func label(_ s: String) -> String {
            return TurkishDateFormatter.relativeShort(to: TestSupport.date(s), now: sunday, calendar: calendar)
        }
        XCTAssertEqual(label("2026-09-27T10:40"), "10 dk sonra")
        XCTAssertEqual(label("2026-09-27T12:30"), "2 saat sonra")
        XCTAssertEqual(label("2026-09-30T09:00"), "3 gün sonra")
        XCTAssertEqual(label("2026-09-27T10:30"), "Şimdi")
        XCTAssertEqual(label("2026-09-27T10:27"), "Şimdi")
        XCTAssertEqual(label("2026-09-27T10:25"), "5 dk gecikti")
        XCTAssertEqual(label("2026-09-27T08:30"), "2 saat gecikti")
        XCTAssertEqual(label("2026-09-24T10:30"), "3 gündür bekliyor")
    }

    func testDuration() {
        XCTAssertEqual(TurkishDateFormatter.duration(minutes: 10), "10 dakika")
        XCTAssertEqual(TurkishDateFormatter.duration(minutes: 60), "1 saat")
        XCTAssertEqual(TurkishDateFormatter.duration(minutes: 90), "1 saat 30 dakika")
        XCTAssertEqual(TurkishDateFormatter.duration(minutes: 1440), "1 gün")
        XCTAssertEqual(TurkishDateFormatter.duration(minutes: 10080), "1 hafta")
        XCTAssertEqual(TurkishDateFormatter.duration(minutes: -5), "0 dakika")
    }

    func testUnderstoodText() {
        var settings = ParserSettings()
        settings.knownProjects = ["Arka Cep", "Hat 3", "Kaynak Robotu", "Bakım"]
        let parser = TurkishParser(settings: settings, calendar: calendar)
        let reminder = parser.parse("Salı günü teklif konusunu bana saat 3'te hatırlat", now: sunday)
        XCTAssertEqual(reminder.understood, "Salı 29 Eylül, 15:00 — Teklif konusu")
        XCTAssertEqual(reminder.relativePhrase, "(2 gün sonra)")
        let daily = parser.parse("her gün saat 8'de günlük üretim raporunu kontrol et", now: sunday)
        XCTAssertEqual(daily.understood, "Yarın 28 Eylül, 08:00 — Günlük üretim raporunu kontrol et · Her gün")
        let query = parser.parse("bugün ne var", now: sunday)
        XCTAssertEqual(query.understood, "Bugünün ajandası")
        let complete = parser.parse("teklif konusunu tamamladım", now: sunday)
        XCTAssertEqual(complete.understood, "Tamamlanacak: teklif konusu")
        let waiting = parser.parse("Ahmet'ten teklif bekliyorum", now: sunday)
        XCTAssertEqual(waiting.understood, "Bekleniyor (Ahmet) — Teklif")
    }
}
