// FILE: Packages/AsistCore/Sources/AsistCore/Planning/NotificationCatalog.swift
import Foundation

public enum NotificationID {
    public static let prefix = "asist."
    /// Requests the app schedules ad hoc (test, feedback); never touched by the diff-apply.
    public static let unmanagedPrefix = "asist.x."
    /// Location reminders (07 §9): created only by LocationService; the diff-apply never touches them.
    public static let locationPrefix = "asist.loc."

    public static func chain(_ itemID: UUID, _ k: Int) -> String { "asist.i.\(itemID.uuidString).\(k)" }
    public static func preAlert(_ itemID: UUID, minutes: Int) -> String { "asist.i.\(itemID.uuidString).pre.\(minutes)" }
    public static func longTail(_ itemID: UUID) -> String { "asist.i.\(itemID.uuidString).d" }
    public static func occurrence(_ itemID: UUID, minuteKey: String) -> String { "asist.i.\(itemID.uuidString).o.\(minuteKey)" }
    /// Repeating carrier of future occurrences (D27). suffix: "d" (daily), "w1"…"w7" (Foundation weekday), "m" (monthly).
    public static func carrier(_ itemID: UUID, suffix: String) -> String { "asist.i.\(itemID.uuidString).r.\(suffix)" }
    public static func location(_ itemID: UUID) -> String { "asist.loc.\(itemID.uuidString)" }
    public static func briefing(dayKey: String) -> String { "asist.brief.\(dayKey)" }
    public static func endOfDay(dayKey: String) -> String { "asist.eod.\(dayKey)" }
    public static let backup = "asist.backup"
    public static func signing(minuteKey: String) -> String { "asist.sign.\(minuteKey)" }
    /// Budget sentinel: a copy of the earliest dropped item notification (05b B5); carries that item's iid.
    public static let sentinel = "asist.sentinel"
    /// Horizon sentinel: "Asist'i bir kez aç" after the last planned item notification (05a #23, 05b B3).
    public static let horizonSentinel = "asist.sentinel.h"
    public static let test = "asist.x.test"
    public static let movedFeedback = "asist.x.moved"

    /// thread identifier: all notifications of one item stack together.
    public static func thread(_ itemID: UUID) -> String { "asist.i.\(itemID.uuidString)" }
    public static let digestThread = "asist.digest"
    public static let systemThread = "asist.system"

    /// Item UUID for "asist.i.<UUID>…" and "asist.loc.<UUID>"; nil otherwise.
    public static func itemID(from identifier: String) -> UUID? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "asist", parts[1] == "i" || parts[1] == "loc" else { return nil }
        return UUID(uuidString: String(parts[2]))
    }

    /// Owned by NagPlanner + NotificationScheduler diff-apply.
    public static func isPlannerManaged(_ identifier: String) -> Bool {
        identifier.hasPrefix(prefix) && !identifier.hasPrefix(unmanagedPrefix) && !identifier.hasPrefix(locationPrefix)
    }
}

public enum NotificationCategoryID {
    public static let item = "ASIST_ITEM"
    /// Pre-alerts: only "✓ Yaptım" (+ default tap) — a pre-alert can never snooze/re-anchor the item (05a #13).
    public static let preAlert = "ASIST_PRE"
    public static let followUp = "ASIST_FOLLOWUP"
    public static let briefing = "ASIST_BRIEF"
    public static let endOfDay = "ASIST_EOD"
    public static let system = "ASIST_SYSTEM"
}

public enum NotificationActionID {
    // ASIST_ITEM (background, no unlock); ASIST_PRE uses `done` only
    public static let done = "ASIST_DONE"
    public static let snooze10 = "ASIST_SNOOZE_10"
    public static let snooze60 = "ASIST_SNOOZE_60"
    public static let tomorrow = "ASIST_TOMORROW"
    // ASIST_FOLLOWUP
    public static let followUpReceived = "ASIST_FU_RECEIVED"   // background
    public static let followUpTomorrow = "ASIST_FU_TOMORROW"   // background
    public static let followUpTwoDays = "ASIST_FU_2DAYS"       // background
    public static let followUpMessage = "ASIST_FU_MESSAGE"     // .foreground
    // ASIST_BRIEF
    public static let briefingRead = "ASIST_BRIEF_READ"        // .foreground
    // ASIST_EOD
    public static let endOfDayMove = "ASIST_EOD_MOVE"          // background
    public static let endOfDayReview = "ASIST_EOD_REVIEW"      // .foreground
}

/// userInfo keys (values are String or Int only).
public enum NotificationUserInfoKey {
    public static let itemID = "iid"          // UUID string ("" when none)
    public static let attempt = "k"           // Int
    public static let fingerprint = "fp"      // String
    public static let kind = "nk"             // PlannedNotification.Kind rawValue
}
