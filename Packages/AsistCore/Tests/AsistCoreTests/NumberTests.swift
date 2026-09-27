import Foundation
import XCTest
@testable import AsistCore

/// 02 §6: cardinal words 1…99, suffixed forms, ordinals, durations, clock phrases (buçuk / çeyrek / geçe / kala).
final class NumberTests: XCTestCase {

    static let unitWords = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    static let tensWords = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]

    func context(_ text: String) -> ParseContext {
        let normalized = Normalizer.normalize(text)
        let tokenized = Tokenizer.tokenize(normalized)
        return ParseContext(tokens: tokenized.tokens, chars: tokenized.chars, normalized: normalized,
                            now: TestSupport.date("2026-09-27T10:30"), settings: ParserSettings(),
                            calendar: TestSupport.calendar)
    }

    func spelled(_ n: Int, separator: String = " ") -> String {
        let tens = NumberTests.tensWords[n / 10]
        let unit = NumberTests.unitWords[n % 10]
        if tens.isEmpty {
            return unit
        }
        if unit.isEmpty {
            return tens
        }
        return tens + separator + unit
    }

    func testEveryCardinalAsWords() {
        for n in 1...99 {
            let text = spelled(n)
            let ctx = context(text)
            let phrase = ctx.numberPhrase(at: 0)
            XCTAssertEqual(phrase?.value, n, "'\(text)'")
            XCTAssertEqual(phrase?.end, ctx.count - 1, "'\(text)' must be read completely")
            XCTAssertEqual(phrase?.suffix, "", "'\(text)'")
        }
    }

    func testEveryCardinalAsOneWord() {
        for n in 11...99 where n % 10 != 0 {
            let text = spelled(n, separator: "")
            XCTAssertEqual(TurkishNumbers.parseWord(TurkishText.lower(text))?.value, n, "'\(text)'")
        }
    }

    func testDigitsKeepTheirSuffix() {
        let ctx = context("15'inde 3te 20'si")
        XCTAssertEqual(ctx.numberPhrase(at: 0)?.value, 15)
        XCTAssertEqual(ctx.numberPhrase(at: 0)?.suffix, "inde")
        XCTAssertEqual(ctx.numberPhrase(at: 1)?.value, 3)
        XCTAssertEqual(ctx.numberPhrase(at: 1)?.suffix, "te")
        XCTAssertEqual(ctx.numberPhrase(at: 2)?.suffix, "si")
    }

    func testSuffixedWordForms() {
        let cases: [(String, Int, String)] = [
            ("üçte", 3, "te"), ("dörtte", 4, "te"), ("dörde", 4, "e"), ("beşi", 5, "i"), ("altıya", 6, "ya"),
            ("dokuzu", 9, "u"), ("ikisinde", 2, "sinde"), ("otuzunda", 30, "unda"), ("birinci", 1, "inci"),
            ("üçüncü", 3, "uncu"), ("onuncu", 10, "uncu"), ("ikide", 2, "de"), ("ona", 10, "a"), ("biri", 1, "i")
        ]
        for (word, value, suffix) in cases {
            let parsed = TurkishNumbers.parseWord(TurkishText.lower(word))
            XCTAssertEqual(parsed?.value, value, word)
            XCTAssertEqual(parsed?.suffix, suffix, word)
        }
    }

    func testTwoWordPhrasesCarryTheLastSuffix() {
        let a = context("on beşinde").numberPhrase(at: 0)
        XCTAssertEqual(a?.value, 15)
        XCTAssertEqual(a?.suffix, "inde")
        let b = context("yirmi birinde").numberPhrase(at: 0)
        XCTAssertEqual(b?.value, 21)
        XCTAssertEqual(b?.suffix, "inde")
        let c = context("on biri").numberPhrase(at: 0)
        XCTAssertEqual(c?.value, 11)
        XCTAssertEqual(c?.suffix, "i")
    }

    func testOrdinaryWordsAreNotNumbers() {
        for word in ["altında", "onay", "birlikte", "önde", "biraz", "ondalık", "üçgen", "yedik"] {
            XCTAssertNil(TurkishNumbers.parseWord(TurkishText.lower(word)), word)
        }
    }

    func testDurations() {
        XCTAssertEqual(context("bir buçuk saat").durationPhrase(at: 0)?.minutes, 90)
        XCTAssertEqual(context("yarım saat").durationPhrase(at: 0)?.minutes, 30)
        XCTAssertEqual(context("çeyrek saat").durationPhrase(at: 0)?.minutes, 15)
        XCTAssertEqual(context("1,5 saat").durationPhrase(at: 0)?.minutes, 90)
        XCTAssertEqual(context("1 saat 20 dakika").durationPhrase(at: 0)?.minutes, 80)
        XCTAssertEqual(context("bir saat yirmi dakika").durationPhrase(at: 0)?.minutes, 80)
        XCTAssertEqual(context("45 dk").durationPhrase(at: 0)?.minutes, 45)
        let weeks = context("iki hafta").durationPhrase(at: 0)
        XCTAssertEqual(weeks?.days, 14)
        XCTAssertEqual(weeks?.isCalendar, true)
        let dative = context("on dakikaya").durationPhrase(at: 0)
        XCTAssertEqual(dative?.minutes, 10)
        XCTAssertEqual(dative?.unitSuffix, "ya")
        XCTAssertEqual(context("bir ay").durationPhrase(at: 0)?.months, 1)
        XCTAssertEqual(context("iki yıl").durationPhrase(at: 0)?.years, 2)
        XCTAssertNil(context("yarım gün").durationPhrase(at: 0))
        XCTAssertNil(context("3 teklif").durationPhrase(at: 0))
    }

    func testClockPhrases() {
        let parser = TurkishParser(settings: ParserSettings(), calendar: TestSupport.calendar)
        let now = TestSupport.date("2026-09-27T10:30")
        let cases: [(String, String)] = [
            ("yarın üçü çeyrek geçe toplantı", "2026-09-28T15:15"),
            ("yarın dörde çeyrek var toplantı", "2026-09-28T15:45"),
            ("yarın beşe on kala toplantı", "2026-09-28T16:50"),
            ("yarın saat on beş otuzda toplantı", "2026-09-28T15:30"),
            ("yarın dokuz kırk beşte toplantı", "2026-09-28T09:45"),
            ("yarın saat yarımda toplantı", "2026-09-28T12:30"),
            ("yarın bir buçuğa toplantı", "2026-09-28T13:30"),
            ("yarın saat 3 toplantı", "2026-09-28T15:00"),
            ("yarın 4'ü 10 geçe toplantı", "2026-09-28T16:10"),
            ("yarın ona yirmi kala toplantı", "2026-09-28T09:40"),
            ("yarın saat birde toplantı", "2026-09-28T13:00"),
            ("yarın öğlen birde toplantı", "2026-09-28T13:00"),
            ("yarın saat 2 30'da test", "2026-09-28T14:30")
        ]
        for (text, expected) in cases {
            let due = parser.parse(text, now: now).item?.dueDate
            XCTAssertEqual(due.map { TestSupport.format($0) }, expected, text)
        }
    }

    func testBareNumberIsNotAClock() {
        let parser = TurkishParser(settings: ParserSettings(), calendar: TestSupport.calendar)
        let result = parser.parse("3 teklif hazırla", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertNil(result.item?.dueDate)
        XCTAssertTrue(result.flags.contains(.unusedNumber))
        XCTAssertEqual(result.item?.title, "3 teklif hazırla")
    }

    func testBirDeIsTheFillerAlso() {
        let parser = TurkishParser(settings: ParserSettings(), calendar: TestSupport.calendar)
        let result = parser.parse("bir de yarın Mehmet'e çizimleri sor", now: TestSupport.date("2026-09-27T10:30"))
        XCTAssertEqual(result.item?.title, "Mehmet'e çizimleri sor")
        XCTAssertEqual(result.item?.dueDate.map { TestSupport.format($0) }, "2026-09-28T09:00")
    }
}
