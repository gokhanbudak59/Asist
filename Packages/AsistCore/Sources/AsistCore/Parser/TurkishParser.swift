// API: Packages/AsistCore/Sources/AsistCore/Parser/TurkishParser.swift
// WP0 STUB (04 §3.4.3, shipped verbatim) — WP1 replaces this file with the 02 §2 pipeline.
import Foundation

public struct TurkishParser {
    public let settings: ParserSettings
    public let calendar: Calendar

    public init(settings: ParserSettings = ParserSettings(), calendar: Calendar = TurkishParser.defaultCalendar()) {
        self.settings = settings
        self.calendar = calendar
    }

    /// Pure: depends only on (text, now, settings, calendar). Never reads Date()/Locale.current/TimeZone.current.
    public func parse(_ text: String, now: Date) -> ParseResult {
        // WP0 STUB — replaced by WP1 (02 §2 pipeline).
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Not" : TurkishText.upperFirst(trimmed)
        let item = ParsedItem(kind: .note, title: title, body: trimmed)
        return ParseResult(kind: .note, item: item, command: nil, confidence: 0.55, flags: [.noKindCue],
                           understood: "Not — " + title, relativePhrase: nil, originalText: text,
                           normalizedText: trimmed)
    }

    public static func defaultCalendar() -> Calendar {
        AsistCalendar.make(timeZone: AsistCalendar.istanbul)
    }
}
