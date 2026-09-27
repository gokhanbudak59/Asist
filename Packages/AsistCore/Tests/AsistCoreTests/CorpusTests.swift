import Foundation
import XCTest
@testable import AsistCore

/// 02 §15 harness over `docs/design/parser_corpus.json` and `parser_corpus_extra.json` (04 §3.4.6 gate, D24).
/// Every failing field is printed as `CORPUS failed <id> … field= expected= actual=`, followed by a per-file and
/// per-tag summary; the test fails when any non-deferred case fails.
final class CorpusTests: XCTestCase {

    /// Extra-corpus ids that may fail without failing the gate (≤ 6, each with a one-line reason; 04 §3.4.6).
    /// Deferred cases are still run and reported as warnings — never silently skipped.
    static let deferredExtraCases: [String: String] = [:]

    // MARK: - Corpus model

    struct CorpusFile: Decodable {
        let referenceNows: [String: String]
        let settings: CorpusSettings
        let cases: [CorpusCase]
    }

    struct CorpusSettings: Decodable {
        let defaultDayTime: String?
        let sabah: String?
        let ogledenOnce: String?
        let ogle: String?
        let ogledenSonra: String?
        let aksamustu: String?
        let aksam: String?
        let gece: String?
        let mesaiBasi: String?
        let mesaiBitimi: String?
        let birazdanMinutes: Int?
        let hemenMinutes: Int?
        let belirsizSaatlerOgledenSonra: Bool?
        let smartModeThreshold: Double?
        let autoSaveThreshold: Double?
        let knownProjects: [String]?
        let knownPlaces: [String]?
        let knownPeople: [String]?
    }

    struct CorpusCase: Decodable {
        let id: String
        let now: String
        let input: String
        let tags: [String]?
        let expected: CorpusExpected
    }

    struct CorpusRecurrence: Decodable, Equatable {
        let freq: String
        let interval: Int?
        let weekdays: [Int]?
        let monthDay: Int?
        let month: Int?
    }

    struct CorpusPlace: Decodable {
        let name: String
        let trigger: String
    }

    /// Only keys present in the expectation are compared (`"query": null` present = queryText must be nil).
    struct CorpusCommand: Decodable {
        let type: String
        let scope: String?
        let hasScope: Bool
        let date: String?
        let hasDate: Bool
        let query: String?
        let hasQuery: Bool
        let snoozeMinutes: Int?
        let hasSnoozeMinutes: Bool
        let targetDate: String?
        let hasTargetDate: Bool

        enum CodingKeys: String, CodingKey {
            case type, scope, date, query, snoozeMinutes, targetDate
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            hasScope = c.contains(.scope)
            scope = try c.decodeIfPresent(String.self, forKey: .scope)
            hasDate = c.contains(.date)
            date = try c.decodeIfPresent(String.self, forKey: .date)
            hasQuery = c.contains(.query)
            query = try c.decodeIfPresent(String.self, forKey: .query)
            hasSnoozeMinutes = c.contains(.snoozeMinutes)
            snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes)
            hasTargetDate = c.contains(.targetDate)
            targetDate = try c.decodeIfPresent(String.self, forKey: .targetDate)
        }
    }

    struct CorpusExpected: Decodable {
        let kind: String
        let title: String?
        let due: String?
        let recurrence: CorpusRecurrence?
        let priority: String?
        let person: String?
        let project: String?
        let place: CorpusPlace?
        let command: CorpusCommand?
        let minConfidence: Double?
        let maxConfidence: Double?
        let leadMinutes: [Int]?
    }

    struct FieldDiff {
        let field: String
        let expected: String
        let actual: String
    }

    // MARK: - Tests

    func testMainCorpus() throws {
        let failures = try runCorpus(url: TestSupport.corpusURL, deferred: [:])
        if !failures.isEmpty {
            XCTFail("parser_corpus.json: \(failures.count) case(s) failed: " + failures.prefix(25).joined(separator: ", "))
        }
    }

    func testExtraCorpus() throws {
        XCTAssertLessThanOrEqual(CorpusTests.deferredExtraCases.count, 6, "at most 6 deferred extra cases (04 §3.4.6)")
        let failures = try runCorpus(url: TestSupport.corpusExtraURL, deferred: CorpusTests.deferredExtraCases)
        if !failures.isEmpty {
            XCTFail("parser_corpus_extra.json: \(failures.count) case(s) failed: "
                    + failures.prefix(25).joined(separator: ", "))
        }
    }

    // MARK: - Harness

    /// Runs one corpus file; returns the ids of failing, non-deferred cases.
    func runCorpus(url: URL, deferred: [String: String]) throws -> [String] {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(CorpusFile.self, from: data)
        let settings = parserSettings(file.settings)
        let parser = TurkishParser(settings: settings, calendar: TestSupport.calendar)
        let fileName = url.lastPathComponent
        var failing: [String] = []
        var deferredFailing: [String] = []
        var tagFailures: [String: Int] = [:]
        var tagTotals: [String: Int] = [:]
        for testCase in file.cases {
            for tag in testCase.tags ?? [] {
                tagTotals[tag, default: 0] += 1
            }
            guard let nowText = file.referenceNows[testCase.now] else {
                print("CORPUS failed \(testCase.id): unknown reference now '\(testCase.now)'")
                failing.append(testCase.id)
                continue
            }
            let now = TestSupport.date(nowText)
            let result = parser.parse(testCase.input, now: now)
            let diffs = compare(testCase.expected, result)
            if diffs.isEmpty {
                if let reason = deferred[testCase.id] {
                    print("CORPUS NOTE \(testCase.id) is deferred (\(reason)) but passes now — remove it from "
                          + "deferredExtraCases.")
                }
                continue
            }
            let isDeferred = deferred[testCase.id] != nil
            // One self-contained line per field; "failed" is matched by Scripts/ci/error-summary.sh.
            let label = isDeferred ? "CORPUS warning (deferred: \(deferred[testCase.id] ?? ""))" : "CORPUS failed"
            for diff in diffs {
                print("\(label) \(testCase.id) [\(testCase.now)] field=\(diff.field) expected=\(diff.expected) "
                      + "actual=\(diff.actual) input=\"\(testCase.input)\"")
            }
            print("CORPUS detail \(testCase.id) [\(nowText)] -> " + describe(result))
            if isDeferred {
                deferredFailing.append(testCase.id)
            } else {
                failing.append(testCase.id)
                for tag in testCase.tags ?? [] {
                    tagFailures[tag, default: 0] += 1
                }
            }
        }
        let passed = file.cases.count - failing.count - deferredFailing.count
        print("CORPUS SUMMARY \(fileName): \(passed)/\(file.cases.count) passed, \(failing.count) failed, "
              + "\(deferredFailing.count) deferred failures")
        if !tagFailures.isEmpty {
            let lines = tagFailures.sorted { $0.key < $1.key }.map { entry -> String in
                "\(entry.key) \(entry.value)/\(tagTotals[entry.key] ?? 0)"
            }
            print("CORPUS TAGS \(fileName) failing: " + lines.joined(separator: ", "))
        }
        return failing
    }

    func parserSettings(_ s: CorpusSettings) -> ParserSettings {
        var settings = ParserSettings()
        if let value = clock(s.defaultDayTime) { settings.defaultDayTime = value }
        if let value = clock(s.sabah) { settings.sabah = value }
        if let value = clock(s.ogledenOnce) { settings.ogledenOnce = value }
        if let value = clock(s.ogle) { settings.ogle = value }
        if let value = clock(s.ogledenSonra) { settings.ogledenSonra = value }
        if let value = clock(s.aksamustu) { settings.aksamustu = value }
        if let value = clock(s.aksam) { settings.aksam = value }
        if let value = clock(s.gece) { settings.gece = value }
        if let value = clock(s.mesaiBasi) { settings.mesaiBasi = value }
        if let value = clock(s.mesaiBitimi) { settings.mesaiBitimi = value }
        if let value = s.birazdanMinutes { settings.birazdanMinutes = value }
        if let value = s.hemenMinutes { settings.hemenMinutes = value }
        if let value = s.belirsizSaatlerOgledenSonra { settings.belirsizSaatlerOgledenSonra = value }
        if let value = s.smartModeThreshold { settings.smartModeThreshold = value }
        if let value = s.autoSaveThreshold { settings.autoSaveThreshold = value }
        settings.knownProjects = s.knownProjects ?? []
        settings.knownPlaces = s.knownPlaces ?? []
        settings.knownPeople = s.knownPeople ?? []
        return settings
    }

    func clock(_ text: String?) -> ClockTime? {
        guard let value = text else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return ClockTime(parts[0], parts[1])
    }

    func show(_ value: String?) -> String {
        guard let text = value else { return "nil" }
        return "\"" + text + "\""
    }

    func day(_ date: Date?) -> String? {
        guard let value = date else { return nil }
        return String(TestSupport.format(value).prefix(10))
    }

    /// Turkish lowercase + whitespace collapse (02 §15 `query` rule).
    func collapse(_ text: String?) -> String? {
        guard let value = text else { return nil }
        return TurkishText.lower(value).split(separator: " ").joined(separator: " ")
    }

    func recurrenceText(_ r: CorpusRecurrence?) -> String {
        guard let rule = r else { return "nil" }
        return "{freq: \(rule.freq), interval: \(rule.interval ?? 1), weekdays: \(String(describing: rule.weekdays)), "
            + "monthDay: \(String(describing: rule.monthDay)), month: \(String(describing: rule.month))}"
    }

    func corpusRecurrence(_ r: Recurrence?) -> CorpusRecurrence? {
        guard let rule = r else { return nil }
        return CorpusRecurrence(freq: rule.frequency.rawValue, interval: rule.interval, weekdays: rule.weekdays,
                                monthDay: rule.monthDay, month: rule.month)
    }

    func describe(_ result: ParseResult) -> String {
        var parts: [String] = ["kind=\(result.kind.rawValue)", "confidence=\(result.confidence)"]
        if let item = result.item {
            parts.append("title=\"\(item.title)\"")
            parts.append("due=" + (item.dueDate.map { TestSupport.format($0) } ?? "nil"))
        }
        if let command = result.command {
            parts.append("command=\(command.type.rawValue)/\(command.scope?.rawValue ?? "-")")
            parts.append("query=" + show(command.queryText))
            parts.append("date=" + (command.date.map { TestSupport.format($0) } ?? "nil"))
        }
        parts.append("flags=" + result.flags.map { $0.rawValue }.sorted().joined(separator: ","))
        parts.append("understood=\"\(result.understood)\"")
        return parts.joined(separator: " ")
    }

    func compare(_ expected: CorpusExpected, _ result: ParseResult) -> [FieldDiff] {
        var diffs: [FieldDiff] = []
        func add(_ field: String, _ e: String, _ a: String) {
            diffs.append(FieldDiff(field: field, expected: e, actual: a))
        }
        if result.kind.rawValue != expected.kind {
            add("kind", expected.kind, result.kind.rawValue)
        }
        let item = result.item
        let command = result.command
        if let title = expected.title, expected.kind != "command", item?.title != title {
            add("title", show(title), show(item?.title))
        }
        // due: item.dueDate, or command.date for snooze; query/complete/cancel commands have no due.
        var actualDue: Date? = item?.dueDate
        if let cmd = command {
            actualDue = cmd.type == .snooze ? cmd.date : nil
        }
        let actualDueText = actualDue.map { TestSupport.format($0) }
        if actualDueText != expected.due {
            add("due", show(expected.due), show(actualDueText))
        }
        let actualRecurrence = command == nil ? corpusRecurrence(item?.recurrence) : nil
        let expectedRecurrence = expected.recurrence.map { rule -> CorpusRecurrence in
            CorpusRecurrence(freq: rule.freq, interval: rule.interval ?? 1, weekdays: rule.weekdays,
                             monthDay: rule.monthDay, month: rule.month)
        }
        if actualRecurrence != expectedRecurrence {
            add("recurrence", recurrenceText(expectedRecurrence), recurrenceText(actualRecurrence))
        }
        if let item = item {
            let expectedPriority = expected.priority ?? "normal"
            if item.priority.code != expectedPriority {
                add("priority", expectedPriority, item.priority.code)
            }
        }
        let actualPerson = command != nil ? command?.person : item?.person
        if actualPerson != expected.person {
            add("person", show(expected.person), show(actualPerson))
        }
        let actualProject = command != nil ? command?.project : item?.project
        if actualProject != expected.project {
            add("project", show(expected.project), show(actualProject))
        }
        let actualPlace = command == nil ? item?.place : nil
        let expectedPlaceText = expected.place.map { $0.name + "/" + $0.trigger }
        let actualPlaceText = actualPlace.map { $0.name + "/" + $0.trigger.rawValue }
        if expectedPlaceText != actualPlaceText {
            add("place", show(expectedPlaceText), show(actualPlaceText))
        }
        if let expectedCommand = expected.command {
            if let cmd = command {
                if cmd.type.rawValue != expectedCommand.type {
                    add("command.type", expectedCommand.type, cmd.type.rawValue)
                }
                if expectedCommand.hasScope && cmd.scope?.rawValue != expectedCommand.scope {
                    add("command.scope", show(expectedCommand.scope), show(cmd.scope?.rawValue))
                }
                if expectedCommand.hasDate && day(cmd.date) != expectedCommand.date {
                    add("command.date", show(expectedCommand.date), show(day(cmd.date)))
                }
                if expectedCommand.hasQuery && collapse(cmd.queryText) != collapse(expectedCommand.query) {
                    add("command.query", show(collapse(expectedCommand.query)), show(collapse(cmd.queryText)))
                }
                if expectedCommand.hasSnoozeMinutes && cmd.snoozeMinutes != expectedCommand.snoozeMinutes {
                    add("command.snoozeMinutes", String(describing: expectedCommand.snoozeMinutes),
                        String(describing: cmd.snoozeMinutes))
                }
                if expectedCommand.hasTargetDate && day(cmd.targetDate) != expectedCommand.targetDate {
                    add("command.targetDate", show(expectedCommand.targetDate), show(day(cmd.targetDate)))
                }
            } else {
                add("command", "{type: \(expectedCommand.type)}", "nil")
            }
        } else if command != nil && expected.kind != "command" {
            add("command", "nil", "present")
        }
        if let leads = expected.leadMinutes {
            let actualLeads = item?.leadTimesMinutes ?? []
            if actualLeads != leads {
                add("leadMinutes", "\(leads)", "\(actualLeads)")
            }
        }
        if let minimum = expected.minConfidence, result.confidence + 1e-9 < minimum {
            add("minConfidence", "\(minimum)", "\(result.confidence)")
        }
        if let maximum = expected.maxConfidence, result.confidence - 1e-9 > maximum {
            add("maxConfidence", "\(maximum)", "\(result.confidence)")
        }
        return diffs
    }
}
