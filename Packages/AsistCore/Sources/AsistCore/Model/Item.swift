// FILE: Packages/AsistCore/Sources/AsistCore/Model/Item.swift
import Foundation

public struct ChecklistEntry: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var text: String
    public var done: Bool

    public init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }

    enum CodingKeys: String, CodingKey { case id, text, done }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, forKey: .id, default: UUID())
        text = c.lenient(String.self, forKey: .text, default: "")
        done = c.lenient(Bool.self, forKey: .done, default: false)
    }
}

public struct HistoryEntry: Codable, Equatable, Hashable {
    public var date: Date
    public var event: HistoryEvent
    public var detail: String?

    public init(date: Date, event: HistoryEvent, detail: String? = nil) {
        self.date = date
        self.event = event
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey { case date, event, detail }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.lenient(Date.self, forKey: .date, default: Date(timeIntervalSince1970: 0))
        event = c.lenient(HistoryEvent.self, forKey: .event, default: .other)
        detail = c.lenientOptional(String.self, forKey: .detail)
    }
}

/// One user record: Hatırlatma / Görev / Not / Takip.
public struct Item: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var kind: ItemKind
    public var title: String
    /// Free-text notes (for notes: the note body).
    public var notes: String
    /// The utterance/typed text the item was created from (always shown in detail).
    public var originalText: String?
    public var status: ItemStatus
    public var priority: Priority
    /// Due instant of the current occurrence (whole minute). nil = "zamanı belirsiz".
    public var dueDate: Date?
    /// false when the time part was a default (09:00 / today policy).
    public var hasTime: Bool
    public var recurrence: Recurrence?
    /// Explicit snooze target; when set it is the nag anchor instead of `dueDate`.
    public var snoozedUntil: Date?
    public var snoozeCount: Int
    /// Pre-alerts in minutes before `dueDate` (e.g. 10, 30, 60, 1440, 10080, 43200).
    public var leadTimesMinutes: [Int]
    /// nil = profile by priority from settings (waiting items always use .takip, events .etkinlik).
    public var nagProfile: NagProfileKind?
    /// Meeting/visit/FAT…: first alert + pre-alert only, never overdue, auto-closed 120 min after start (D31).
    public var isEvent: Bool
    public var person: String?
    public var projectID: UUID?
    public var placeID: UUID?
    public var placeTrigger: PlaceTrigger?
    /// Delivery time of the location notification; anchor of the nag chain for place-only items.
    public var locationFiredAt: Date?
    public var tags: [String]
    public var checklist: [ChecklistEntry]
    /// "Emin değilim" flag (low-confidence capture that nobody confirmed; UI section "EMİN OLAMADIKLARIM").
    public var needsReview: Bool
    public var source: CaptureSource
    public var parseConfidence: Double?
    public var smartModeUsed: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var deletedAt: Date?
    public var lastDismissedAt: Date?
    public var completedOccurrences: Int
    /// Newest last; capped at 50 entries by `appendHistory`.
    public var history: [HistoryEntry]

    public init(id: UUID = UUID(),
                kind: ItemKind,
                title: String,
                notes: String = "",
                originalText: String? = nil,
                status: ItemStatus = .open,
                priority: Priority = .normal,
                dueDate: Date? = nil,
                hasTime: Bool = false,
                recurrence: Recurrence? = nil,
                snoozedUntil: Date? = nil,
                snoozeCount: Int = 0,
                leadTimesMinutes: [Int] = [],
                nagProfile: NagProfileKind? = nil,
                isEvent: Bool = false,
                person: String? = nil,
                projectID: UUID? = nil,
                placeID: UUID? = nil,
                placeTrigger: PlaceTrigger? = nil,
                locationFiredAt: Date? = nil,
                tags: [String] = [],
                checklist: [ChecklistEntry] = [],
                needsReview: Bool = false,
                source: CaptureSource = .other,
                parseConfidence: Double? = nil,
                smartModeUsed: Bool = false,
                createdAt: Date,
                updatedAt: Date? = nil,
                completedAt: Date? = nil,
                deletedAt: Date? = nil,
                lastDismissedAt: Date? = nil,
                completedOccurrences: Int = 0,
                history: [HistoryEntry] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.notes = notes
        self.originalText = originalText
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.recurrence = recurrence
        self.snoozedUntil = snoozedUntil
        self.snoozeCount = snoozeCount
        self.leadTimesMinutes = leadTimesMinutes
        self.nagProfile = nagProfile
        self.isEvent = isEvent
        self.person = person
        self.projectID = projectID
        self.placeID = placeID
        self.placeTrigger = placeTrigger
        self.locationFiredAt = locationFiredAt
        self.tags = tags
        self.checklist = checklist
        self.needsReview = needsReview
        self.source = source
        self.parseConfidence = parseConfidence
        self.smartModeUsed = smartModeUsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.lastDismissedAt = lastDismissedAt
        self.completedOccurrences = completedOccurrences
        self.history = history
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, notes, originalText, status, priority, dueDate, hasTime, recurrence
        case snoozedUntil, snoozeCount, leadTimesMinutes, nagProfile, isEvent, person, projectID, placeID, placeTrigger
        case locationFiredAt, tags, checklist, needsReview, source, parseConfidence, smartModeUsed
        case createdAt, updatedAt, completedAt, deletedAt, lastDismissedAt, completedOccurrences, history
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let epoch = Date(timeIntervalSince1970: 0)
        id = c.lenient(UUID.self, forKey: .id, default: UUID())
        kind = c.lenient(ItemKind.self, forKey: .kind, default: .task)
        title = c.lenient(String.self, forKey: .title, default: "")
        notes = c.lenient(String.self, forKey: .notes, default: "")
        originalText = c.lenientOptional(String.self, forKey: .originalText)
        status = c.lenient(ItemStatus.self, forKey: .status, default: .open)
        priority = c.lenient(Priority.self, forKey: .priority, default: .normal)
        dueDate = c.lenientOptional(Date.self, forKey: .dueDate)
        hasTime = c.lenient(Bool.self, forKey: .hasTime, default: false)
        recurrence = c.lenientOptional(Recurrence.self, forKey: .recurrence)
        snoozedUntil = c.lenientOptional(Date.self, forKey: .snoozedUntil)
        snoozeCount = max(0, c.lenient(Int.self, forKey: .snoozeCount, default: 0))
        let leads = c.lenient([Int].self, forKey: .leadTimesMinutes, default: [])
        leadTimesMinutes = Array(Set(leads.filter { $0 > 0 && $0 <= 527_040 })).sorted()   // ≤ 366 days
        nagProfile = c.lenientOptional(NagProfileKind.self, forKey: .nagProfile)
        isEvent = c.lenient(Bool.self, forKey: .isEvent, default: false)
        person = c.lenientOptional(String.self, forKey: .person)
        projectID = c.lenientOptional(UUID.self, forKey: .projectID)
        placeID = c.lenientOptional(UUID.self, forKey: .placeID)
        placeTrigger = c.lenientOptional(PlaceTrigger.self, forKey: .placeTrigger)
        locationFiredAt = c.lenientOptional(Date.self, forKey: .locationFiredAt)
        tags = c.lenient([String].self, forKey: .tags, default: [])
        checklist = c.lenientOptional(LossyDecodableArray<ChecklistEntry>.self, forKey: .checklist)?.elements ?? []
        needsReview = c.lenient(Bool.self, forKey: .needsReview, default: false)
        source = c.lenient(CaptureSource.self, forKey: .source, default: .other)
        parseConfidence = c.lenientOptional(Double.self, forKey: .parseConfidence)
        smartModeUsed = c.lenient(Bool.self, forKey: .smartModeUsed, default: false)
        createdAt = c.lenient(Date.self, forKey: .createdAt, default: epoch)
        updatedAt = c.lenient(Date.self, forKey: .updatedAt, default: createdAt)
        completedAt = c.lenientOptional(Date.self, forKey: .completedAt)
        deletedAt = c.lenientOptional(Date.self, forKey: .deletedAt)
        lastDismissedAt = c.lenientOptional(Date.self, forKey: .lastDismissedAt)
        completedOccurrences = c.lenient(Int.self, forKey: .completedOccurrences, default: 0)
        history = c.lenientOptional(LossyDecodableArray<HistoryEntry>.self, forKey: .history)?.elements ?? []
    }
}
