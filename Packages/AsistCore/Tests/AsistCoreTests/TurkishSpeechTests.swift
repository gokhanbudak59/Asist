import Foundation
import XCTest
@testable import AsistCore

/// 03 §5.12 suffix table, 05b F12 12-hour daypart phrases, 04 §3.5.4 required confirmations, `dialogSafe`.
/// Reference instant: Sun 2026-09-27 10:30 (Europe/Istanbul).
final class TurkishSpeechTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let now = TestSupport.date("2026-09-27T10:30")

    private func makeItem(_ kind: ItemKind, _ title: String, due: String? = nil, hasTime: Bool = true) -> Item {
        Item(kind: kind, title: title, dueDate: due.map { TestSupport.date($0) }, hasTime: hasTime,
             createdAt: TestSupport.date("2026-09-27T10:30"))
    }

    private func confirm(_ item: Item, project: String? = nil, headless: Bool = false, low: Bool = false,
                         defaulted: Bool = false) -> String {
        TurkishSpeech.confirmation(for: item, projectName: project, headless: headless, lowConfidence: low,
                                   appliedDefaultTime: defaulted, now: now, calendar: calendar)
    }

    // MARK: - Numbers and suffixes

    func testNumberWords() {
        XCTAssertEqual(TurkishSpeech.numberWords(0), "sıfır")
        XCTAssertEqual(TurkishSpeech.numberWords(7), "yedi")
        XCTAssertEqual(TurkishSpeech.numberWords(10), "on")
        XCTAssertEqual(TurkishSpeech.numberWords(15), "on beş")
        XCTAssertEqual(TurkishSpeech.numberWords(40), "kırk")
        XCTAssertEqual(TurkishSpeech.numberWords(99), "doksan dokuz")
        XCTAssertEqual(TurkishSpeech.numberWords(100), "yüz")
        XCTAssertEqual(TurkishSpeech.numberWords(102), "yüz iki")
        XCTAssertEqual(TurkishSpeech.numberWords(250), "iki yüz elli")
        XCTAssertEqual(TurkishSpeech.numberWords(1000), "bin")
        XCTAssertEqual(TurkishSpeech.numberWords(2026), "iki bin yirmi altı")
        XCTAssertEqual(TurkishSpeech.numberWords(-3), "-3")
    }

    func testLocativeSuffixTable() {
        // 03 §5.12: chosen by the last spoken word.
        let expected: [Int: String] = [
            1: "'de", 2: "'de", 3: "'te", 4: "'te", 5: "'te", 6: "'da", 7: "'de", 8: "'de", 9: "'da",
            10: "'da", 20: "'de", 30: "'da", 40: "'ta", 50: "'de", 60: "'ta", 70: "'te", 80: "'de", 90: "'da",
            13: "'te", 16: "'da", 21: "'de", 0: "'da", 100: "'de", 1000: "'de"
        ]
        for (number, suffix) in expected {
            XCTAssertEqual(TurkishSpeech.locativeSuffix(forNumber: number), suffix, "number \(number)")
        }
    }

    func testDisplayClockLocative() {
        XCTAssertEqual(TurkishSpeech.displayClockLocative(hour: 15, minute: 0), "15'te")
        XCTAssertEqual(TurkishSpeech.displayClockLocative(hour: 15, minute: 30), "15:30'da")
        XCTAssertEqual(TurkishSpeech.displayClockLocative(hour: 9, minute: 0), "9'da")
        XCTAssertEqual(TurkishSpeech.displayClockLocative(hour: 21, minute: 0), "21'de")
        XCTAssertEqual(TurkishSpeech.displayClockLocative(hour: 15, minute: 20), "15:20'de")
        XCTAssertEqual(TurkishSpeech.displayClockLocative(hour: 15, minute: 40), "15:40'ta")
        XCTAssertEqual(TurkishSpeech.displayClockLocative(hour: 0, minute: 0), "gece yarısı")
    }

    func testSpokenClockLocative24Hour() {
        XCTAssertEqual(TurkishSpeech.spokenClockLocative(hour: 15, minute: 0), "on beşte")
        XCTAssertEqual(TurkishSpeech.spokenClockLocative(hour: 15, minute: 30), "on beş otuzda")
        XCTAssertEqual(TurkishSpeech.spokenClockLocative(hour: 16, minute: 0), "on altıda")
        XCTAssertEqual(TurkishSpeech.spokenClockLocative(hour: 12, minute: 0), "on ikide")
        XCTAssertEqual(TurkishSpeech.spokenClockLocative(hour: 15, minute: 5), "on beş sıfır beşte")
        XCTAssertEqual(TurkishSpeech.spokenClockLocative(hour: 0, minute: 30), "sıfır otuzda")
        XCTAssertEqual(TurkishSpeech.spokenClockLocative(hour: 0, minute: 0), "gece yarısı")
    }

    func testSpokenTimeOfDayRequiredExamples() {
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 15, minute: 0), "öğleden sonra üçte")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 9, minute: 0), "sabah dokuzda")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 20, minute: 0), "akşam sekizde")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 12, minute: 0), "öğlen on ikide")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 15, minute: 30), "öğleden sonra üç buçukta")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 15, minute: 15), "öğleden sonra üç on beşte")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 2, minute: 0), "gece ikide")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 0, minute: 0), "gece yarısı")
    }

    func testSpokenTimeOfDayDaypartBoundaries() {
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 4, minute: 0), "gece dörtte")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 5, minute: 0), "sabah beşte")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 11, minute: 45), "sabah on bir kırk beşte")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 12, minute: 30), "öğlen on iki buçukta")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 13, minute: 0), "öğleden sonra birde")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 17, minute: 59), "öğleden sonra beş elli dokuzda")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 18, minute: 0), "akşam altıda")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 22, minute: 0), "gece onda")
        XCTAssertEqual(TurkishSpeech.spokenTimeOfDay(hour: 9, minute: 5), "sabah dokuz sıfır beşte")
    }

    func testSpokenWhen() {
        func when(_ s: String) -> String {
            TurkishSpeech.spokenWhen(TestSupport.date(s), now: now, calendar: calendar)
        }
        XCTAssertEqual(when("2026-09-27T20:00"), "bugün akşam sekizde")
        XCTAssertEqual(when("2026-09-28T09:00"), "yarın sabah dokuzda")
        XCTAssertEqual(when("2026-09-29T15:00"), "salı öğleden sonra üçte")
        XCTAssertEqual(when("2026-09-30T15:30"), "çarşamba öğleden sonra üç buçukta")
        XCTAssertEqual(when("2026-10-29T10:00"), "29 Ekim sabah onda")
        XCTAssertEqual(when("2027-01-03T09:00"), "3 Ocak 2027 sabah dokuzda")
        XCTAssertEqual(when("2026-09-26T09:00"), "dün sabah dokuzda")
    }

    func testSpokenDuration() {
        XCTAssertEqual(TurkishSpeech.spokenDuration(minutes: 15), "on beş dakika")
        XCTAssertEqual(TurkishSpeech.spokenDuration(minutes: 30), "yarım saat")
        XCTAssertEqual(TurkishSpeech.spokenDuration(minutes: 60), "bir saat")
        XCTAssertEqual(TurkishSpeech.spokenDuration(minutes: 90), "bir buçuk saat")
        XCTAssertEqual(TurkishSpeech.spokenDuration(minutes: 150), "iki saat otuz dakika")
        XCTAssertEqual(TurkishSpeech.spokenDuration(minutes: 1440), "bir gün")
        XCTAssertEqual(TurkishSpeech.spokenDuration(minutes: 10080), "bir hafta")
        XCTAssertEqual(TurkishSpeech.spokenDuration(minutes: 43200), "otuz gün")
    }

    // MARK: - Required confirmations (04 §3.5.4)

    func testReminderConfirmation() {
        let item = makeItem(.reminder, "Teklif konusu", due: "2026-09-29T15:00")
        XCTAssertEqual(confirm(item), "Tamam, salı öğleden sonra üçte hatırlatacağım.")
        XCTAssertEqual(confirm(item, headless: true), "Tamam, salı öğleden sonra üçte hatırlatacağım: Teklif konusu.")
    }

    func testTaskConfirmations() {
        let today = makeItem(.task, "Sipariş formu", due: "2026-09-27T11:00", hasTime: false)
        XCTAssertEqual(confirm(today), "Tamam, görevlere ekledim; bugün içinde hatırlatacağım.")

        let unscheduled = makeItem(.task, "Sipariş formu")
        XCTAssertEqual(confirm(unscheduled), "Görevlere ekledim.")
        XCTAssertEqual(confirm(unscheduled, headless: true), "Görevlere ekledim: Sipariş formu.")

        let friday = makeItem(.task, "Rapor", due: "2026-10-02T09:00", hasTime: false)
        XCTAssertEqual(confirm(friday), "Tamam, görevlere ekledim; cuma sabah dokuzda hatırlatacağım.")
    }

    func testEventConfirmation() {
        var event = makeItem(.reminder, "ABB ile toplantı", due: "2026-10-01T14:00")
        event.isEvent = true
        event.leadTimesMinutes = [15]
        XCTAssertEqual(confirm(event), "Tamam, perşembe öğleden sonra ikide; on beş dakika önce haber vereceğim.")
    }

    func testNoteConfirmations() {
        let note = makeItem(.note, "Işık perdesi mesafesi")
        XCTAssertEqual(confirm(note), "Not aldım.")
        XCTAssertEqual(confirm(note, project: "Arka Cep"), "Arka Cep projesine not aldım.")
    }

    func testWaitingConfirmation() {
        let waiting = makeItem(.waiting, "Çizimler", due: "2026-10-02T16:00")
        XCTAssertEqual(confirm(waiting), "Tamam, cuma günü takip edeceğim.")
    }

    func testAppliedDefaultTimeConfirmation() {
        let item = makeItem(.reminder, "Hakan'la konuş", due: "2026-09-27T11:30")
        XCTAssertEqual(confirm(item, defaulted: true), "Zaman söylemedin; bir saat sonra hatırlatacağım.")
    }

    func testLowConfidenceHeadlessConfirmation() {
        let item = makeItem(.task, "Teklif konusu", due: "2026-09-27T11:00", hasTime: false)
        XCTAssertEqual(confirm(item, headless: true, low: true),
                       "“Teklif konusu” olarak kaydettim. Emin olmak için Asist'i aç.")
    }

    func testRecurringReminderConfirmation() {
        var item = makeItem(.reminder, "Haftalık rapor", due: "2026-09-28T09:00")
        item.recurrence = Recurrence(frequency: .weekly, weekdays: [1])
        XCTAssertEqual(confirm(item), "Tamam, her pazartesi sabah dokuzda hatırlatacağım.")
        item.recurrence = Recurrence(frequency: .weekly, weekdays: [1, 2, 3, 4, 5])
        XCTAssertEqual(confirm(item), "Tamam, hafta içi her gün sabah dokuzda hatırlatacağım.")
    }

    func testConfirmationIsDialogSafe() {
        let item = makeItem(.reminder, "%50 indirim teklifi", due: "2026-09-29T15:00")
        let text = confirm(item, headless: true)
        XCTAssertFalse(text.contains("%"))
        XCTAssertTrue(text.hasSuffix(": yüzde 50 indirim teklifi."))
    }

    // MARK: - dialogSafe

    func testDialogSafe() {
        XCTAssertEqual(TurkishSpeech.dialogSafe("%50 indirim teklifi"), "yüzde 50 indirim teklifi")
        XCTAssertEqual(TurkishSpeech.dialogSafe("Oran %20 oldu"), "Oran yüzde 20 oldu")
        XCTAssertEqual(TurkishSpeech.dialogSafe("  a   b\nc  "), "a b c")
        XCTAssertEqual(TurkishSpeech.dialogSafe(""), "")
    }
}
