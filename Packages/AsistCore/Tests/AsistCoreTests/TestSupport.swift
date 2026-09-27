// FILE: Packages/AsistCore/Tests/AsistCoreTests/TestSupport.swift
import Foundation
import XCTest
@testable import AsistCore

enum TestSupport {
    static let calendar: Calendar = TurkishParser.defaultCalendar()

    /// "2026-09-27T10:30" interpreted in `calendar` (Europe/Istanbul). Traps on malformed input (tests only).
    static func date(_ s: String, calendar: Calendar = TestSupport.calendar) -> Date {
        let parts = s.split(separator: "T")
        let d = parts[0].split(separator: "-").compactMap { Int($0) }
        let t = parts.count > 1 ? parts[1].split(separator: ":").compactMap { Int($0) } : [0, 0]
        var comps = DateComponents()
        comps.year = d[0]; comps.month = d[1]; comps.day = d[2]
        comps.hour = t[0]; comps.minute = t[1]; comps.second = 0
        return calendar.date(from: comps)!
    }

    /// "yyyy-MM-dd'T'HH:mm" in `calendar`.
    static func format(_ date: Date, calendar: Calendar = TestSupport.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return AsistCalendar.pad(c.year!, 4) + "-" + AsistCalendar.pad(c.month!, 2) + "-" + AsistCalendar.pad(c.day!, 2)
            + "T" + AsistCalendar.pad(c.hour!, 2) + ":" + AsistCalendar.pad(c.minute!, 2)
    }

    /// Repository file `docs/design/parser_corpus.json`, located from this source file (D24).
    static var corpusURL: URL {
        designDirectory.appendingPathComponent("parser_corpus.json")
    }

    /// `docs/design/parser_corpus_extra.json` (05b cases, gate rules §3.4.6).
    static var corpusExtraURL: URL {
        designDirectory.appendingPathComponent("parser_corpus_extra.json")
    }

    private static var designDirectory: URL {
        URL(fileURLWithPath: #filePath)                 // …/Packages/AsistCore/Tests/AsistCoreTests/TestSupport.swift
            .deletingLastPathComponent()                 // AsistCoreTests
            .deletingLastPathComponent()                 // Tests
            .deletingLastPathComponent()                 // AsistCore
            .deletingLastPathComponent()                 // Packages
            .deletingLastPathComponent()                 // repo root
            .appendingPathComponent("docs/design", isDirectory: true)
    }
}
