// FILE: Packages/AsistCore/Sources/AsistCore/Model/Enums.swift
import Foundation

public enum ItemKind: String, Codable, CaseIterable, Hashable {
    case reminder, task, note, waiting

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ItemKind(rawValue: raw) ?? .task
    }

    public var label: String {
        switch self {
        case .reminder: return "Hatırlatma"
        case .task: return "Görev"
        case .note: return "Not"
        case .waiting: return "Takip"
        }
    }

    public var pluralLabel: String {
        switch self {
        case .reminder: return "Hatırlatmalar"
        case .task: return "Görevler"
        case .note: return "Notlar"
        case .waiting: return "Takip"
        }
    }
}

public enum ItemStatus: String, Codable, CaseIterable, Hashable {
    case open, done, deleted

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ItemStatus(rawValue: raw) ?? .open
    }
}

public enum Priority: Int, Codable, CaseIterable, Comparable, Hashable {
    case low = 0, normal = 1, high = 2, critical = 3

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(Int.self)) ?? 1
        self = Priority(rawValue: raw) ?? .normal
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Corpus / Smart Mode spelling.
    public var code: String {
        switch self {
        case .low: return "low"
        case .normal: return "normal"
        case .high: return "high"
        case .critical: return "critical"
        }
    }

    public init?(code: String) {
        switch code {
        case "low": self = .low
        case "normal": self = .normal
        case "high": self = .high
        case "critical": self = .critical
        default: return nil
        }
    }

    public var label: String {
        switch self {
        case .low: return "Düşük"
        case .normal: return "Normal"
        case .high: return "Önemli"
        case .critical: return "Kritik"
        }
    }
}

public enum PlaceTrigger: String, Codable, CaseIterable, Hashable {
    case onArrive, onLeave

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = PlaceTrigger(rawValue: raw) ?? .onArrive
    }

    public var label: String { self == .onArrive ? "varınca" : "çıkınca" }
}

public enum CaptureSource: String, Codable, CaseIterable, Hashable {
    case voice, keyboard, siri, shortcut, widget, notification, importFile, smartMode, calendar, other

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = CaptureSource(rawValue: raw) ?? .other
    }

    /// Used in history text: "27 Eyl 10:14 · sesle oluşturuldu"
    public var historyLabel: String {
        switch self {
        case .voice: return "sesle"
        case .keyboard: return "klavyeyle"
        case .siri: return "Siri ile"
        case .shortcut: return "kestirmeyle"
        case .widget: return "widget'tan"
        case .notification: return "bildirimden"
        case .importFile: return "içe aktarmayla"
        case .smartMode: return "Akıllı Mod ile"
        case .calendar: return "takvimden"
        case .other: return "elle"
        }
    }
}

public enum NagProfileKind: String, Codable, CaseIterable, Hashable {
    case nazik, israrci, birakmaz, takip, etkinlik

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = NagProfileKind(rawValue: raw) ?? .nazik
    }

    public var label: String {
        switch self {
        case .nazik: return "Nazik"
        case .israrci: return "Israrcı"
        case .birakmaz: return "Bırakmaz"
        case .takip: return "Takip"
        case .etkinlik: return "Etkinlik"
        }
    }

    /// Offered in the per-priority pickers and the detail "Israr düzeyi" menu (takip/etkinlik are automatic).
    public static let selectable: [NagProfileKind] = [.nazik, .israrci, .birakmaz]
}

public enum BadgeMode: String, Codable, CaseIterable, Hashable {
    case overdue, overdueAndToday, off

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = BadgeMode(rawValue: raw) ?? .overdue
    }
}

public enum NoTimeBehavior: String, Codable, CaseIterable, Hashable {
    case ask, inOneHour, thisEvening, tomorrowMorning

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = NoTimeBehavior(rawValue: raw) ?? .ask
    }
}

public enum TTSRate: String, Codable, CaseIterable, Hashable {
    case slow, normal, fast

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = TTSRate(rawValue: raw) ?? .normal
    }
}

public enum HistoryEvent: String, Codable, CaseIterable, Hashable {
    case created, edited, rescheduled, snoozed, done, occurrenceDone, occurrenceMissed
    case reopened, deleted, restored, movedEndOfDay, smartMode, locationFired, other

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = HistoryEvent(rawValue: raw) ?? .other
    }
}

public enum ProjectColor: String, Codable, CaseIterable, Hashable {
    case blue, green, orange, red, purple, teal, pink, brown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ProjectColor(rawValue: raw) ?? .blue
    }
}
