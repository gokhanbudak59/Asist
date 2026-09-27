// PlanPostPass.swift — WP3 (04 §6.4 steps 1f, 2, 4, 5, 6, 8, 9): long-tail ranking, signing clamp, reserved
// notifications, rate limiter, tiers + budget, sentinels and output assembly. Internal to AsistCore; pure and
// deterministic (Dictionary/Set iteration order never reaches the output).
import Foundation

// MARK: - Working types

/// A notification under construction. Converted to `PlannedNotification` (which computes the fingerprint) only at
/// the very end, after every field is final.
struct NagPlanCandidate {
    var id: String
    var kind: PlannedNotification.Kind
    /// Index into the planner's item array; nil for reserved notifications.
    var itemSlot: Int?
    var itemID: UUID?
    var attempt: Int
    var fireDate: Date
    var rule: PlannedNotification.Rule
    /// The item's priority (reserved notifications: `.normal`).
    var priority: Priority
    /// Pre-alert lead in minutes (0 for every other kind).
    var leadMinutes: Int
    var threadID: String
    var categoryID: String
    var title: String = ""
    var subtitle: String = ""
    var body: String = ""
    /// true when the last body line is `NotificationCopy.itemContent`'s line 2 (the budget sentinel replaces it).
    var bodyHasFollowLine: Bool = false
    var interruption: PlannedNotification.Interruption = .active
    var relevance: Double = 0.5
    var playsSound: Bool = true
    var soundName: String? = nil
    var tier: Int = 0
    var badge: Int? = nil
    /// `.nag` from step 1b: index among the item's pending follow-ups (0 = the next pending nag). `Int.max` for
    /// day-tail picks and every other kind. Step 6 tier 1 uses it instead of the absolute k (see `tier(of:)`).
    var pendingRank: Int = Int.max
    /// `.nag` carried over at the date it is already pending at (`PlanInput.pendingNagDates`): fixed in step 5.
    var isCarried: Bool = false

    init(id: String, kind: PlannedNotification.Kind, itemSlot: Int?, itemID: UUID?, attempt: Int, fireDate: Date,
         rule: PlannedNotification.Rule, priority: Priority, leadMinutes: Int, threadID: String, categoryID: String) {
        self.id = id
        self.kind = kind
        self.itemSlot = itemSlot
        self.itemID = itemID
        self.attempt = attempt
        self.fireDate = fireDate
        self.rule = rule
        self.priority = priority
        self.leadMinutes = leadMinutes
        self.threadID = threadID
        self.categoryID = categoryID
    }

    var isOnce: Bool {
        if case .once = rule {
            return true
        }
        return false
    }

    var isCritical: Bool { priority == .critical }

    func makePlanned() -> PlannedNotification {
        PlannedNotification(id: id, kind: kind, itemID: itemID, attempt: attempt, fireDate: fireDate, rule: rule,
                            title: title, subtitle: subtitle, body: body, threadID: threadID, categoryID: categoryID,
                            badge: badge, interruption: interruption, relevance: relevance, playsSound: playsSound,
                            tier: tier, soundName: soundName)
    }
}

/// Step 1f input: an item that qualifies for a daily long-tail.
struct NagLongTailRequest {
    var itemSlot: Int
    var itemID: UUID
    var priority: Priority
    var anchor: Date
    /// `F`: first instant > now at `minuteOfDay`.
    var firstFire: Date
    var minuteOfDay: Int
    var threadID: String
    var categoryID: String
}

/// Kept one-shot fire dates and repeating rules of one item (step 7 "next" computation).
struct NagSlotTimeline {
    var oneShots: [Date] = []
    var repeating: [PlannedNotification.Rule] = []

    init() {}

    init(candidates: [NagPlanCandidate]) {
        for candidate in candidates {
            if candidate.isOnce {
                oneShots.append(candidate.fireDate)
            } else {
                repeating.append(candidate.rule)
            }
        }
        oneShots.sort()
    }

    /// Earliest kept fire of this item strictly after `date` (one-shots and the next fire of every repeating rule).
    func nextFire(after date: Date, rules: NagTimeRules) -> Date? {
        var best: Date? = nil
        for oneShot in oneShots where oneShot > date {
            best = oneShot
            break
        }
        for rule in repeating {
            guard let fire = rules.nextFire(of: rule, after: date) else { continue }
            if let current = best {
                if fire < current { best = fire }
            } else {
                best = fire
            }
        }
        return best
    }
}

/// Step 6 result.
struct NagBudgetOutcome {
    /// Kept item notifications, sorted (tier, fireDate, id).
    var kept: [NagPlanCandidate]
    /// Dropped candidates of tiers 0…3 (the ones that count), sorted (fireDate, tier, id).
    var countedDrops: [NagPlanCandidate]
}

// MARK: - Post pass

enum PlanPostPass {
    static let maxLongTails = 5
    static let longTailStaggerMinutes = 2
    static let longTailDedupeMinutes = 15
    static let signingClampSeconds: TimeInterval = 5 * 60
    static let spacingSeconds = 3 * 60
    static let windowSeconds = 60 * 60
    static let maxSoundedPerWindow = 8
    static let maxShiftMinutes = 15
    /// Tier 1 holds the first this-many pending follow-ups of each item (≤ 48 h).
    static let tierOneFollowUps = 4
    static let shortHorizon: TimeInterval = 48 * 3600
    static let mediumHorizon: TimeInterval = 14 * 86_400
    static let farHorizon: TimeInterval = 400 * 86_400
    static let briefingCount = 5
    static let reservedLookaheadDays = 14
    static let minimumLead: TimeInterval = 60

    // MARK: Step 1f — long-tails

    /// Keeps at most 5 long-tails by (priority desc, anchor asc, id asc); rank r fires daily at m + 2·r minutes.
    /// Each kept long-tail removes its item's `.nag` candidates on days ≥ day(F) within ±15 minutes of its minute.
    static func applyLongTails(_ requests: [NagLongTailRequest], to candidates: inout [NagPlanCandidate], rules: NagTimeRules) {
        let ranked = requests.sorted(by: longTailOrder)
        var rank = 0
        for request in ranked {
            if rank >= maxLongTails { break }
            let staggerMinutes = longTailStaggerMinutes * rank
            let clock = ClockTime(minutesOfDay: request.minuteOfDay + staggerMinutes)
            let fire = request.firstFire.addingTimeInterval(TimeInterval(staggerMinutes * 60))
            var longTail = NagPlanCandidate(id: NotificationID.longTail(request.itemID), kind: .longTail,
                                         itemSlot: request.itemSlot, itemID: request.itemID, attempt: 0,
                                         fireDate: fire, rule: .daily(hour: clock.hour, minute: clock.minute),
                                         priority: request.priority, leadMinutes: 0,
                                         threadID: request.threadID, categoryID: request.categoryID)
            longTail.tier = 0
            candidates.append(longTail)

            let slot = request.itemSlot
            let firstDay = rules.startOfDay(request.firstFire)
            let targetMinute = clock.minutesOfDay
            let window = longTailDedupeMinutes
            candidates.removeAll(where: { (other: NagPlanCandidate) -> Bool in
                guard other.itemSlot == slot, other.kind == .nag else { return false }
                guard rules.startOfDay(other.fireDate) >= firstDay else { return false }
                return PlanPostPass.circularDistance(rules.minuteOfDay(other.fireDate), targetMinute) <= window
            })
            rank += 1
        }
    }

    static func longTailOrder(_ lhs: NagLongTailRequest, _ rhs: NagLongTailRequest) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.anchor != rhs.anchor { return lhs.anchor < rhs.anchor }
        return lhs.itemID.uuidString < rhs.itemID.uuidString
    }

    /// Distance between two minutes of day on the 24-hour circle.
    static func circularDistance(_ lhs: Int, _ rhs: Int) -> Int {
        let difference = abs(lhs - rhs) % 1440
        return min(difference, 1440 - difference)
    }

    // MARK: Step 2 — signing clamp

    /// 05b A1: one-shot nags after `expiry − 5 min` are dropped; k0s, pre-alerts, occurrences, carriers and
    /// long-tails stay (they are the only safety net after a re-sign that is never followed by an app launch).
    static func applySigningClamp(_ candidates: inout [NagPlanCandidate], signingExpiry: Date?) {
        guard let expiry = signingExpiry else { return }
        let limit = expiry.addingTimeInterval(-signingClampSeconds)
        candidates.removeAll(where: { (candidate: NagPlanCandidate) -> Bool in
            candidate.kind == .nag && candidate.fireDate > limit
        })
    }

    // MARK: Step 3 helper — delivery rules shared by items and reserved notifications

    /// D32 mute (one-shots inside the window become silent/passive except critical first alerts and signing) and
    /// 05b B7 (`.timeSensitive` → `.active` when the setting is not enabled).
    static func applyDeliveryRules(_ candidate: inout NagPlanCandidate, input: PlanInput, rules: NagTimeRules) {
        let exempt = candidate.kind == .signing || (candidate.kind == .first && candidate.priority == .critical)
        if candidate.isOnce && !exempt && rules.isMuted(candidate.fireDate) {
            candidate.playsSound = false
            candidate.interruption = .passive
        }
        if !input.allowTimeSensitive && candidate.interruption == .timeSensitive {
            candidate.interruption = .active
        }
        if !candidate.playsSound {
            candidate.soundName = nil
        }
    }

    // MARK: Step 4 (+ step 8 content) — reserved notifications

    /// Briefings (next 5 eligible dates), next end-of-day, weekly backup and signing notifications. Briefing/EOD
    /// content is projected at the fire date; a nil text means "do not send" (the date is not replaced).
    static func reservedCandidates(input: PlanInput, rules: NagTimeRules) -> [NagPlanCandidate] {
        var result: [NagPlanCandidate] = []
        let settings = input.settings
        let calendar = input.calendar
        let earliest = input.now.addingTimeInterval(minimumLead)
        let latest = input.now.addingTimeInterval(mediumHorizon)
        let today = rules.startOfDay(input.now)

        if settings.briefingEnabled {
            var dates = 0
            var offset = 0
            while dates < briefingCount && offset <= reservedLookaheadDays {
                let day = AsistCalendar.addingDays(offset, to: today, calendar: calendar)
                offset += 1
                if settings.briefingWorkdaysOnly && !rules.isWorkday(day) { continue }
                let fire = AsistCalendar.date(on: day, at: settings.briefingTime, calendar: calendar)
                if fire <= earliest { continue }
                if fire > latest { break }
                dates += 1
                guard let text = AgendaBuilder.briefing(items: input.items, at: fire, settings: settings,
                                                        calendar: calendar) else { continue }
                let id = NotificationID.briefing(dayKey: AsistCalendar.dayKey(fire, calendar: calendar))
                var briefing = NagPlanCandidate(id: id, kind: .briefing, itemSlot: nil, itemID: nil, attempt: 0,
                                             fireDate: fire, rule: .once, priority: .normal, leadMinutes: 0,
                                             threadID: NotificationID.digestThread,
                                             categoryID: NotificationCategoryID.briefing)
                briefing.title = text.title
                briefing.subtitle = text.subtitle
                briefing.body = text.body
                briefing.interruption = .active
                briefing.relevance = 0.6
                result.append(briefing)
            }
        }

        if settings.endOfDayEnabled {
            var offset = 0
            while offset <= reservedLookaheadDays {
                let day = AsistCalendar.addingDays(offset, to: today, calendar: calendar)
                offset += 1
                if settings.endOfDayWorkdaysOnly && !rules.isWorkday(day) { continue }
                let fire = AsistCalendar.date(on: day, at: settings.endOfDayTime, calendar: calendar)
                if fire <= earliest { continue }
                if fire > latest { break }
                if let text = AgendaBuilder.endOfDay(items: input.items, at: fire, settings: settings, calendar: calendar) {
                    let id = NotificationID.endOfDay(dayKey: AsistCalendar.dayKey(fire, calendar: calendar))
                    var endOfDay = NagPlanCandidate(id: id, kind: .endOfDay, itemSlot: nil, itemID: nil, attempt: 0,
                                                 fireDate: fire, rule: .once, priority: .normal, leadMinutes: 0,
                                                 threadID: NotificationID.digestThread,
                                                 categoryID: NotificationCategoryID.endOfDay)
                    endOfDay.title = text.title
                    endOfDay.subtitle = text.subtitle
                    endOfDay.body = text.body
                    endOfDay.interruption = .active
                    endOfDay.relevance = 0.6
                    result.append(endOfDay)
                }
                break   // only the next end-of-day date is considered
            }
        }

        if settings.backupReminderEnabled {
            let isoWeekday = min(7, max(1, settings.backupReminderWeekday))
            let weekday = AsistCalendar.foundationWeekday(fromISO: isoWeekday)
            let time = settings.backupReminderTime
            let rule = PlannedNotification.Rule.weekly(weekday: weekday, hour: time.hour, minute: time.minute)
            if let fire = rules.nextFire(of: rule, after: input.now) {
                let text = NotificationCopy.backupContent()
                var backup = NagPlanCandidate(id: NotificationID.backup, kind: .backup, itemSlot: nil, itemID: nil,
                                           attempt: 0, fireDate: fire, rule: rule, priority: .normal, leadMinutes: 0,
                                           threadID: NotificationID.systemThread,
                                           categoryID: NotificationCategoryID.system)
                backup.title = text.title
                backup.subtitle = text.subtitle
                backup.body = text.body
                backup.interruption = .passive
                backup.relevance = 0.3
                backup.playsSound = false
                result.append(backup)
            }
        }

        if let expiry = input.signingExpiry {
            var seen = Set<String>()
            let warnings = SigningExpiryPlanner.warningDates(expiration: expiry, now: input.now, calendar: calendar)
            for warning in warnings {
                let fire = AsistCalendar.ceilToMinute(warning)
                let id = NotificationID.signing(minuteKey: AsistCalendar.minuteKey(fire, calendar: calendar))
                if seen.contains(id) { continue }
                seen.insert(id)
                let text = NotificationCopy.signingContent(expiry: expiry, fireDate: fire, calendar: calendar)
                result.append(signingCandidate(id: id, fire: fire, text: text))
            }
            let notice = AsistCalendar.ceilToMinute(expiry.addingTimeInterval(60))
            if notice > earliest {
                let id = NotificationID.signing(minuteKey: AsistCalendar.minuteKey(notice, calendar: calendar))
                if !seen.contains(id) {
                    seen.insert(id)
                    result.append(signingCandidate(id: id, fire: notice, text: NotificationCopy.signingExpiredContent()))
                }
            }
        }
        return result
    }

    private static func signingCandidate(id: String, fire: Date, text: NotificationText) -> NagPlanCandidate {
        var signing = NagPlanCandidate(id: id, kind: .signing, itemSlot: nil, itemID: nil, attempt: 0, fireDate: fire,
                                    rule: .once, priority: .normal, leadMinutes: 0,
                                    threadID: NotificationID.systemThread, categoryID: NotificationCategoryID.system)
        signing.title = text.title
        signing.subtitle = text.subtitle
        signing.body = text.body
        signing.interruption = .timeSensitive
        signing.relevance = 0.9
        return signing
    }

    // MARK: Step 5 — rate limiter (05b C2)

    /// Fixed = every sounded one-shot that is not a `.nag` (item k0s, pre-alerts, occurrences and `reserved`);
    /// movable = sounded one-shot `.nag`s in (priority desc, fireDate asc, id asc). A movable nag is placed at the
    /// earliest t ∈ {fireDate, +1 min … +15 min} with ≥ 3 min to every accepted/fixed sounded notification and
    /// ≤ 8 sounded in every 60-minute window containing t; a shifted t must not be quiet nor pass the signing
    /// clamp. Nags without a valid t are removed; the return value is their count (`rateLimitedCount`).
    /// DEVIATION(04 §6.4 step 5): a carried-over nag (`isCarried`, already pending at its shifted date) is fixed.
    static func applyRateLimiter(_ candidates: inout [NagPlanCandidate], fixed reserved: [NagPlanCandidate],
                                 rules: NagTimeRules, signingExpiry: Date?) -> Int {
        var times: [Int] = []
        for candidate in candidates where candidate.isOnce && candidate.playsSound
            && (candidate.kind != .nag || candidate.isCarried) {
            times.append(seconds(candidate.fireDate))
        }
        for candidate in reserved where candidate.isOnce && candidate.playsSound {
            times.append(seconds(candidate.fireDate))
        }
        times.sort()

        var movable: [Int] = []
        for index in candidates.indices {
            let candidate = candidates[index]
            if candidate.kind == .nag && !candidate.isCarried && candidate.isOnce && candidate.playsSound {
                movable.append(index)
            }
        }
        let snapshot = candidates
        movable.sort(by: { (lhs: Int, rhs: Int) -> Bool in
            PlanPostPass.movableOrder(snapshot[lhs], snapshot[rhs])
        })

        var clampLimit: Date? = nil
        if let expiry = signingExpiry {
            clampLimit = expiry.addingTimeInterval(-signingClampSeconds)
        }
        var dropped = Set<Int>()
        for index in movable {
            let original = candidates[index].fireDate
            let critical = candidates[index].isCritical
            var acceptedDate: Date? = nil
            var step = 0
            while step <= maxShiftMinutes {
                let date = original.addingTimeInterval(TimeInterval(step * 60))
                let shifted = step > 0
                step += 1
                if shifted {
                    if rules.isQuiet(date, critical: critical) { continue }
                    if let limit = clampLimit, date > limit { continue }
                }
                let t = seconds(date)
                if !hasSpacing(t, in: times) { continue }
                if !windowAllows(t, in: times) { continue }
                acceptedDate = date
                break
            }
            if let accepted = acceptedDate {
                let t = seconds(accepted)
                let position = lowerBound(t, in: times)
                times.insert(t, at: position)
                candidates[index].fireDate = accepted
            } else {
                dropped.insert(index)
            }
        }
        if dropped.isEmpty { return 0 }
        var remaining: [NagPlanCandidate] = []
        remaining.reserveCapacity(candidates.count - dropped.count)
        for index in candidates.indices where !dropped.contains(index) {
            remaining.append(candidates[index])
        }
        candidates = remaining
        return dropped.count
    }

    static func movableOrder(_ lhs: NagPlanCandidate, _ rhs: NagPlanCandidate) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
        return lhs.id < rhs.id
    }

    static func seconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    /// First index whose value is >= `value` (`sorted` ascending).
    static func lowerBound(_ value: Int, in sorted: [Int]) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle] < value {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// |t − a| ≥ 3 min for every accepted/fixed a.
    static func hasSpacing(_ t: Int, in times: [Int]) -> Bool {
        let index = lowerBound(t - spacingSeconds + 1, in: times)
        if index < times.count && times[index] < t + spacingSeconds {
            return false
        }
        return true
    }

    /// Every window [s, s + 60 min) containing t holds ≤ 8 sounded including t; s ∈ {t} ∪ {a : t − 60 min < a ≤ t}.
    static func windowAllows(_ t: Int, in times: [Int]) -> Bool {
        var starts: [Int] = [t]
        var index = lowerBound(t - windowSeconds + 1, in: times)
        while index < times.count && times[index] <= t {
            starts.append(times[index])
            index += 1
        }
        for start in starts {
            let inside = lowerBound(start + windowSeconds, in: times) - lowerBound(start, in: times)
            if inside + 1 > maxSoundedPerWindow {
                return false
            }
        }
        return true
    }

    // MARK: Step 6 — tiers and budget

    /// 0 = first/preAlert/occurrence ≤ 48 h and long-tails; 1 = the item's first 4 pending follow-ups ≤ 48 h and
    /// carriers; 2 = first/preAlert/occurrence in (48 h, 14 d]; 3 = other nags ≤ 14 d; 4 = first/preAlert/occurrence
    /// in (14 d, 400 d]; nil = not planned. Reserved notifications carry tier 0.
    /// DEVIATION(04 §6.4 step 6): tier 1 was "`.nag` k 1…4". k counts from the anchor, so an item overdue since
    /// yesterday has only k ≥ 5 pending and all its nags fell to tier 3, below every first alert up to 14 days out —
    /// under budget pressure the forgotten items went silent. Tier 1 now takes the first 4 *pending* follow-ups
    /// (`pendingRank` 0…3; for an item that is not yet overdue these are exactly k 1…4), restoring 01a §5 "Tier 1:
    /// k = 1…4 whose anchor ≤ now + 48 h (includes overdue items)". `attempt` (ids, sounds, copy) is unchanged.
    static func tier(of candidate: NagPlanCandidate, now: Date) -> Int? {
        let delta = candidate.fireDate.timeIntervalSince(now)
        switch candidate.kind {
        case .longTail:
            return 0
        case .carrier:
            return 1
        case .first, .preAlert, .occurrence:
            if delta <= shortHorizon { return 0 }
            if delta <= mediumHorizon { return 2 }
            if delta <= farHorizon { return 4 }
            return nil
        case .nag:
            if delta <= shortHorizon && candidate.pendingRank < tierOneFollowUps { return 1 }
            if delta <= mediumHorizon { return 3 }
            return nil
        case .briefing, .endOfDay, .backup, .signing, .sentinel, .horizon:
            return 0
        }
    }

    /// Output order (tier, fireDate, id).
    static func planOrder(_ lhs: NagPlanCandidate, _ rhs: NagPlanCandidate) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
        if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
        return lhs.id < rhs.id
    }

    /// Chronological order (fireDate, id) — immediate requests and per-item timelines.
    static func timeOrder(_ lhs: NagPlanCandidate, _ rhs: NagPlanCandidate) -> Bool {
        if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
        return lhs.id < rhs.id
    }

    /// Assigns tiers (dropping never-planned candidates), keeps the first `budget` by (tier, fireDate, id).
    static func applyBudget(_ candidates: [NagPlanCandidate], budget: Int, now: Date) -> NagBudgetOutcome {
        let tiered = assignTiers(candidates, now: now).sorted(by: planOrder)
        let limit = max(0, budget)
        if tiered.count <= limit {
            return NagBudgetOutcome(kept: tiered, countedDrops: [])
        }
        let kept = Array(tiered[0..<limit])
        var counted: [NagPlanCandidate] = []
        for candidate in tiered[limit...] where candidate.tier <= 3 {
            counted.append(candidate)
        }
        counted.sort(by: { (lhs: NagPlanCandidate, rhs: NagPlanCandidate) -> Bool in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.id < rhs.id
        })
        return NagBudgetOutcome(kept: kept, countedDrops: counted)
    }

    static func assignTiers(_ candidates: [NagPlanCandidate], now: Date) -> [NagPlanCandidate] {
        var result: [NagPlanCandidate] = []
        result.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard let assigned = PlanPostPass.tier(of: candidate, now: now) else { continue }
            var tiered = candidate
            tiered.tier = assigned
            result.append(tiered)
        }
        return result
    }

    // MARK: Step 8 — sentinels

    /// 05b B5: a copy of the earliest dropped notification (content already computed) with the budget line in
    /// place of body line 2.
    static func budgetSentinel(from source: NagPlanCandidate, extraCount: Int) -> NagPlanCandidate {
        var sentinel = source
        sentinel.id = NotificationID.sentinel
        sentinel.kind = .sentinel
        sentinel.rule = .once
        sentinel.tier = 0
        sentinel.body = sentinelBody(source.body, replacingLastLine: source.bodyHasFollowLine,
                                     line: NotificationCopy.budgetSentinelLine(extraCount: max(0, extraCount)))
        sentinel.bodyHasFollowLine = false
        sentinel.interruption = .active
        sentinel.relevance = 0.7
        sentinel.playsSound = true
        sentinel.badge = nil
        return sentinel
    }

    static func sentinelBody(_ body: String, replacingLastLine: Bool, line: String) -> String {
        var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        if replacingLastLine && !lines.isEmpty {
            lines.removeLast()
        }
        var kept: [String] = []
        for existing in lines where !existing.trimmingCharacters(in: .whitespaces).isEmpty {
            kept.append(existing)
        }
        kept.append(line)
        return kept.joined(separator: "\n")
    }

    /// 05a #23 / 05b B3: "Asist'i bir kez aç" 1 h after the last kept one-shot item notification, at the latest at
    /// the day start of now + 13 days, moved out of quiet hours. nil when no open item has an anchor.
    static func horizonSentinel(input: PlanInput, rules: NagTimeRules, keptItems: [NagPlanCandidate]) -> NagPlanCandidate? {
        var openCount = 0
        for item in input.items where item.isNotifiable && item.anchorDate != nil {
            openCount += 1
        }
        guard openCount > 0 else { return nil }

        var latest: Date? = nil
        for candidate in keptItems where candidate.isOnce && candidate.itemSlot != nil {
            if let current = latest {
                if candidate.fireDate > current { latest = candidate.fireDate }
            } else {
                latest = candidate.fireDate
            }
        }
        let capDay = AsistCalendar.addingDays(13, to: input.now, calendar: input.calendar)
        let cap = rules.dayStart(onDay: capDay, takip: false)
        var fire = cap
        if let last = latest {
            let afterLast = last.addingTimeInterval(3600)
            if afterLast < cap { fire = afterLast }
        }
        if rules.isQuiet(fire, critical: false) {
            fire = rules.quietExit(fire)
        }
        guard fire > input.now.addingTimeInterval(minimumLead) else { return nil }

        let text = NotificationCopy.horizonSentinelContent(openCount: openCount)
        var horizon = NagPlanCandidate(id: NotificationID.horizonSentinel, kind: .horizon, itemSlot: nil, itemID: nil,
                                    attempt: 0, fireDate: fire, rule: .once, priority: .normal, leadMinutes: 0,
                                    threadID: NotificationID.systemThread, categoryID: NotificationCategoryID.system)
        horizon.title = text.title
        horizon.subtitle = text.subtitle
        horizon.body = text.body
        horizon.interruption = .active
        horizon.relevance = 0.7
        horizon.tier = 0
        return horizon
    }

    /// Keeps at most `slots` reserved notifications (only relevant for a custom `reservedSlots`; the default 14
    /// always fits the ≤ 13 produced). Importance: signing, budget sentinel, horizon, end-of-day, briefings, backup.
    static func trimReserved(_ reserved: [NagPlanCandidate], slots: Int) -> [NagPlanCandidate] {
        let limit = max(0, slots)
        if reserved.count <= limit { return reserved }
        let ordered = reserved.sorted(by: { (lhs: NagPlanCandidate, rhs: NagPlanCandidate) -> Bool in
            let lhsRank = PlanPostPass.reservedRank(lhs.kind)
            let rhsRank = PlanPostPass.reservedRank(rhs.kind)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.id < rhs.id
        })
        return Array(ordered.prefix(limit))
    }

    static func reservedRank(_ kind: PlannedNotification.Kind) -> Int {
        switch kind {
        case .signing: return 0
        case .sentinel: return 1
        case .horizon: return 2
        case .endOfDay: return 3
        case .briefing: return 4
        case .backup: return 5
        case .first, .nag, .preAlert, .longTail, .occurrence, .carrier: return 6
        }
    }

    // MARK: Step 9 — badges

    /// Every one-shot gets the projected badge at its fire date; repeating rules leave the badge unchanged (nil).
    static func applyBadges(_ candidates: inout [NagPlanCandidate], items: [Item], settings: AppSettings, calendar: Calendar) {
        for index in candidates.indices {
            if candidates[index].isOnce {
                candidates[index].badge = NagPlanner.badgeCount(items: items, at: candidates[index].fireDate,
                                                                settings: settings, calendar: calendar)
            } else {
                candidates[index].badge = nil
            }
        }
    }

    // MARK: Step 10 — output

    /// Sorted (tier, fireDate, id); duplicate ids (possible only with duplicate item ids) keep the first.
    static func output(_ candidates: [NagPlanCandidate]) -> [PlannedNotification] {
        let ordered = candidates.sorted(by: planOrder)
        var seen = Set<String>()
        var result: [PlannedNotification] = []
        result.reserveCapacity(ordered.count)
        for candidate in ordered where !seen.contains(candidate.id) {
            seen.insert(candidate.id)
            result.append(candidate.makePlanned())
        }
        return result
    }
}
