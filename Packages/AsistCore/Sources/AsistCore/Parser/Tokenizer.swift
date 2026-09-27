// Tokenizer — 02 §4 (tokens with root/suffix/number split and original ranges).
import Foundation

/// Numeric shapes of a token root (02 §4 step 5).
enum NumberValue: Equatable {
    case integer(Int)
    case clock(Int, Int)
    case dotted(Int, Int)
    case dottedDate(Int, Int, Int)
    case slashDate(Int, Int, Int?)
    /// "1,5" / "1.5" (duration context only).
    case half(Int)
}

struct Token {
    /// Exact surface form from the normalised text (casing kept, separators removed).
    let original: String
    /// Turkish-lowercased `original`.
    let lower: String
    /// Lowercased + diacritic fold (apostrophes kept).
    let folded: String
    /// Folded part before the apostrophe, or the numeric part of "3te".
    let root: String
    /// Folded part after the apostrophe / after the digits ("" if none).
    let suffix: String
    /// `root + suffix` (folded, no apostrophe).
    let plain: String
    /// Lowercase text before the apostrophe (number words, person values).
    let lowerRoot: String
    /// Original text before the apostrophe.
    let originalRoot: String
    let hadApostrophe: Bool
    /// Apostrophe or digit–letter split ("3'te", "3te").
    let isSplit: Bool
    let number: NumberValue?
    /// "09:30", "08.00" (02 §8.5 leadingZero).
    let leadingZero: Bool
    let isCapitalized: Bool
    /// ≥ 2 letters before the apostrophe, all uppercase ("PLC'yi", "ABB").
    let isAllCaps: Bool
    /// Separator that followed the token (":" "," ";" "!" "?" "." …).
    var trailingPunct: Character?
    /// Character offsets into the normalised text (end exclusive).
    let start: Int
    let end: Int
    let index: Int

    init(text: String, start: Int, end: Int, index: Int) {
        let foldedText = TurkishText.fold(text)
        original = text
        lower = TurkishText.lower(text)
        folded = foldedText
        self.start = start
        self.end = end
        self.index = index
        trailingPunct = nil

        var rootPart = foldedText
        var suffixPart = ""
        var apostrophe = false
        var split = false
        if let apostropheIndex = foldedText.firstIndex(of: "'") {
            rootPart = String(foldedText[foldedText.startIndex..<apostropheIndex])
            let after = String(foldedText[foldedText.index(after: apostropheIndex)...])
            suffixPart = after.replacingOccurrences(of: "'", with: "")
            apostrophe = true
            split = true
        } else if let first = foldedText.first, Normalizer.isDigit(first) {
            var numeric = ""
            var rest = ""
            var inNumber = true
            for ch in foldedText {
                if inNumber && (Normalizer.isDigit(ch) || ch == ":" || ch == "." || ch == "/" || ch == ",") {
                    numeric.append(ch)
                } else {
                    inNumber = false
                    rest.append(ch)
                }
            }
            while let last = numeric.last, !Normalizer.isDigit(last) {
                rest = String(last) + rest
                numeric.removeLast()
            }
            rootPart = numeric
            suffixPart = rest
            split = !rest.isEmpty
        }
        root = rootPart
        suffix = suffixPart
        plain = rootPart + suffixPart
        hadApostrophe = apostrophe
        isSplit = split

        var textRoot = text
        if let apostropheIndex = text.firstIndex(of: "'") {
            textRoot = String(text[text.startIndex..<apostropheIndex])
        }
        originalRoot = textRoot
        let lowered = TurkishText.lower(text)
        var loweredRoot = lowered
        if let apostropheIndex = lowered.firstIndex(of: "'") {
            loweredRoot = String(lowered[lowered.startIndex..<apostropheIndex])
        }
        lowerRoot = loweredRoot

        number = Token.parseNumeric(rootPart)
        let rootChars = Array(rootPart)
        leadingZero = rootChars.count >= 2 && rootChars[0] == "0" && Normalizer.isDigit(rootChars[1])

        var capitalized = false
        if let firstChar = text.first {
            capitalized = firstChar.isLetter && firstChar.isUppercase
        }
        isCapitalized = capitalized
        var letterCount = 0
        var allUpper = true
        for ch in textRoot where ch.isLetter {
            letterCount += 1
            if !ch.isUppercase {
                allUpper = false
            }
        }
        isAllCaps = letterCount >= 2 && allUpper
    }

    var integerValue: Int? {
        if case .integer(let value)? = number {
            return value
        }
        return nil
    }

    // MARK: - Numeric shapes

    static func allDigits(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        for ch in s where !Normalizer.isDigit(ch) {
            return false
        }
        return true
    }

    static func parseNumeric(_ root: String) -> NumberValue? {
        guard let first = root.first, Normalizer.isDigit(first) else { return nil }
        if allDigits(root) {
            guard root.count <= 9, let value = Int(root) else { return nil }
            return .integer(value)
        }
        if root.contains(":") {
            let parts = root.split(separator: ":", omittingEmptySubsequences: false).map { String($0) }
            guard parts.count == 2, allDigits(parts[0]), allDigits(parts[1]), parts[0].count <= 2,
                  parts[1].count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return .clock(h, m)
        }
        if root.contains("/") {
            let parts = root.split(separator: "/", omittingEmptySubsequences: false).map { String($0) }
            guard parts.count == 2 || parts.count == 3 else { return nil }
            for part in parts where !allDigits(part) {
                return nil
            }
            guard parts[0].count <= 2, parts[1].count <= 2, let d = Int(parts[0]), let m = Int(parts[1]) else {
                return nil
            }
            var year: Int? = nil
            if parts.count == 3 {
                guard let y = yearValue(parts[2]) else { return nil }
                year = y
            }
            return .slashDate(d, m, year)
        }
        let separator: Character = root.contains(".") ? "." : ","
        let parts = root.split(separator: separator, omittingEmptySubsequences: false).map { String($0) }
        for part in parts where !allDigits(part) {
            return nil
        }
        if parts.count == 2 {
            if separator == ".", parts[0].count <= 2, parts[1].count == 2, let a = Int(parts[0]), let b = Int(parts[1]) {
                return .dotted(a, b)
            }
            if parts[1] == "5", parts[0].count <= 4, let whole = Int(parts[0]) {
                return .half(whole)
            }
            return nil
        }
        if parts.count == 3, separator == ".", parts[0].count <= 2, parts[1].count <= 2,
           let d = Int(parts[0]), let m = Int(parts[1]), let y = yearValue(parts[2]) {
            return .dottedDate(d, m, y)
        }
        return nil
    }

    /// 2-digit year → 2000 + y; 4-digit as is.
    static func yearValue(_ s: String) -> Int? {
        guard let value = Int(s) else { return nil }
        if s.count == 2 {
            return 2000 + value
        }
        if s.count == 4 {
            return value
        }
        return nil
    }
}

enum Tokenizer {
    static let alwaysSeparators: Set<Character> = [" ", ",", ";", "!", "?", "(", ")", "\"", "«", "»", "…", "[", "]",
                                                   "{", "}", "\u{201C}", "\u{201D}", "\u{201E}"]

    /// Returns the tokens and the character array of `text` (token `start`/`end` index into it).
    static func tokenize(_ text: String) -> (tokens: [Token], chars: [Character]) {
        let chars = Array(text)
        let count = chars.count
        var tokens: [Token] = []
        var current = ""
        var currentStart = 0

        func isSeparator(_ i: Int) -> Bool {
            let ch = chars[i]
            let previousIsDigit = i > 0 && Normalizer.isDigit(chars[i - 1])
            let nextIsDigit = i + 1 < count && Normalizer.isDigit(chars[i + 1])
            if alwaysSeparators.contains(ch) {
                if ch == "," && previousIsDigit && nextIsDigit {
                    return false
                }
                return true
            }
            if ch == "." || ch == ":" {
                return !(previousIsDigit && nextIsDigit)
            }
            if ch == "-" || ch == "–" || ch == "—" {
                let previousIsLetter = i > 0 && chars[i - 1].isLetter
                let nextIsLetter = i + 1 < count && chars[i + 1].isLetter
                return !(previousIsLetter && nextIsLetter)
            }
            return false
        }

        func finish(_ end: Int) {
            var text = current
            var start = currentStart
            var stop = end
            while text.hasPrefix("'") {
                text.removeFirst()
                start += 1
            }
            while text.hasSuffix("'") {
                text.removeLast()
                stop -= 1
            }
            if !text.isEmpty {
                tokens.append(Token(text: text, start: start, end: stop, index: tokens.count))
            }
        }

        var i = 0
        while i < count {
            if isSeparator(i) {
                if !current.isEmpty {
                    finish(i)
                    current = ""
                }
                let ch = chars[i]
                if ch != " ", !tokens.isEmpty, tokens[tokens.count - 1].trailingPunct == nil {
                    tokens[tokens.count - 1].trailingPunct = ch
                }
                i += 1
                continue
            }
            if current.isEmpty {
                currentStart = i
            }
            current.append(chars[i])
            i += 1
        }
        if !current.isEmpty {
            finish(count)
        }
        return (tokens, chars)
    }
}
