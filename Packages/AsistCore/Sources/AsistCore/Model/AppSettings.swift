// FILE: Packages/AsistCore/Sources/AsistCore/Model/AppSettings.swift
import Foundation

/// Every user-changeable setting with its v1 default (03 §4.11, decisions D7/D10/D11/D16/D18–D21/D31/D32).
public struct AppSettings: Codable, Equatable, Hashable {
    // Genel
    public var userName: String = ""                         // hitap: "Günaydın, Gökhan"
    public var speakConfirmations: Bool = true               // D18: on a private route (headphones/BT/car) only
    public var speakConfirmationsOnSpeaker: Bool = false     // D18: also through the loudspeaker
    public var ttsRate: TTSRate = .normal
    public var autoSaveSeconds: Int = 4                      // 0 = kapalı; allowed 0, 3, 4, 6
    public var noTimeBehavior: NoTimeBehavior = .ask
    // Parser time words
    public var defaultDayTime = ClockTime(9, 0)
    public var sabah = ClockTime(9, 0)
    public var ogledenOnce = ClockTime(11, 0)                // "öğleden önce" (G7)
    public var ogle = ClockTime(12, 0)
    public var ogledenSonra = ClockTime(14, 0)
    public var aksamustu = ClockTime(17, 0)
    public var aksam = ClockTime(19, 0)
    public var gece = ClockTime(22, 0)
    public var ambiguousHoursPM: Bool = true                 // 1–6 without qualifier → 13–18
    // Zamanlar
    public var workdays: [Int] = [1, 2, 3, 4, 5]             // ISO weekdays; never empty after decoding
    public var workStart = ClockTime(8, 30)
    public var workEnd = ClockTime(18, 0)
    public var offDayStart = ClockTime(9, 0)                 // "day start" on non-workdays
    public var quietStart = ClockTime(22, 30)
    public var quietEnd = ClockTime(7, 30)
    public var followUpAskTime = ClockTime(16, 0)            // Takip "Geldi mi?" time
    public var waitingDefaultWorkdays: Int = 2               // 1…10
    public var waitingDefaultTime = ClockTime(10, 0)
    // Israr
    public var profileForLow: NagProfileKind = .nazik
    public var profileForNormal: NagProfileKind = .nazik
    public var profileForHigh: NagProfileKind = .israrci
    public var profileForCritical: NagProfileKind = .birakmaz
    public var criticalIgnoresQuietHours: Bool = false
    public var eventDefaultLeadMinutes: Int = 15             // D31; 0 = no default pre-alert for events
    public var badgeMode: BadgeMode = .overdue
    public var lockScreenShowsContent: Bool = true
    // Özetler
    public var briefingEnabled: Bool = true
    public var briefingTime = ClockTime(8, 0)
    public var briefingWorkdaysOnly: Bool = true
    public var briefingWhenEmpty: Bool = false
    public var briefingTapSpeaks: Bool = false
    public var endOfDayEnabled: Bool = true
    public var endOfDayTime = ClockTime(17, 45)
    public var endOfDayWorkdaysOnly: Bool = true
    public var moveSkipsWeekend: Bool = true
    public var backupReminderEnabled: Bool = true
    public var backupReminderWeekday: Int = 7                // ISO: 7 = Pazar; 1…7
    public var backupReminderTime = ClockTime(20, 0)
    // Tetikleyiciler / ses
    public var volumeTriggerEnabled: Bool = true
    public var restoreVolumeAfterTrigger: Bool = true
    public var silenceSeconds: Double = 1.8                  // 1.2 / 1.8 / 2.5 / 3.5 (clamped 0.8…5)
    public var onDeviceRecognitionOnly: Bool = false
    // Akıllı Mod (v1.1; persisted but unused in v1.0)
    public var smartModeEnabled: Bool = false
    public var smartModeModel: String = "claude-opus-5"
    public var smartModeAutoOnLowConfidence: Bool = true
    // Durum
    public var activeProjectID: UUID? = nil                  // v1.0 has no UI that sets it (v1.1)
    public var onboardingCompleted: Bool = false
    /// D32 "Sessize al": nags before this instant collapse to it; first alerts before it are silent.
    public var muteUntil: Date? = nil

    public init() {}

    /// Code-defined profile table (not persisted, see `NagProfiles`).
    public var nagProfiles: NagProfiles { NagProfiles() }

    public func profileKind(for priority: Priority) -> NagProfileKind {
        switch priority {
        case .low: return profileForLow
        case .normal: return profileForNormal
        case .high: return profileForHigh
        case .critical: return profileForCritical
        }
    }

    public func isWorkday(isoWeekday: Int) -> Bool { workdays.contains(isoWeekday) }

    /// Mute is active at `now` and covers `date`.
    public func isMuted(_ date: Date, now: Date) -> Bool {
        guard let until = muteUntil, now < until else { return false }
        return date < until
    }

    enum CodingKeys: String, CodingKey {
        case userName, speakConfirmations, speakConfirmationsOnSpeaker, ttsRate, autoSaveSeconds, noTimeBehavior
        case defaultDayTime, sabah, ogledenOnce, ogle, ogledenSonra, aksamustu, aksam, gece, ambiguousHoursPM
        case workdays, workStart, workEnd, offDayStart, quietStart, quietEnd, followUpAskTime
        case waitingDefaultWorkdays, waitingDefaultTime
        case profileForLow, profileForNormal, profileForHigh, profileForCritical
        case criticalIgnoresQuietHours, eventDefaultLeadMinutes, badgeMode, lockScreenShowsContent
        case briefingEnabled, briefingTime, briefingWorkdaysOnly, briefingWhenEmpty, briefingTapSpeaks
        case endOfDayEnabled, endOfDayTime, endOfDayWorkdaysOnly, moveSkipsWeekend
        case backupReminderEnabled, backupReminderWeekday, backupReminderTime
        case volumeTriggerEnabled, restoreVolumeAfterTrigger, silenceSeconds, onDeviceRecognitionOnly
        case smartModeEnabled, smartModeModel, smartModeAutoOnLowConfidence
        case activeProjectID, onboardingCompleted, muteUntil
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userName = c.lenient(String.self, forKey: .userName, default: userName)
        speakConfirmations = c.lenient(Bool.self, forKey: .speakConfirmations, default: speakConfirmations)
        speakConfirmationsOnSpeaker = c.lenient(Bool.self, forKey: .speakConfirmationsOnSpeaker, default: speakConfirmationsOnSpeaker)
        ttsRate = c.lenient(TTSRate.self, forKey: .ttsRate, default: ttsRate)
        let rawAutoSave = c.lenient(Int.self, forKey: .autoSaveSeconds, default: autoSaveSeconds)
        autoSaveSeconds = [0, 3, 4, 6].contains(rawAutoSave) ? rawAutoSave : 4
        noTimeBehavior = c.lenient(NoTimeBehavior.self, forKey: .noTimeBehavior, default: noTimeBehavior)
        defaultDayTime = c.lenient(ClockTime.self, forKey: .defaultDayTime, default: defaultDayTime)
        sabah = c.lenient(ClockTime.self, forKey: .sabah, default: sabah)
        ogledenOnce = c.lenient(ClockTime.self, forKey: .ogledenOnce, default: ogledenOnce)
        ogle = c.lenient(ClockTime.self, forKey: .ogle, default: ogle)
        ogledenSonra = c.lenient(ClockTime.self, forKey: .ogledenSonra, default: ogledenSonra)
        aksamustu = c.lenient(ClockTime.self, forKey: .aksamustu, default: aksamustu)
        aksam = c.lenient(ClockTime.self, forKey: .aksam, default: aksam)
        gece = c.lenient(ClockTime.self, forKey: .gece, default: gece)
        ambiguousHoursPM = c.lenient(Bool.self, forKey: .ambiguousHoursPM, default: ambiguousHoursPM)
        // Never empty, only 1…7 (05a #8: an empty set would hang the nag chain search).
        let rawWorkdays = c.lenient([Int].self, forKey: .workdays, default: workdays)
        let validWorkdays = Array(Set(rawWorkdays.filter { (1...7).contains($0) })).sorted()
        workdays = validWorkdays.isEmpty ? [1, 2, 3, 4, 5] : validWorkdays
        workStart = c.lenient(ClockTime.self, forKey: .workStart, default: workStart)
        workEnd = c.lenient(ClockTime.self, forKey: .workEnd, default: workEnd)
        offDayStart = c.lenient(ClockTime.self, forKey: .offDayStart, default: offDayStart)
        quietStart = c.lenient(ClockTime.self, forKey: .quietStart, default: quietStart)
        quietEnd = c.lenient(ClockTime.self, forKey: .quietEnd, default: quietEnd)
        followUpAskTime = c.lenient(ClockTime.self, forKey: .followUpAskTime, default: followUpAskTime)
        waitingDefaultWorkdays = min(10, max(1, c.lenient(Int.self, forKey: .waitingDefaultWorkdays, default: waitingDefaultWorkdays)))
        waitingDefaultTime = c.lenient(ClockTime.self, forKey: .waitingDefaultTime, default: waitingDefaultTime)
        profileForLow = AppSettings.decodedProfile(c, .profileForLow, fallback: .nazik)   // WP0-FIX: per-field fallback for unknown raw values
        profileForNormal = AppSettings.decodedProfile(c, .profileForNormal, fallback: .nazik)   // WP0-FIX: per-field fallback for unknown raw values
        profileForHigh = AppSettings.decodedProfile(c, .profileForHigh, fallback: .israrci)   // WP0-FIX: per-field fallback for unknown raw values
        profileForCritical = AppSettings.decodedProfile(c, .profileForCritical, fallback: .birakmaz)   // WP0-FIX: per-field fallback for unknown raw values
        criticalIgnoresQuietHours = c.lenient(Bool.self, forKey: .criticalIgnoresQuietHours, default: criticalIgnoresQuietHours)
        eventDefaultLeadMinutes = min(1440, max(0, c.lenient(Int.self, forKey: .eventDefaultLeadMinutes, default: eventDefaultLeadMinutes)))
        badgeMode = c.lenient(BadgeMode.self, forKey: .badgeMode, default: badgeMode)
        lockScreenShowsContent = c.lenient(Bool.self, forKey: .lockScreenShowsContent, default: lockScreenShowsContent)
        briefingEnabled = c.lenient(Bool.self, forKey: .briefingEnabled, default: briefingEnabled)
        briefingTime = c.lenient(ClockTime.self, forKey: .briefingTime, default: briefingTime)
        briefingWorkdaysOnly = c.lenient(Bool.self, forKey: .briefingWorkdaysOnly, default: briefingWorkdaysOnly)
        briefingWhenEmpty = c.lenient(Bool.self, forKey: .briefingWhenEmpty, default: briefingWhenEmpty)
        briefingTapSpeaks = c.lenient(Bool.self, forKey: .briefingTapSpeaks, default: briefingTapSpeaks)
        endOfDayEnabled = c.lenient(Bool.self, forKey: .endOfDayEnabled, default: endOfDayEnabled)
        endOfDayTime = c.lenient(ClockTime.self, forKey: .endOfDayTime, default: endOfDayTime)
        endOfDayWorkdaysOnly = c.lenient(Bool.self, forKey: .endOfDayWorkdaysOnly, default: endOfDayWorkdaysOnly)
        moveSkipsWeekend = c.lenient(Bool.self, forKey: .moveSkipsWeekend, default: moveSkipsWeekend)
        backupReminderEnabled = c.lenient(Bool.self, forKey: .backupReminderEnabled, default: backupReminderEnabled)
        backupReminderWeekday = min(7, max(1, c.lenient(Int.self, forKey: .backupReminderWeekday, default: backupReminderWeekday)))
        backupReminderTime = c.lenient(ClockTime.self, forKey: .backupReminderTime, default: backupReminderTime)
        volumeTriggerEnabled = c.lenient(Bool.self, forKey: .volumeTriggerEnabled, default: volumeTriggerEnabled)
        restoreVolumeAfterTrigger = c.lenient(Bool.self, forKey: .restoreVolumeAfterTrigger, default: restoreVolumeAfterTrigger)
        silenceSeconds = min(5, max(0.8, c.lenient(Double.self, forKey: .silenceSeconds, default: silenceSeconds)))
        onDeviceRecognitionOnly = c.lenient(Bool.self, forKey: .onDeviceRecognitionOnly, default: onDeviceRecognitionOnly)
        smartModeEnabled = c.lenient(Bool.self, forKey: .smartModeEnabled, default: smartModeEnabled)
        smartModeModel = c.lenient(String.self, forKey: .smartModeModel, default: smartModeModel)
        smartModeAutoOnLowConfidence = c.lenient(Bool.self, forKey: .smartModeAutoOnLowConfidence, default: smartModeAutoOnLowConfidence)
        activeProjectID = c.lenientOptional(UUID.self, forKey: .activeProjectID)
        onboardingCompleted = c.lenient(Bool.self, forKey: .onboardingCompleted, default: onboardingCompleted)
        muteUntil = c.lenientOptional(Date.self, forKey: .muteUntil)
    }

    private static func selectable(_ kind: NagProfileKind, fallback: NagProfileKind) -> NagProfileKind {
        NagProfileKind.selectable.contains(kind) ? kind : fallback
    }

    // WP0-FIX: NagProfileKind.init(from:) maps an unknown raw value to .nazik, which silently downgraded a garbled
    // profileForCritical (default .birakmaz, D7). Decode the raw string here so missing/unknown/non-selectable values
    // fall back to each field's documented default.
    private static func decodedProfile(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys,
                                       fallback: NagProfileKind) -> NagProfileKind {
        guard let raw = c.lenientOptional(String.self, forKey: key),
              let kind = NagProfileKind(rawValue: raw) else { return fallback }
        return selectable(kind, fallback: fallback)
    }
}
