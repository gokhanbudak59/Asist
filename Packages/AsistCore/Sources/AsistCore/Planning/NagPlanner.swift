// API: Packages/AsistCore/Sources/AsistCore/Planning/NagPlanner.swift
// WP3 (04 §3.5.3; algorithm 04 §6.4, normative). Chain generation and time rules: NagChain.swift;
// signing clamp, rate limiter, tiers/budget, reserved notifications and sentinels: PlanPostPass.swift.
// Pure: depends only on the input (injected calendar and `now`), never on Date()/TimeZone.current.
import Foundation

public enum NagPlanner {
    /// Pure. Same input → same output (ids, order, fingerprints). Algorithm §6.4.
    public static func plan(_ input: PlanInput) -> PlanResult {
        let rules = NagTimeRules(settings: input.settings, calendar: input.calendar, now: input.now)
        let items = input.items
        let names = projectNames(input.projects)

        // Step 1: per-item candidates (a–e) and long-tail requests (f).
        var candidates: [NagPlanCandidate] = []
        var longTailRequests: [NagLongTailRequest] = []
        for slot in items.indices {
            let draft = itemDraft(item: items[slot], slot: slot, input: input, rules: rules)
            candidates.append(contentsOf: draft.candidates)
            if let request = draft.longTail {
                longTailRequests.append(request)
            }
        }
        PlanPostPass.applyLongTails(longTailRequests, to: &candidates, rules: rules)

        // Step 2: signing clamp.
        PlanPostPass.applySigningClamp(&candidates, signingExpiry: input.signingExpiry)

        // Step 3: attributes (priority, overdue relevance, sounds, mute, time-sensitive fallback).
        for index in candidates.indices {
            guard let slot = candidates[index].itemSlot, slot < items.count else { continue }
            applyItemAttributes(&candidates[index], item: items[slot], input: input, rules: rules)
        }

        // Step 4 (+ step 8 content of briefings/EOD/backup/signing): reserved notifications.
        var reserved = PlanPostPass.reservedCandidates(input: input, rules: rules)
        for index in reserved.indices {
            PlanPostPass.applyDeliveryRules(&reserved[index], input: input, rules: rules)
        }

        // Candidates step 6 would never plan (nags beyond 14 days, first alerts beyond 400 days) must not occupy
        // rate-limiter slots of plannable ones.
        let now = input.now
        candidates = candidates.filter { (candidate: NagPlanCandidate) -> Bool in
            PlanPostPass.tier(of: candidate, now: now) != nil
        }

        // Step 5: rate limiter.
        let rateLimited = PlanPostPass.applyRateLimiter(&candidates, fixed: reserved, rules: rules,
                                                        signingExpiry: input.signingExpiry)

        // Step 6: tiers and budget.
        let budget = PlanPostPass.applyBudget(candidates, budget: input.itemBudget, now: input.now)
        var kept = budget.kept

        // Step 7: item content (after budget, so "next" refers to what is really pending).
        var timelines = [NagSlotTimeline](repeating: NagSlotTimeline(), count: items.count)
        for candidate in kept {
            guard let slot = candidate.itemSlot, slot < items.count else { continue }
            if candidate.isOnce {
                timelines[slot].oneShots.append(candidate.fireDate)
            } else {
                timelines[slot].repeating.append(candidate.rule)
            }
        }
        for slot in timelines.indices {
            timelines[slot].oneShots.sort()
        }
        for index in kept.indices {
            guard let slot = kept[index].itemSlot, slot < items.count else { continue }
            let item = items[slot]
            applyContent(&kept[index], item: item, projectName: projectName(of: item, names: names),
                         timeline: timelines[slot], rules: rules)
        }

        // Step 8: budget sentinel and horizon sentinel.
        var extras: [NagPlanCandidate] = []
        if let earliest = budget.countedDrops.first,
           earliest.fireDate > input.now.addingTimeInterval(PlanPostPass.minimumLead),
           let slot = earliest.itemSlot, slot < items.count {
            var source = earliest
            let item = items[slot]
            applyContent(&source, item: item, projectName: projectName(of: item, names: names),
                         timeline: timelines[slot], rules: rules)
            extras.append(PlanPostPass.budgetSentinel(from: source, extraCount: budget.countedDrops.count - 1))
        }
        if let horizon = PlanPostPass.horizonSentinel(input: input, rules: rules, keptItems: kept) {
            extras.append(horizon)
        }
        for index in extras.indices {
            PlanPostPass.applyDeliveryRules(&extras[index], input: input, rules: rules)
        }
        let reservedFinal = PlanPostPass.trimReserved(reserved + extras, slots: input.reservedSlots)

        // Step 9: badges.
        var all = kept + reservedFinal
        PlanPostPass.applyBadges(&all, items: items, settings: input.settings, calendar: input.calendar)

        // Step 10: output sorted (tier, fireDate, id); fingerprints computed by PlannedNotification.init.
        let notifications = PlanPostPass.output(all)
        let badgeNow = badgeCount(items: items, at: input.now, settings: input.settings, calendar: input.calendar)
        return PlanResult(notifications: notifications,
                          droppedCount: budget.countedDrops.count,
                          earliestDroppedDate: budget.countedDrops.first?.fireDate,
                          rateLimitedCount: rateLimited,
                          badgeNow: badgeNow,
                          itemBudget: input.itemBudget)
    }

    /// 05b B1: the first `limit` one-shot (`.once`) notifications of `item`, computed exactly as `plan` would for an
    /// input that contains only this item (same ids, content and fingerprints; no reserved slots, no sentinels,
    /// no rate limiter, no budget). Used by ReminderEngine.handle before completionHandler().
    public static func immediateRequests(for item: Item, input: PlanInput, limit: Int) -> [PlannedNotification] {
        guard limit > 0 else { return [] }
        let rules = NagTimeRules(settings: input.settings, calendar: input.calendar, now: input.now)
        let draft = itemDraft(item: item, slot: 0, input: input, rules: rules)
        var candidates = draft.candidates
        if let request = draft.longTail {
            PlanPostPass.applyLongTails([request], to: &candidates, rules: rules)
        }
        PlanPostPass.applySigningClamp(&candidates, signingExpiry: input.signingExpiry)
        for index in candidates.indices {
            applyItemAttributes(&candidates[index], item: item, input: input, rules: rules)
        }
        let tiered = PlanPostPass.assignTiers(candidates, now: input.now)
        let timeline = NagSlotTimeline(candidates: tiered)
        let name = projectName(of: item, names: projectNames(input.projects))

        // Badges are projected over the caller's full item list (with this item's current state), so the requests
        // added before completionHandler() already carry the right badge. For a single-item input this is exactly
        // what plan() computes.
        var badgeItems: [Item] = []
        var replaced = false
        for existing in input.items {
            if existing.id == item.id {
                if !replaced {
                    badgeItems.append(item)
                    replaced = true
                }
            } else {
                badgeItems.append(existing)
            }
        }
        if !replaced {
            badgeItems.append(item)
        }

        let oneShots = tiered.filter { $0.isOnce }.sorted(by: PlanPostPass.timeOrder)
        var result: [PlannedNotification] = []
        for candidate in oneShots.prefix(limit) {
            var planned = candidate
            applyContent(&planned, item: item, projectName: name, timeline: timeline, rules: rules)
            planned.badge = badgeCount(items: badgeItems, at: planned.fireDate, settings: input.settings,
                                     calendar: input.calendar)
            result.append(planned.makePlanned())
        }
        return result
    }

    /// Full chain for an anchor (index = k; element 0 == anchor; `.etkinlik` → [anchor]). Honours quiet hours,
    /// work hours, daily caps and the mute window (`settings.muteUntil`, active only while `now < muteUntil`).
    /// Used by plan(), tests and the Settings preview.
    public static func chain(anchor: Date, profile: NagProfile, profileKind: NagProfileKind, isCritical: Bool,
                             settings: AppSettings, now: Date, calendar: Calendar) -> [Date] {
        let rules = NagTimeRules(settings: settings, calendar: calendar, now: now)
        var generator = NagChainGenerator(anchor: anchor, profile: profile, kind: profileKind,
                                          isCritical: isCritical, rules: rules)
        var result: [Date] = []
        while let next = generator.next() {
            result.append(next)
        }
        return result
    }

    /// "Yarın sabah": before 05:00 → today's day start; else next day's day start
    /// (workStart on workdays, offDayStart otherwise).
    public static func tomorrowMorning(after now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let rules = NagTimeRules(settings: settings, calendar: calendar, now: now)
        if calendar.component(.hour, from: now) < 5 {
            let today = rules.dayStart(onDay: now, takip: false)
            // DEVIATION(04 §3.5.3): a snooze target must lie in the future; a day start before 05:00 that has
            // already passed (e.g. workStart 04:00 at 04:30) falls through to the next day's start.
            if today > now { return today }
        }
        let tomorrow = AsistCalendar.addingDays(1, to: rules.startOfDay(now), calendar: calendar)
        return rules.dayStart(onDay: tomorrow, takip: false)
    }

    /// Takip re-ask: `workdays` workdays after `now` at settings.followUpAskTime.
    public static func followUpAsk(after now: Date, workdays: Int, settings: AppSettings, calendar: Calendar) -> Date {
        let count = min(30, max(1, workdays))
        let day = AsistCalendar.addingWorkdays(count, to: now, workdays: settings.workdays, calendar: calendar)
        return AsistCalendar.date(on: day, at: settings.followUpAskTime, calendar: calendar)
    }

    /// "Bu akşam" = today at settings.aksam; nil if now is past 18:30.
    public static func thisEvening(now: Date, settings: AppSettings, calendar: Calendar) -> Date? {
        if AsistCalendar.minuteOfDay(now, calendar: calendar) > 18 * 60 + 30 { return nil }
        let evening = AsistCalendar.date(on: now, at: settings.aksam, calendar: calendar)
        // DEVIATION(04 §3.5.3): also nil when a user-set "akşam" time has already passed (never a past target).
        return evening > now ? evening : nil
    }

    /// "Pazartesi" = next Monday (strictly after today) at day start.
    public static func nextMonday(now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let rules = NagTimeRules(settings: settings, calendar: calendar, now: now)
        var day = AsistCalendar.addingDays(1, to: rules.startOfDay(now), calendar: calendar)
        var guardCounter = 0
        while AsistCalendar.isoWeekday(day, calendar: calendar) != 1 && guardCounter < 8 {
            day = AsistCalendar.addingDays(1, to: day, calendar: calendar)
            guardCounter += 1
        }
        return rules.dayStart(onDay: day, takip: false)
    }

    /// Mute preset "Mesai sonuna kadar" (D32): today's workEnd when now is before it on a workday, else now + 2 h
    /// (ceil to minute).
    public static func muteUntilWorkEnd(now: Date, settings: AppSettings, calendar: Calendar) -> Date {
        let iso = AsistCalendar.isoWeekday(now, calendar: calendar)
        let end = AsistCalendar.date(on: now, at: settings.workEnd, calendar: calendar)
        if settings.isWorkday(isoWeekday: iso) && now < end { return end }
        return AsistCalendar.ceilToMinute(now.addingTimeInterval(2 * 3600))
    }

    /// Open, non-note, non-event items overdue at `date` (+ due today when mode == .overdueAndToday; 0 when .off).
    public static func badgeCount(items: [Item], at date: Date, settings: AppSettings, calendar: Calendar) -> Int {
        if settings.badgeMode == .off { return 0 }
        var count = 0
        for item in items where item.isNotifiable && !item.isEvent {
            if item.isOverdue(at: date, calendar: calendar) {
                count += 1
            } else if settings.badgeMode == .overdueAndToday && item.isDueToday(at: date, calendar: calendar) {
                count += 1
            }
        }
        return count
    }
}

// MARK: - Step 1: per-item candidates (internal)

/// Output of step 1 for one item.
struct NagItemDraft {
    var candidates: [NagPlanCandidate] = []
    var longTail: NagLongTailRequest? = nil
}

/// A chain element picked for planning (k = index in the full chain). `carried`: `date` is the pending trigger
/// date of an element the rate limiter had shifted (PlanInput.pendingNagDates), not the chain date.
struct NagChainPick {
    var k: Int
    var date: Date
    var carried: Bool = false
}

/// Result of scanning one chain: (a) first alert, (b) follow-ups, (c) day-tail.
struct NagChainScan {
    var first: Date? = nil
    var followUps: [NagChainPick] = []
    var dayTail: [NagChainPick] = []
}

/// A repeating carrier rule of a recurring item (D27).
struct NagCarrierRule {
    var suffix: String
    var rule: PlannedNotification.Rule
}

/// A carrier rule with its next fire after `now`.
struct NagCarrierFire {
    var carrier: NagCarrierRule
    var fire: Date
}

extension NagPlanner {
    /// k0 is planned only when it lies more than 10 s ahead (a request at "now" would be lost).
    static let firstAlertMargin: TimeInterval = 10
    /// Pre-alerts need at least one minute of lead.
    static let preAlertMargin: TimeInterval = 60
    /// Day-tail: first element of each of the next 3 distinct calendar days (05a #2).
    static let dayTailDays = 3
    /// One-shot future occurrences of a recurring item without a carrier (D27).
    static let occurrenceCount = 7
    /// Longest pre-alert lead accepted (366 days; matches the `Item` decode clamp).
    static let maxLeadMinutes = 527_040
    static let importantSound = "asist-onemli.wav"
    static let criticalSound = "asist-kritik.wav"

    /// 04 §6.4 step 1 for one item. Items that cannot notify produce an empty draft.
    static func itemDraft(item: Item, slot: Int, input: PlanInput, rules: NagTimeRules) -> NagItemDraft {
        var draft = NagItemDraft()
        guard item.isNotifiable, let rawAnchor = item.anchorDate else { return draft }
        // 07 §9.3: a place-only item has anchorDate == locationFiredAt (nil until its geofence notification was
        // delivered → nothing planned; LocationService owns the asist.loc.* request) or its snooze.

        let settings = input.settings
        let calendar = input.calendar
        let now = input.now
        let anchor = AsistCalendar.ceilToMinute(rawAnchor)
        let profileKind = item.profileKind(settings: settings)
        let profile = settings.nagProfiles[profileKind]
        let critical = item.priority == .critical
        let cutoff = now.addingTimeInterval(firstAlertMargin)
        let thread = NotificationID.thread(item.id)
        let category = item.kind == .waiting ? NotificationCategoryID.followUp : NotificationCategoryID.item

        // D27: the current occurrence's chain ends where the next occurrence begins.
        var nextOccurrence: Date? = nil
        var dueClock: ClockTime? = nil
        if let rule = item.recurrence, let due = item.dueDate {
            let clock = clockTime(of: due, calendar: calendar)
            dueClock = clock
            nextOccurrence = RecurrenceEngine.nextOccurrence(of: rule, time: clock, after: due, anchor: due,
                                                            calendar: calendar)
        }

        // (a) first alert, (b) follow-ups, (c) day-tail.
        let itemID = item.id
        let pendingNags = input.pendingNagDates
        let scan = scanChain(anchor: anchor, profile: profile, profileKind: profileKind, critical: critical,
                             rules: rules, cutoff: cutoff, stopAt: nextOccurrence,
                             pendingDate: { (k: Int) -> Date? in pendingNags[NotificationID.chain(itemID, k)] })
        if let first = scan.first {
            draft.candidates.append(NagPlanCandidate(id: NotificationID.chain(item.id, 0), kind: .first, itemSlot: slot,
                                                  itemID: item.id, attempt: 0, fireDate: first, rule: .once,
                                                  priority: item.priority, leadMinutes: 0, threadID: thread,
                                                  categoryID: category))
        }
        let followUpCount = scan.followUps.count
        for (index, pick) in (scan.followUps + scan.dayTail).enumerated() {
            var nag = NagPlanCandidate(id: NotificationID.chain(item.id, pick.k), kind: .nag, itemSlot: slot,
                                       itemID: item.id, attempt: pick.k, fireDate: pick.date, rule: .once,
                                       priority: item.priority, leadMinutes: 0, threadID: thread,
                                       categoryID: category)
            if index < followUpCount {
                nag.pendingRank = index                         // step 6 tier 1: first 4 pending follow-ups
            }
            nag.isCarried = pick.carried
            draft.candidates.append(nag)
        }

        // (d) pre-alerts (category ASIST_PRE: "✓ Yaptım" only, never re-anchors the item).
        if let due = item.dueDate {
            let earliest = now.addingTimeInterval(preAlertMargin)
            var seenLeads = Set<Int>()
            for lead in item.leadTimesMinutes where lead > 0 && lead <= maxLeadMinutes && !seenLeads.contains(lead) {
                seenLeads.insert(lead)
                let fire = AsistCalendar.ceilToMinute(due.addingTimeInterval(TimeInterval(-lead * 60)))
                if fire <= earliest { continue }
                draft.candidates.append(NagPlanCandidate(id: NotificationID.preAlert(item.id, minutes: lead),
                                                      kind: .preAlert, itemSlot: slot, itemID: item.id, attempt: 0,
                                                      fireDate: fire, rule: .once, priority: item.priority,
                                                      leadMinutes: lead, threadID: thread,
                                                      categoryID: NotificationCategoryID.preAlert))
            }
        }

        // (e) recurrence: repeating carriers or one-shot future occurrences (D27).
        if let rule = item.recurrence, let due = item.dueDate, let clock = dueClock {
            appendRecurrence(rule: rule, due: due, clock: clock, nextOccurrence: nextOccurrence, item: item,
                             slot: slot, input: input, rules: rules, thread: thread, category: category,
                             draft: &draft)
        }

        // (f) long-tail request (ranked across items in PlanPostPass.applyLongTails).
        if item.recurrence == nil && profileKind != .etkinlik && item.priority >= .high {
            let time = profileKind == .takip ? settings.followUpAskTime : settings.workStart
            let daily = PlannedNotification.Rule.daily(hour: time.hour, minute: time.minute)
            if let firstFire = rules.nextFire(of: daily, after: now), firstFire > anchor {
                draft.longTail = NagLongTailRequest(itemSlot: slot, itemID: item.id, priority: item.priority,
                                                 anchor: anchor, firstFire: firstFire,
                                                 minuteOfDay: time.minutesOfDay, threadID: thread,
                                                 categoryID: category)
            }
        }
        return draft
    }

    /// Walks the chain lazily and stops once the day-tail is complete (the walked part is a prefix of the full chain).
    /// `pendingDate(k)`: the pending trigger date of chain element k (PlanInput.pendingNagDates), nil if unknown.
    static func scanChain(anchor: Date, profile: NagProfile, profileKind: NagProfileKind, critical: Bool,
                          rules: NagTimeRules, cutoff: Date, stopAt: Date?,
                          pendingDate: (Int) -> Date?) -> NagChainScan {
        var scan = NagChainScan()
        var generator = NagChainGenerator(anchor: anchor, profile: profile, kind: profileKind,
                                          isCritical: critical, rules: rules)
        let maxFollowUps = max(0, profile.maxPendingFollowUps)
        let carryWindow = TimeInterval(PlanPostPass.maxShiftMinutes * 60)
        let carryFloor = cutoff.addingTimeInterval(-carryWindow)
        var k = -1
        var inTail = false
        var tailReferenceDay: Date? = nil
        var lastTailDay: Date? = nil
        while let date = generator.next() {
            k += 1
            if let stop = stopAt, date >= stop { break }        // recurring: drop elements ≥ N1
            if k == 0 {
                if date > cutoff { scan.first = date }
                continue
            }
            if date <= cutoff {
                // DEVIATION(04 §6.4 step 1b): an element the rate limiter moved past the cutoff (≤ 15 min later)
                // is still pending at its shifted date; keep it there (fixed in step 5) instead of letting a
                // reconcile between the two dates remove it.
                if !inTail && scan.followUps.count < maxFollowUps && date > carryFloor,
                   let pending = pendingDate(k), pending > cutoff, pending <= date.addingTimeInterval(carryWindow) {
                    scan.followUps.append(NagChainPick(k: k, date: pending, carried: true))
                }
                continue
            }
            if !inTail {
                if scan.followUps.count < maxFollowUps {
                    scan.followUps.append(NagChainPick(k: k, date: date))
                    continue
                }
                inTail = true
                // Day-tail only when (a) or (b) kept something; D = day of the last kept element.
                guard profileKind != .etkinlik, let lastKept = scan.followUps.last?.date ?? scan.first else { break }
                tailReferenceDay = rules.startOfDay(lastKept)
            }
            guard let reference = tailReferenceDay else { break }
            let day = rules.startOfDay(date)
            if day <= reference { continue }
            if let previous = lastTailDay, day <= previous { continue }
            scan.dayTail.append(NagChainPick(k: k, date: date))
            lastTailDay = day
            if scan.dayTail.count >= dayTailDays { break }
        }
        return scan
    }

    /// Step 1e: carriers when the earliest carrier fire equals the next occurrence (or delivers the un-snoozed
    /// current due date, which then replaces k0); otherwise one-shot occurrences ≤ 14 days + the first beyond.
    static func appendRecurrence(rule: Recurrence, due: Date, clock: ClockTime, nextOccurrence: Date?, item: Item,
                                 slot: Int, input: PlanInput, rules: NagTimeRules, thread: String, category: String,
                                 draft: inout NagItemDraft) {
        let now = input.now
        var carriers: [NagCarrierFire] = []
        for carrier in carrierRules(for: rule, clock: clock) {
            if let fire = rules.nextFire(of: carrier.rule, after: now) {
                carriers.append(NagCarrierFire(carrier: carrier, fire: fire))
            }
        }
        var earliestCarrier: Date? = nil
        for entry in carriers {
            if let current = earliestCarrier {
                if entry.fire < current { earliestCarrier = entry.fire }
            } else {
                earliestCarrier = entry.fire
            }
        }

        if let carrierFire = earliestCarrier {
            var matchesNext = false
            if let next = nextOccurrence {
                matchesNext = next == carrierFire
            }
            let deliversDue = item.snoozedUntil == nil && carrierFire == due
            if matchesNext || deliversDue {
                for entry in carriers {
                    let id = NotificationID.carrier(item.id, suffix: entry.carrier.suffix)
                    draft.candidates.append(NagPlanCandidate(id: id, kind: .carrier, itemSlot: slot, itemID: item.id,
                                                          attempt: 0, fireDate: entry.fire, rule: entry.carrier.rule,
                                                          priority: item.priority, leadMinutes: 0, threadID: thread,
                                                          categoryID: category))
                }
                if carrierFire == due {
                    // The carrier delivers the current occurrence itself.
                    draft.candidates.removeAll(where: { (candidate: NagPlanCandidate) -> Bool in
                        candidate.kind == .first
                    })
                }
                return
            }
        }

        let occurrences = RecurrenceEngine.occurrences(of: rule, time: clock, after: due, anchor: due,
                                                       count: occurrenceCount, calendar: input.calendar)
        let cutoff = now.addingTimeInterval(firstAlertMargin)
        let horizon = now.addingTimeInterval(PlanPostPass.mediumHorizon)
        var seen = Set<String>()
        for occurrence in occurrences {
            let fire = AsistCalendar.ceilToMinute(occurrence)
            if fire <= cutoff { continue }
            let key = AsistCalendar.minuteKey(fire, calendar: input.calendar)
            let id = NotificationID.occurrence(item.id, minuteKey: key)
            if seen.contains(id) { continue }
            seen.insert(id)
            draft.candidates.append(NagPlanCandidate(id: id, kind: .occurrence, itemSlot: slot, itemID: item.id,
                                                  attempt: 0, fireDate: fire, rule: .once, priority: item.priority,
                                                  leadMinutes: 0, threadID: thread, categoryID: category))
            if fire > horizon { break }                         // the first one beyond 14 days (tier 4) ends the list
        }
    }

    /// Carrier rules for interval 1: daily → d; weekly → w<Foundation weekday> per weekday; monthly day 1…28 → m.
    static func carrierRules(for rule: Recurrence, clock: ClockTime) -> [NagCarrierRule] {
        guard rule.interval == 1 else { return [] }
        switch rule.frequency {
        case .daily:
            return [NagCarrierRule(suffix: "d", rule: .daily(hour: clock.hour, minute: clock.minute))]
        case .weekly:
            guard let weekdays = rule.weekdays, !weekdays.isEmpty else { return [] }
            var result: [NagCarrierRule] = []
            var seen = Set<Int>()
            for iso in weekdays.sorted() where iso >= 1 && iso <= 7 && !seen.contains(iso) {
                seen.insert(iso)
                let weekday = AsistCalendar.foundationWeekday(fromISO: iso)
                let weekly = PlannedNotification.Rule.weekly(weekday: weekday, hour: clock.hour, minute: clock.minute)
                result.append(NagCarrierRule(suffix: "w" + String(weekday), rule: weekly))
            }
            return result
        case .monthly:
            guard let day = rule.monthDay, day >= 1 && day <= 28 else { return [] }
            return [NagCarrierRule(suffix: "m", rule: .monthly(day: day, hour: clock.hour, minute: clock.minute))]
        case .yearly:
            return []
        }
    }

    static func clockTime(of date: Date, calendar: Calendar) -> ClockTime {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return ClockTime(parts.hour ?? 0, parts.minute ?? 0)
    }

    static func projectNames(_ projects: [Project]) -> [UUID: String] {
        var table: [UUID: String] = [:]
        for project in projects where table[project.id] == nil {
            table[project.id] = project.name
        }
        return table
    }

    static func projectName(of item: Item, names: [UUID: String]) -> String? {
        guard let id = item.projectID else { return nil }
        return names[id]
    }

    // MARK: Step 3 — attributes

    /// 03 §3.2 levels, overdue relevance, D37 sounds, then mute / time-sensitive rules.
    static func applyItemAttributes(_ candidate: inout NagPlanCandidate, item: Item, input: PlanInput,
                                    rules: NagTimeRules) {
        switch item.priority {
        case .low, .normal:
            candidate.interruption = .active
            candidate.relevance = 0.5
        case .high:
            candidate.interruption = .timeSensitive
            candidate.relevance = 0.8
        case .critical:
            candidate.interruption = .timeSensitive
            candidate.relevance = 1.0
        }
        if candidate.kind == .nag && item.isOverdue(at: candidate.fireDate, calendar: input.calendar) {
            candidate.relevance = 1.0
        }
        candidate.playsSound = true
        candidate.soundName = soundName(kind: candidate.kind, priority: item.priority, attempt: candidate.attempt)
        PlanPostPass.applyDeliveryRules(&candidate, input: input, rules: rules)
    }

    /// D37: high → "asist-onemli.wav", critical → "asist-kritik.wav" for first/occurrence/carrier/long-tail and
    /// every nag with k % 3 == 0; everything else the system default (nil).
    static func soundName(kind: PlannedNotification.Kind, priority: Priority, attempt: Int) -> String? {
        let name: String
        switch priority {
        case .low, .normal:
            return nil
        case .high:
            name = importantSound
        case .critical:
            name = criticalSound
        }
        switch kind {
        case .first, .occurrence, .carrier, .longTail:
            return name
        case .nag:
            return attempt % 3 == 0 ? name : nil
        case .preAlert, .briefing, .endOfDay, .backup, .signing, .sentinel, .horizon:
            return nil
        }
    }

    // MARK: Step 7 — content

    // DEVIATION(04 §6.4 step 7): `nextFireDate` also considers the next fire of the item's kept repeating rules
    // (long-tail, carriers) after this notification — ordering repeating rules only by their first fire would make
    // a later one-shot claim "nothing follows" although the daily repeat continues. Occurrences are rendered as
    // the first alert of that occurrence (item copy with dueDate = occurrence, no snooze) with nextFireDate nil and
    // isLastOfDay false (k0 subtitle "<Gün HH:mm> · Proje", line 2 "Asist'i bir kez açarsan…"): the next element is
    // the next occurrence days later, so "yarın sabah yine" / "devam edeceğim" would be false. Event occurrences use
    // `eventContent` like the event's own first alert.
    /// Fills title/subtitle/body of an item notification from NotificationCopy.
    static func applyContent(_ candidate: inout NagPlanCandidate, item: Item, projectName: String?,
                             timeline: NagSlotTimeline, rules: NagTimeRules) {
        let calendar = rules.calendar
        let text: NotificationText
        switch candidate.kind {
        case .first, .nag, .occurrence:
            var subject = item
            if candidate.kind == .occurrence {
                subject.dueDate = candidate.fireDate
                subject.snoozedUntil = nil
                subject.snoozeCount = 0
            }
            if item.kind == .waiting {
                text = NotificationCopy.followUpContent(item: subject, attempt: candidate.attempt,
                                                        fireDate: candidate.fireDate, calendar: calendar)
                candidate.bodyHasFollowLine = false
            } else if item.isEvent && candidate.kind != .nag {
                text = NotificationCopy.eventContent(item: subject, projectName: projectName, calendar: calendar)
                candidate.bodyHasFollowLine = false
            } else {
                // Occurrences: nothing of this item follows until the next occurrence (days or weeks later) or a
                // reconcile re-anchors it, so neither "yarın sabah yine" nor "devam edeceğim" may be promised.
                var next: Date? = nil
                if candidate.kind != .occurrence {
                    next = timeline.nextFire(after: candidate.fireDate, rules: rules)
                }
                var lastOfDay = false
                if let nextDate = next {
                    lastOfDay = rules.startOfDay(nextDate) > rules.startOfDay(candidate.fireDate)
                }
                text = NotificationCopy.itemContent(item: subject, projectName: projectName,
                                                    attempt: candidate.attempt, fireDate: candidate.fireDate,
                                                    nextFireDate: next, isLastOfDay: lastOfDay, calendar: calendar)
                candidate.bodyHasFollowLine = true
            }
        case .preAlert:
            text = NotificationCopy.preAlertContent(item: item, projectName: projectName,
                                                    leadMinutes: candidate.leadMinutes, calendar: calendar)
            candidate.bodyHasFollowLine = false
        case .longTail:
            text = NotificationCopy.longTailContent(item: item, projectName: projectName)
            candidate.bodyHasFollowLine = false
        case .carrier:
            text = NotificationCopy.recurrenceCarrierContent(item: item, projectName: projectName, calendar: calendar)
            candidate.bodyHasFollowLine = false
        case .briefing, .endOfDay, .backup, .signing, .sentinel, .horizon:
            return
        }
        candidate.title = text.title
        candidate.subtitle = text.subtitle
        candidate.body = text.body
    }
}
