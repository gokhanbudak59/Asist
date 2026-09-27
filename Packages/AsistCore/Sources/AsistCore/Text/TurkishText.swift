// FILE: Packages/AsistCore/Sources/AsistCore/Text/TurkishText.swift
import Foundation

/// Locale-free Turkish casing and folding (identical on Linux and iOS; never uses tr_TR locale data).
public enum TurkishText {
    /// "IŞIK" → "ışık", "İzmir" → "izmir".
    public static func lower(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.precomposedStringWithCanonicalMapping {
            switch ch {
            case "I": out.append("ı")
            case "İ": out.append("i")
            default: out.append(contentsOf: String(ch).lowercased())
            }
        }
        return out
    }

    /// "istanbul" → "İSTANBUL", "ılık" → "ILIK".
    public static func upper(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.precomposedStringWithCanonicalMapping {
            switch ch {
            case "i": out.append("İ")
            case "ı": out.append("I")
            default: out.append(contentsOf: String(ch).uppercased())
            }
        }
        return out
    }

    /// First character upper-cased with Turkish rules, rest unchanged.
    public static func upperFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return upper(String(first)) + String(s.dropFirst())
    }

    /// Lowercase + diacritic fold: ç→c ğ→g ı→i ö→o ş→s ü→u â→a î→i û→u (02 §3.2).
    public static func fold(_ s: String) -> String {
        var out = ""
        for ch in lower(s) {
            switch ch {
            case "ç": out.append("c")
            case "ğ": out.append("g")
            case "ı": out.append("i")
            case "ö": out.append("o")
            case "ş": out.append("s")
            case "ü": out.append("u")
            case "â": out.append("a")
            case "î": out.append("i")
            case "û": out.append("u")
            case "i\u{0307}": out.append("i")
            default: out.append(ch)
            }
        }
        return out
    }

    /// Search/match key: fold, apostrophes removed, punctuation → space, single spaces, trimmed.
    public static func searchKey(_ s: String) -> String {
        var out = ""
        var lastWasSpace = true
        for ch in fold(s) {
            if ch == "'" || ch == "’" || ch == "‘" || ch == "`" || ch == "´" {
                continue
            }
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        while out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    /// Cuts at the last word boundary ≤ `max` characters and appends "…".
    public static func truncated(_ s: String, max: Int) -> String {
        guard s.count > max, max > 1 else { return s }
        let prefix = String(s.prefix(max - 1))
        if let space = prefix.lastIndex(of: " "), prefix.distance(from: prefix.startIndex, to: space) > max / 2 {
            return String(prefix[prefix.startIndex..<space]) + "…"
        }
        return prefix + "…"
    }
}
