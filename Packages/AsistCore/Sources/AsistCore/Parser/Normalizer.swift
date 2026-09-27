// Normalizer — 02 §3 (NFC, apostrophes, whitespace, detached suffix join, trailing punctuation).
import Foundation

enum Normalizer {
    /// Apostrophe look-alikes unified to ASCII "'" (02 §3 step 2).
    static let apostropheVariants: Set<Character> = ["\u{2019}", "\u{2018}", "\u{00B4}", "\u{0060}", "\u{02BC}",
                                                     "\u{2032}", "\u{FF07}"]
    /// Whitespace variants replaced by a plain space (02 §3 step 3).
    static let spaceVariants: Set<Character> = ["\t", "\n", "\r", "\r\n", "\u{00A0}", "\u{202F}", "\u{2007}",
                                                "\u{2009}", "\u{200A}", "\u{2002}", "\u{2003}", "\u{000B}",
                                                "\u{000C}"]
    /// Standalone suffixes joined to a preceding number: "3 te" → "3'te" (02 §3 step 4).
    static let detachedSuffixes: Set<String> = ["te", "ta", "de", "da", "e", "a", "ye", "ya", "i", "ı", "u", "ü",
                                                "yi", "yı", "yu", "yü", "inde", "ında", "unda", "ünde", "nde", "nda"]
    static let trailingPunctuation: Set<Character> = [".", "!", "?", "…", ",", ";", ":"]
    static let leadingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", "-", "–", "—"]

    static func normalize(_ text: String) -> String {
        // 1–3: NFC, apostrophes, whitespace
        var unified = ""
        for ch in text.precomposedStringWithCanonicalMapping {
            if apostropheVariants.contains(ch) {
                unified.append("'")
            } else if spaceVariants.contains(ch) || ch.isNewline {
                unified.append(" ")
            } else {
                unified.append(ch)
            }
        }
        let rawWords = unified.split(separator: " ", omittingEmptySubsequences: true).map { String($0) }

        // Space before an apostrophe: "3 'te" → "3'te"
        var merged: [String] = []
        for word in rawWords {
            if word.hasPrefix("'"), word.count > 1, let last = merged.last, let lastChar = last.last,
               lastChar.isLetter || lastChar.isNumber {
                merged[merged.count - 1] = last + word
            } else {
                merged.append(word)
            }
        }

        // 4: detached suffix after a number
        var words: [String] = []
        for word in merged {
            var core = word
            var tail = ""
            while let last = core.last, trailingPunctuation.contains(last) {
                tail = String(last) + tail
                core.removeLast()
            }
            let lowered = TurkishText.lower(core)
            if let previous = words.last, detachedSuffixes.contains(lowered), isNumericWord(previous) {
                if (lowered == "de" || lowered == "da") && !numberIsClockLike(previous) {
                    words.append(word)
                } else {
                    words[words.count - 1] = previous + "'" + core + tail
                }
            } else {
                words.append(word)
            }
        }

        // 5: trailing punctuation
        var result = words.joined(separator: " ")
        while let last = result.last, trailingPunctuation.contains(last) || last == " " {
            result.removeLast()
        }
        while let first = result.first, leadingPunctuation.contains(first) || first == " " {
            result.removeFirst()
        }
        return result
    }

    static func isDigit(_ ch: Character) -> Bool {
        return ch >= "0" && ch <= "9"
    }

    /// "3", "15:30", "15.30" — digits with optional ":" "." "/" separators, ending in a digit.
    static func isNumericWord(_ word: String) -> Bool {
        guard let first = word.first, isDigit(first), let last = word.last, isDigit(last) else { return false }
        for ch in word where !(isDigit(ch) || ch == ":" || ch == "." || ch == "/") {
            return false
        }
        return true
    }

    /// `de`/`da` are joined only after a number ≤ 24 or a clock-like number (02 §3 step 4 exception).
    static func numberIsClockLike(_ word: String) -> Bool {
        if word.contains(":") || word.contains(".") {
            return true
        }
        guard let value = Int(word) else { return false }
        return value <= 24
    }
}
