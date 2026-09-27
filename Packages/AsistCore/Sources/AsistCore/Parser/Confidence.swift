// Confidence — 02 §12: clamp(certainty(tier) − Σ penalty(flag), 0, 1), rounded to 2 decimals.
// Computed in hundredths so thresholds (0.80 / 0.60) compare exactly.
import Foundation

enum Confidence {
    /// Penalty in hundredths per flag (each flag counts once).
    static func penalty(_ flag: ParseFlag) -> Int {
        switch flag {
        case .ambiguousHourPM: return 5
        case .ambiguousHourNearest: return 10
        case .ambiguousDotted: return 15
        case .rolledToTomorrow: return 5
        case .rolledToNextYear: return 5
        case .defaultTimeApplied: return 0
        case .pastDue: return 45
        case .conflictingDates: return 35
        case .invalidDateTime: return 30
        case .needsTime: return 15
        case .unsupportedRecurrence: return 40
        case .multipleItems: return 25
        case .unknownPlace: return 25
        case .uncertainPerson: return 5
        case .negation: return 40
        case .titleFallback: return 40
        case .vagueDate: return 10
        case .noKindCue: return 0
        case .tooShort: return 20
        case .tooLong: return 10
        case .unusedNumber: return 10
        case .smartModeSuggested: return 0
        // P2: the cap to 0.79 is applied separately.
        case .nextWeekAmbiguous: return 0
        // G8: a spoken correction is honoured but slightly lowers certainty.
        case .correctionApplied: return 5
        }
    }

    /// `certainty` in hundredths. Commands never pay titleFallback / tooShort / unusedNumber (02 §12).
    static func score(certainty: Int, flags: Set<ParseFlag>, isCommand: Bool, capAt cap: Int? = nil) -> Double {
        var total = certainty
        for flag in flags {
            if isCommand && (flag == .titleFallback || flag == .tooShort || flag == .unusedNumber) {
                continue
            }
            total -= penalty(flag)
        }
        total = max(0, min(100, total))
        if flags.contains(.nextWeekAmbiguous) {
            total = min(total, 79)
        }
        if let limit = cap {
            total = min(total, limit)
        }
        return Double(total) / 100.0
    }
}
