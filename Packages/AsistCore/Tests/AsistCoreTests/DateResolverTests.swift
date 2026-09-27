import Foundation
import XCTest
@testable import AsistCore

/// 02 §8 (day expressions, combination, today policy, hour resolution, worked examples) + 04 §3.4.6 P1–P3, G7–G9.
final class DateResolverTests: XCTestCase {

    let parser = TurkishParser(settings: DateResolverTests.settings(), calendar: TestSupport.calendar)

    static func settings() -> ParserSettings {
        var settings = ParserSettings()
        settings.knownProjects = ["Arka Cep", "Hat 3", "Kaynak Robotu", "Bakım"]
        settings.knownPlaces = ["Fabrika", "Ev", "Ofis"]
        return settings
    }

    func due(_ text: String, _ now: String) -> String? {
        return parser.parse(text, now: TestSupport.date(now)).item?.dueDate.map { TestSupport.format($0) }
    }

    func assertDue(_ text: String, now: String, _ expected: String?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(due(text, now), expected, "'\(text)' @ \(now)", file: file, line: line)
    }

    /// 02 §8.7 worked examples (now = Sun 2026-09-27 10:30 unless stated).
    func testWorkedExamples() {
        let sun = "2026-09-27T10:30"
        assertDue("salı günü toplantı saat 3'te", now: sun, "2026-09-29T15:00")
        assertDue("toplantı salı 9'da", now: sun, "2026-09-29T09:00")
        assertDue("bu salı toplantı", now: sun, "2026-09-29T09:00")
        assertDue("haftaya salı toplantı", now: sun, "2026-09-29T09:00")
        assertDue("pazar günü toplantı", now: sun, "2026-10-04T09:00")
        assertDue("bu pazar toplantı", now: sun, "2026-09-27T11:00")
        assertDue("3'te toplantı", now: sun, "2026-09-27T15:00")
        assertDue("8'de toplantı", now: sun, "2026-09-27T20:00")
        assertDue("11'de toplantı", now: sun, "2026-09-27T11:00")
        assertDue("sabah 9'da toplantı", now: sun, "2026-09-28T09:00")
        assertDue("akşam 8 toplantı", now: sun, "2026-09-27T20:00")
        assertDue("gece 2'de toplantı", now: sun, "2026-09-28T02:00")
        assertDue("yarın gece 12'de toplantı", now: sun, "2026-09-29T00:00")
        assertDue("hafta sonu toplantı", now: sun, "2026-10-03T09:00")
        assertDue("ay sonu toplantı", now: sun, "2026-09-30T09:00")
        assertDue("ayın 15'inde toplantı", now: sun, "2026-10-15T09:00")
        assertDue("20 eylül toplantı", now: sun, "2027-09-20T09:00")
        assertDue("10 dakika sonra toplantı", now: sun, "2026-09-27T10:40")
        assertDue("bir buçuk saat sonra toplantı", now: sun, "2026-09-27T12:00")
        assertDue("3 gün sonra toplantı", now: sun, "2026-09-30T09:00")
        assertDue("birazdan toplantı", now: sun, "2026-09-27T10:45")
        assertDue("akşama toplantı", now: sun, "2026-09-27T19:00")
        assertDue("mesai bitiminde toplantı", now: sun, "2026-09-27T17:30")
        let tueMorning = "2026-09-29T09:15"
        assertDue("salı toplantı", now: tueMorning, "2026-10-06T09:00")
        assertDue("bu salı 3'te toplantı", now: tueMorning, "2026-09-29T15:00")
        assertDue("9'da toplantı", now: tueMorning, "2026-09-29T21:00")
        let tueEvening = "2026-09-29T19:40"
        assertDue("3'te toplantı", now: tueEvening, "2026-09-30T15:00")
        assertDue("bugün 3'te toplantı", now: tueEvening, "2026-09-29T15:00")
        let dec31 = "2026-12-31T16:00"
        assertDue("haftaya cuma toplantı", now: dec31, "2027-01-08T09:00")
        assertDue("ay sonu toplantı", now: dec31, "2026-12-31T17:00")
    }

    /// 02 §8.2a: 10:30 → 11:00 · 19:40 → 21:00 · 23:10 → 23:40 · 06:05 → 09:00 · 16:00 → 17:00.
    func testTodayPolicy() {
        assertDue("bugün toplantı", now: "2026-09-27T10:30", "2026-09-27T11:00")
        assertDue("bugün toplantı", now: "2026-09-27T19:40", "2026-09-27T21:00")
        assertDue("bugün toplantı", now: "2026-09-27T23:10", "2026-09-27T23:40")
        assertDue("bugün toplantı", now: "2026-09-27T06:05", "2026-09-27T09:00")
        assertDue("bugün toplantı", now: "2026-09-27T16:00", "2026-09-27T17:00")
        let result = parser.parse("bugün toplantı", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertEqual(result.item?.hasTime, false)
        XCTAssertTrue(result.flags.contains(.defaultTimeApplied))
    }

    /// P1: "haftaya" / "gelecek hafta" without weekday = next week's first workday (Monday) at the default time.
    func testP1NextWeekWithoutWeekday() {
        assertDue("haftaya toplantı", now: "2026-10-02T23:10", "2026-10-05T09:00")
        assertDue("haftaya toplantı", now: "2026-09-28T10:10", "2026-10-05T09:00")
        assertDue("haftaya toplantı", now: "2026-09-27T10:30", "2026-09-28T09:00")
        let result = parser.parse("gelecek hafta müşteri ziyareti planla", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertTrue(result.flags.contains(.vagueDate))
    }

    /// P2: "haftaya salı" on Saturday/Sunday keeps the value but is capped below auto-save.
    func testP2NextWeekWeekdayOnWeekend() {
        let sunday = parser.parse("haftaya salı toplantı", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertTrue(sunday.flags.contains(.nextWeekAmbiguous))
        XCTAssertLessThanOrEqual(sunday.confidence, 0.79)
        assertDue("haftaya salı toplantı", now: "2026-09-26T10:00", "2026-09-29T09:00")
        let monday = parser.parse("haftaya salı toplantı", now: TestSupport.date("2026-09-28T10:10"))
        XCTAssertFalse(monday.flags.contains(.nextWeekAmbiguous))
        XCTAssertEqual(monday.item?.dueDate.map { TestSupport.format($0) }, "2026-10-06T09:00")
    }

    /// P3: a bare weekday equal to today is +7 days, even when today's time is still ahead.
    func testP3SameWeekdayIsNextWeek() {
        assertDue("salı 10'da toplantı", now: "2026-09-29T09:15", "2026-10-06T10:00")
        assertDue("bugün 10'da toplantı", now: "2026-09-29T09:15", "2026-09-29T10:00")
        assertDue("bu salı 10'da toplantı", now: "2026-09-29T09:15", "2026-09-29T10:00")
    }

    /// 02 §8.3 day expressions from several reference nows.
    func testDayExpressions() {
        let sun = "2026-09-27T10:30"
        assertDue("öbür gün toplantı", now: sun, "2026-09-29T09:00")
        assertDue("yarından sonra toplantı", now: sun, "2026-09-29T09:00")
        assertDue("ertesi gün toplantı", now: sun, "2026-09-28T09:00")
        assertDue("hafta başı toplantı", now: sun, "2026-09-28T09:00")
        assertDue("hafta ortası toplantı", now: sun, "2026-09-30T09:00")
        assertDue("ay başında toplantı", now: sun, "2026-10-01T09:00")
        assertDue("ay ortası toplantı", now: sun, "2026-10-15T09:00")
        assertDue("yıl sonu toplantı", now: sun, "2026-12-31T09:00")
        assertDue("ekim başı toplantı", now: sun, "2026-10-01T09:00")
        assertDue("kasım sonunda toplantı", now: sun, "2026-11-30T09:00")
        assertDue("ekimde fuar", now: sun, "2026-10-01T09:00")
        assertDue("15.10 tarihinde toplantı", now: sun, "2026-10-15T09:00")
        assertDue("15/10 toplantı", now: sun, "2026-10-15T09:00")
        assertDue("12.11.2026 tarihinde denetim", now: sun, "2026-11-12T09:00")
        assertDue("15 Ekim 2027'de toplantı", now: sun, "2027-10-15T09:00")
        assertDue("ekimin 5'inde fatura", now: sun, "2026-10-05T09:00")
        assertDue("geçen salı toplantı", now: sun, "2026-09-22T09:00")
        assertDue("hafta sonu toplantı", now: "2026-10-30T12:00", "2026-10-31T09:00")
        assertDue("ay sonunda toplantı", now: "2026-10-30T12:00", "2026-10-31T09:00")
        assertDue("ayın 15'inde toplantı", now: "2026-10-30T12:00", "2026-11-15T09:00")
        assertDue("yılbaşında toplantı", now: "2026-12-31T16:00", "2027-01-01T09:00")
        assertDue("hafta başında toplantı", now: "2026-09-28T06:05", "2026-10-05T09:00")
        assertDue("gelecek ayın 5'inde kira öde", now: "2026-09-03T10:00", "2026-10-05T09:00")
        assertDue("bu ayın 20'sinde fatura", now: "2026-09-03T10:00", "2026-09-20T09:00")
        assertDue("önümüzdeki ayın ilk pazartesi toplantı", now: "2026-09-03T10:00", "2026-10-05T09:00")
        let title = parser.parse("bu ayın 20'sinde fatura", now: TestSupport.date("2026-09-03T10:00")).item?.title
        XCTAssertEqual(title, "Fatura")
    }

    func testDottedIsAmbiguousWithoutConfirmingWord() {
        let result = parser.parse("15.10 kalibrasyon raporu", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertTrue(result.flags.contains(.ambiguousDotted))
        let time = parser.parse("15.10'da vardiya değişimi", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertEqual(time.item?.dueDate.map { TestSupport.format($0) }, "2026-09-27T15:10")
    }

    /// 02 §8.5 qualifier table.
    func testHourQualifiers() {
        let sun = "2026-09-27T10:30"
        assertDue("yarın sabah 7'de toplantı", now: sun, "2026-09-28T07:00")
        assertDue("yarın öğlen 1'de toplantı", now: sun, "2026-09-28T13:00")
        assertDue("yarın öğleden sonra 3'te toplantı", now: sun, "2026-09-28T15:00")
        assertDue("yarın öğleden sonra 6'da toplantı", now: sun, "2026-09-28T18:00")
        assertDue("yarın akşam 8'de toplantı", now: sun, "2026-09-28T20:00")
        assertDue("yarın akşam 12'de toplantı", now: sun, "2026-09-29T00:00")
        assertDue("yarın gece 11'de toplantı", now: sun, "2026-09-28T23:00")
        assertDue("yarın gece 2'de toplantı", now: sun, "2026-09-29T02:00")
        assertDue("yarın 09:30'da toplantı", now: sun, "2026-09-28T09:30")
        assertDue("yarın 14:00'te toplantı", now: sun, "2026-09-28T14:00")
        assertDue("yarın 3'te toplantı", now: sun, "2026-09-28T15:00")
        assertDue("yarın 9'da toplantı", now: sun, "2026-09-28T09:00")
    }

    func testPMPolicyCanBeTurnedOff() {
        var settings = DateResolverTests.settings()
        settings.belirsizSaatlerOgledenSonra = false
        let custom = TurkishParser(settings: settings, calendar: TestSupport.calendar)
        let result = custom.parse("yarın 5'te kalk", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertEqual(result.item?.dueDate.map { TestSupport.format($0) }, "2026-09-28T05:00")
        XCTAssertFalse(result.flags.contains(.ambiguousHourPM))
    }

    func testPastAndConflictFlags() {
        let past = parser.parse("bugün 3'te teklifi gönder", now: TestSupport.date("2026-09-29T19:40"))
        XCTAssertTrue(past.flags.contains(.pastDue))
        XCTAssertLessThan(past.confidence, 0.60)
        let conflict = parser.parse("yarın salı Ahmet'le toplantı", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertTrue(conflict.flags.contains(.conflictingDates))
        XCTAssertEqual(conflict.item?.dueDate.map { TestSupport.format($0) }, "2026-09-28T09:00")
        let merged = parser.parse("29 eylül salı saat 3'te teklif", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertFalse(merged.flags.contains(.conflictingDates))
    }

    /// G8: the last value wins after a correction marker.
    func testCorrections() {
        let clock = parser.parse("yarın 3'te hayır 4'te Ahmet'i ara", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertEqual(clock.item?.dueDate.map { TestSupport.format($0) }, "2026-09-28T16:00")
        XCTAssertTrue(clock.flags.contains(.correctionApplied))
        XCTAssertEqual(clock.item?.title, "Ahmet'i ara")
        assertDue("yarın değil öbür gün Hat 3 raporunu gönder", now: "2026-09-27T10:30", "2026-09-29T09:00")
    }

    /// G7 / G9 time words.
    func testColloquialTimeWords() {
        let sun = "2026-09-27T10:30"
        let monWork = "2026-09-28T10:10"
        assertDue("yarın 4 gibi Ahmet'i ara", now: sun, "2026-09-28T16:00")
        assertDue("yarın 10'dan sonra Ahmet'i ara", now: sun, "2026-09-28T10:00")
        assertDue("öğleden önce sipariş formunu imzala", now: monWork, "2026-09-28T11:00")
        assertDue("bugün içinde teklif revizyonunu gönder", now: monWork, "2026-09-28T11:00")
        assertDue("öğle yemeğinden sonra Ahmet'i ara", now: monWork, "2026-09-28T13:00")
        assertDue("bu gece vardiyada saat 3'te fırın sıcaklığını kontrol et", now: sun, "2026-09-28T03:00")
        assertDue("çok acil Ahmet Bey'i hemen ara", now: sun, "2026-09-27T10:35")
        assertDue("acil değil ama bu hafta Profinet adreslerini kontrol et", now: monWork, "2026-10-02T09:00")
    }

    func testRecurrenceFirstOccurrence() {
        let sun = "2026-09-27T10:30"
        assertDue("her gün saat 8'de rapor", now: sun, "2026-09-28T08:00")
        assertDue("her gün 3'te mola ver", now: sun, "2026-09-27T15:00")
        assertDue("her salı 10'da toplantı", now: "2026-09-29T09:15", "2026-09-29T10:00")
        assertDue("her salı 10'da toplantı", now: "2026-09-29T19:40", "2026-10-06T10:00")
        assertDue("her ayın son günü fatura kes", now: "2026-10-30T12:00", "2026-10-31T09:00")
        assertDue("her 6 ayda bir filtre değiştir", now: sun, "2027-03-27T09:00")
        assertDue("iki haftada bir cuma 3'te sprint", now: sun, "2026-10-02T15:00")
        let nth = parser.parse("her ayın ilk pazartesi yönetim toplantısı", now: TestSupport.date(sun))
        XCTAssertNil(nth.item?.recurrence)
        XCTAssertTrue(nth.flags.contains(.unsupportedRecurrence))
        XCTAssertEqual(nth.item?.dueDate.map { TestSupport.format($0) }, "2026-10-05T09:00")
        XCTAssertLessThanOrEqual(nth.confidence, 0.59)
    }

    func testOutputIsWholeMinutesAndDeterministic() {
        let now = TestSupport.date("2026-09-27T10:30").addingTimeInterval(37)
        let a = parser.parse("10 dakika sonra toplantı", now: now)
        let b = parser.parse("10 dakika sonra toplantı", now: now)
        XCTAssertEqual(a, b)
        let seconds = TestSupport.calendar.component(.second, from: a.item?.dueDate ?? now)
        XCTAssertEqual(seconds, 0)
        XCTAssertEqual(a.item?.dueDate.map { TestSupport.format($0) }, "2026-09-27T10:40")
    }
}
