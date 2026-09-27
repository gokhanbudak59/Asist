// FILE: Packages/AsistCore/Sources/AsistCore/Planning/PlannedNotification.swift
import Foundation

public struct PlannedNotification: Equatable, Hashable {
    public enum Rule: Equatable, Hashable {
        case once
        /// Repeats every day at hour:minute (wall clock, no time zone component).
        case daily(hour: Int, minute: Int)
        /// Foundation weekday (1 = Sunday … 7 = Saturday).
        case weekly(weekday: Int, hour: Int, minute: Int)
        /// Repeats every month on `day` (1…28 only) at hour:minute (recurrence carriers, D27).
        case monthly(day: Int, hour: Int, minute: Int)

        public var stableDescription: String {
            switch self {
            case .once: return "once"
            case .daily(let h, let m): return "daily-\(h):\(m)"
            case .weekly(let w, let h, let m): return "weekly-\(w)-\(h):\(m)"
            case .monthly(let d, let h, let m): return "monthly-\(d)-\(h):\(m)"
            }
        }
    }

    public enum Interruption: String, Equatable, Hashable { case passive, active, timeSensitive }

    public enum Kind: String, Equatable, Hashable {
        case first, nag, preAlert, longTail, occurrence, carrier, briefing, endOfDay, backup, signing, sentinel, horizon
    }

    public var id: String
    public var kind: Kind
    public var itemID: UUID?
    public var attempt: Int
    /// For repeating rules: the first expected fire (sorting/tiering only).
    public var fireDate: Date
    public var rule: Rule
    public var title: String
    public var subtitle: String
    public var body: String
    public var threadID: String
    public var categoryID: String
    /// Projected badge at fire time; nil for repeating rules (leave badge unchanged).
    public var badge: Int?
    public var interruption: Interruption
    public var relevance: Double
    public var playsSound: Bool
    /// Bundled sound file name ("asist-onemli.wav", "asist-kritik.wav"); nil = system default (D37).
    public var soundName: String?
    /// 0 = most important (kept first under budget pressure).
    public var tier: Int
    public var fingerprint: String

    public init(id: String, kind: Kind, itemID: UUID?, attempt: Int, fireDate: Date, rule: Rule,
                title: String, subtitle: String, body: String, threadID: String, categoryID: String,
                badge: Int?, interruption: Interruption, relevance: Double, playsSound: Bool, tier: Int,
                soundName: String? = nil) {
        self.id = id
        self.kind = kind
        self.itemID = itemID
        self.attempt = attempt
        self.fireDate = fireDate
        self.rule = rule
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.threadID = threadID
        self.categoryID = categoryID
        self.badge = badge
        self.interruption = interruption
        self.relevance = relevance
        self.playsSound = playsSound
        self.soundName = soundName
        self.tier = tier
        self.fingerprint = ""
        self.fingerprint = computeFingerprint()
    }

    /// Everything that affects the system request. Repeating rules ignore fireDate/badge.
    public func computeFingerprint() -> String {
        let repeating = rule != .once
        let time = repeating ? 0 : Int(fireDate.timeIntervalSince1970)
        let badgeText = repeating ? "-" : String(badge ?? -1)
        let raw = [id, String(time), rule.stableDescription, title, subtitle, body, badgeText, categoryID,
                   threadID, interruption.rawValue, playsSound ? "s" : "q", soundName ?? "-"].joined(separator: "|")
        return StableHash.fnv1a64(raw)
    }

    public mutating func refreshFingerprint() {
        fingerprint = computeFingerprint()
    }
}

public struct PlanInput {
    public static let defaultReservedSlots = 14

    public var items: [Item]
    public var projects: [Project]
    public var places: [Place]
    public var settings: AppSettings
    public var now: Date
    public var calendar: Calendar
    /// Profile expiry; nil when the embedded profile is unreadable (then no signing notifications, no clamp).
    public var signingExpiry: Date?
    /// Pending `asist.loc.*` requests (v1.2; always 0 in v1.0).
    public var locationSlotsUsed: Int
    /// false when UNNotificationSettings.timeSensitiveSetting != .enabled → every .timeSensitive becomes .active (05b B7).
    public var allowTimeSensitive: Bool
    public var totalBudget: Int
    public var reservedSlots: Int
    /// Trigger dates of the pending chain-nag requests (`NotificationID.chain`, k ≥ 1), keyed by id; empty = none
    /// known. DEVIATION(04 §6.4 step 1b): a nag the rate limiter shifted past its chain date stays planned at its
    /// pending date (≤ 15 min later) instead of being removed by a reconcile that runs between the two dates.
    public var pendingNagDates: [String: Date]

    public init(items: [Item], projects: [Project], places: [Place], settings: AppSettings, now: Date,
                calendar: Calendar, signingExpiry: Date?, locationSlotsUsed: Int = 0,
                allowTimeSensitive: Bool = true, totalBudget: Int = 64,
                reservedSlots: Int = PlanInput.defaultReservedSlots, pendingNagDates: [String: Date] = [:]) {
        self.items = items
        self.projects = projects
        self.places = places
        self.settings = settings
        self.now = now
        self.calendar = calendar
        self.signingExpiry = signingExpiry
        self.locationSlotsUsed = locationSlotsUsed
        self.allowTimeSensitive = allowTimeSensitive
        self.totalBudget = totalBudget
        self.reservedSlots = reservedSlots
        self.pendingNagDates = pendingNagDates
    }

    /// Slots available to item notifications (chain, day-tail, pre-alerts, long-tails, occurrences, carriers).
    public var itemBudget: Int { max(0, totalBudget - reservedSlots - locationSlotsUsed) }
}

public struct PlanResult: Equatable {
    /// Item notifications (≤ itemBudget) + reserved ones (≤ reservedSlots). Sorted by (tier, fireDate, id).
    public var notifications: [PlannedNotification]
    /// Budget drops of tiers 0…3 (tier-4 far-future drops and rate-limited nags are not counted).
    public var droppedCount: Int
    public var earliestDroppedDate: Date?
    /// Nags removed by the rate limiter (§6.4 step 5; diagnostics only).
    public var rateLimitedCount: Int
    /// Badge to set now (respecting BadgeMode).
    public var badgeNow: Int
    public var itemBudget: Int

    public init(notifications: [PlannedNotification], droppedCount: Int, earliestDroppedDate: Date?,
                rateLimitedCount: Int, badgeNow: Int, itemBudget: Int) {
        self.notifications = notifications
        self.droppedCount = droppedCount
        self.earliestDroppedDate = earliestDroppedDate
        self.rateLimitedCount = rateLimitedCount
        self.badgeNow = badgeNow
        self.itemBudget = itemBudget
    }
}
