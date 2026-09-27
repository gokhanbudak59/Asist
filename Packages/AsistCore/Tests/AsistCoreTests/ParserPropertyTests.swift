import Foundation
import XCTest
@testable import AsistCore

/// 02 §18 property tests: for generated (weekday, qualifier, daypart, hour) combinations the due date is in the
/// future unless `pastDue` is flagged, the spoken minute is kept, the title is never empty; plus robustness.
final class ParserPropertyTests: XCTestCase {
    static let nows = ["2026-09-27T10:30", "2026-09-29T09:15", "2026-09-29T19:40", "2026-10-02T23:10",
                       "2026-09-28T06:05", "2026-12-31T16:00", "2026-10-30T12:00"]
    static let weekdays = ["pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi", "pazar"]
    static let qualifiers = ["", "bu ", "gelecek ", "haftaya "]
    static let dayparts = ["", "sabah ", "akşam "]
    static let hours = [3, 9, 11]

    func makeParser() -> TurkishParser {
        var settings = ParserSettings()
        settings.knownProjects = ["Arka Cep", "Hat 3", "Kaynak Robotu", "Bakım"]
        settings.knownPlaces = ["Fabrika", "Ev", "Ofis"]
        return TurkishParser(settings: settings, calendar: TestSupport.calendar)
    }

    func testGeneratedWeekdayClockCombinations() {
        let parser = makeParser()
        var checked = 0
        var failures: [String] = []
        for nowText in ParserPropertyTests.nows {
            let now = TestSupport.date(nowText)
            for qualifier in ParserPropertyTests.qualifiers {
                for weekday in ParserPropertyTests.weekdays {
                    for daypart in ParserPropertyTests.dayparts {
                        for hour in ParserPropertyTests.hours {
                            let minute = (hour * 7 + weekday.count) % 60
                            // Split + annotated: a 9-operand `+` chain with `String(Int)` risks "expression too complex".
                            let clockText: String = String(hour) + ":" + AsistCalendar.pad(minute, 2)
                            let text: String = qualifier + weekday + " " + daypart + "saat " + clockText + " toplantı"
                            let result = parser.parse(text, now: now)
                            checked += 1
                            guard let item = result.item, let due = item.dueDate else {
                                failures.append("\(text) @ \(nowText): no due")
                                continue
                            }
                            if !(due > now || result.flags.contains(.pastDue)) {
                                failures.append("\(text) @ \(nowText): due \(TestSupport.format(due)) not in future")
                            }
                            if TestSupport.calendar.component(.minute, from: due) != minute {
                                failures.append("\(text) @ \(nowText): minute changed")
                            }
                            if item.title.isEmpty {
                                failures.append("\(text) @ \(nowText): empty title")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 500)
        for failure in failures.prefix(30) {
            print("PROPERTY FAIL " + failure)
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(checked) generated utterances violate a property")
    }

    func testRelativeOffsetsKeepTheMinute() {
        let parser = makeParser()
        let now = TestSupport.date("2026-09-27T10:30")
        for minutes in [1, 5, 10, 15, 25, 45, 59] {
            let result = parser.parse(String(minutes) + " dakika sonra kapıyı kontrol et", now: now)
            XCTAssertEqual(result.item?.dueDate, now.addingTimeInterval(TimeInterval(minutes * 60)), "\(minutes)")
            XCTAssertEqual(result.item?.hasTime, true)
        }
    }

    func testTitlesAreNeverEmptyAndConfidenceIsBounded() {
        let parser = makeParser()
        let now = TestSupport.date("2026-09-27T10:30")
        let inputs = ["", " ", "'", "...", "3'", "saat", "her", "ayın", "yarın", "hmm şey ya", "31/02/2026",
                      "99:99", "saat 25'te", "ayın 99'unda", "🙂", "12.34.5678", "bir de", "ve ve ve",
                      "hatırlat hatırlat hatırlat", "iptal", "not:", "fikir:", "görev:", "bekliyorum:",
                      "Ahmet'e'e", "'''", "0'da", "24:00'te toplantı", "saat 0:15'te kontrol",
                      String(repeating: "çok uzun bir cümle ", count: 30)]
        for input in inputs {
            let result = parser.parse(input, now: now)
            XCTAssertGreaterThanOrEqual(result.confidence, 0, input)
            XCTAssertLessThanOrEqual(result.confidence, 1, input)
            XCTAssertEqual(result.confidence, (result.confidence * 100).rounded() / 100, input)
            if let item = result.item {
                XCTAssertFalse(item.title.isEmpty, "empty title for '\(input)'")
                if let due = item.dueDate {
                    XCTAssertEqual(TestSupport.calendar.component(.second, from: due), 0, input)
                }
            } else {
                XCTAssertNotNil(result.command, input)
            }
            XCTAssertEqual(result.kind == .command, result.command != nil, input)
            XCTAssertEqual(result.smartModeFlagConsistent(threshold: 0.60), true, input)
        }
    }

    /// Reports of something NOT done must never complete an item.
    func testNegativePastIsNeverACompletion() {
        let parser = makeParser()
        let now = TestSupport.date("2026-09-27T10:30")
        for text in ["Ahmet'i aramadım", "raporu gönderemedim", "Ahmet'i aramayı unuttum", "teklifi yapacaktım",
                     "Ahmet'i arıyordum", "teklifi hazırlamalıydım", "on beş ekimde saat 10'da denetim"] {
            let result = parser.parse(text, now: now)
            XCTAssertNotEqual(result.command?.type, .complete, text)
        }
        XCTAssertEqual(parser.parse("raporu yazdım", now: now).command?.type, .complete)
        XCTAssertEqual(parser.parse("sipariş formunu hallettik", now: now).command?.queryText, "sipariş formu")
    }

    func testParseIsPure() {
        let parser = makeParser()
        let now = TestSupport.date("2026-09-29T09:15")
        for text in ["salı günü teklif konusunu bana saat 3'te hatırlat", "her pazartesi ve perşembe 10'da kalite turu",
                     "Ahmet'ten teklif bekliyorum", "yarınki toplantıyı iptal et"] {
            XCTAssertEqual(parser.parse(text, now: now), parser.parse(text, now: now), text)
        }
    }

    func testFoldedTypingGivesTheSameDates() {
        let parser = makeParser()
        let now = TestSupport.date("2026-09-27T10:30")
        let pairs = [("çarşamba 14:30'da tedarikçi toplantısı hatırlat", "carsamba 14:30 da tedarikci toplantisi hatirlat"),
                     ("perşembe öğleden sonra müşteri ziyareti", "persembe ogleden sonra musteri ziyareti"),
                     ("YARIN SAAT 3TE AHMETİ ARA", "yarın saat 3'te ahmeti ara")]
        for (a, b) in pairs {
            XCTAssertEqual(parser.parse(a, now: now).item?.dueDate, parser.parse(b, now: now).item?.dueDate, a)
        }
    }

    func testTimeZoneIsInjected() {
        // The same wall-clock phrase resolves in the injected calendar's zone (D29).
        let utc = AsistCalendar.make(timeZone: TimeZone(secondsFromGMT: 0) ?? AsistCalendar.istanbul)
        let parser = TurkishParser(settings: ParserSettings(), calendar: utc)
        let now = TestSupport.date("2026-09-27T10:30", calendar: utc)
        let result = parser.parse("yarın 15:00'te toplantı", now: now)
        XCTAssertEqual(result.item?.dueDate.map { TestSupport.format($0, calendar: utc) }, "2026-09-28T15:00")
    }
}

private extension ParseResult {
    func smartModeFlagConsistent(threshold: Double) -> Bool {
        return flags.contains(.smartModeSuggested) == (confidence < threshold)
    }
}
