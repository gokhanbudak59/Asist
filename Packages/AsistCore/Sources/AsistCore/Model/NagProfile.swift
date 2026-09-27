// FILE: Packages/AsistCore/Sources/AsistCore/Model/NagProfile.swift
import Foundation

/// Semantics: 04 §6.4. All values are minutes except `dailyCap`/`maxPendingFollowUps` (counts).
public struct NagProfile: Codable, Equatable, Hashable {
    /// Follow-ups after the first alert, relative to the anchor.
    public var followUpOffsetsMinutes: [Int]
    /// After the offsets: repeat step inside work hours (nil = jump to next day start).
    public var repeatMinutesWorkHours: Int?
    /// After the offsets: repeat step outside work hours but outside quiet hours (nil = jump to next day start).
    public var repeatMinutesOffHours: Int?
    /// Max notifications of one item per calendar day (first alert included).
    public var dailyCap: Int
    /// Max pending follow-ups (k >= 1) per item in one plan.
    public var maxPendingFollowUps: Int

    public init(followUpOffsetsMinutes: [Int], repeatMinutesWorkHours: Int?, repeatMinutesOffHours: Int?,
                dailyCap: Int, maxPendingFollowUps: Int) {
        self.followUpOffsetsMinutes = followUpOffsetsMinutes
        self.repeatMinutesWorkHours = repeatMinutesWorkHours
        self.repeatMinutesOffHours = repeatMinutesOffHours
        self.dailyCap = dailyCap
        self.maxPendingFollowUps = maxPendingFollowUps
    }

    /// normal/low (05b C1): +10, +30, +90 min, then every 2 h **inside work hours only**; ≤ 6/day.
    public static let nazik = NagProfile(followUpOffsetsMinutes: [10, 30, 90], repeatMinutesWorkHours: 120,
                                         repeatMinutesOffHours: nil, dailyCap: 6, maxPendingFollowUps: 6)
    /// high (05b C4): hourly inside work hours, no evening repeats.
    public static let israrci = NagProfile(followUpOffsetsMinutes: [5, 15, 30, 60], repeatMinutesWorkHours: 60,
                                           repeatMinutesOffHours: nil, dailyCap: 10, maxPendingFollowUps: 8)
    /// critical: offsets respect the 3-minute spacing of the rate limiter (§6.4 step 5).
    public static let birakmaz = NagProfile(followUpOffsetsMinutes: [3, 6, 10, 15], repeatMinutesWorkHours: 15,
                                            repeatMinutesOffHours: 15, dailyCap: 30, maxPendingFollowUps: 10)
    public static let takip = NagProfile(followUpOffsetsMinutes: [], repeatMinutesWorkHours: nil,
                                         repeatMinutesOffHours: nil, dailyCap: 1, maxPendingFollowUps: 4)
    /// Events (D31): first alert only.
    public static let etkinlik = NagProfile(followUpOffsetsMinutes: [], repeatMinutesWorkHours: nil,
                                            repeatMinutesOffHours: nil, dailyCap: 1, maxPendingFollowUps: 0)

    enum CodingKeys: String, CodingKey {
        case followUpOffsetsMinutes, repeatMinutesWorkHours, repeatMinutesOffHours, dailyCap, maxPendingFollowUps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NagProfile.nazik
        let offsets = c.lenient([Int].self, forKey: .followUpOffsetsMinutes, default: d.followUpOffsetsMinutes)
        followUpOffsetsMinutes = Array(Set(offsets.filter { $0 > 0 && $0 <= 1440 })).sorted()
        // A repeat step of 0 would never advance the chain (05a #20): clamp to >= 5 min.
        repeatMinutesWorkHours = c.lenientOptional(Int.self, forKey: .repeatMinutesWorkHours).map { max(5, $0) }
        repeatMinutesOffHours = c.lenientOptional(Int.self, forKey: .repeatMinutesOffHours).map { max(5, $0) }
        dailyCap = min(60, max(1, c.lenient(Int.self, forKey: .dailyCap, default: d.dailyCap)))
        maxPendingFollowUps = min(20, max(0, c.lenient(Int.self, forKey: .maxPendingFollowUps, default: d.maxPendingFollowUps)))
    }
}

/// Code-defined profile table. Not persisted in v1.x (parameters are not user-editable, so a stored copy
/// would freeze today's defaults forever); `AppSettings.nagProfiles` is a computed property returning `NagProfiles()`.
public struct NagProfiles: Codable, Equatable, Hashable {
    public var nazik: NagProfile = .nazik
    public var israrci: NagProfile = .israrci
    public var birakmaz: NagProfile = .birakmaz
    public var takip: NagProfile = .takip
    public var etkinlik: NagProfile = .etkinlik

    public init() {}

    public subscript(_ kind: NagProfileKind) -> NagProfile {
        switch kind {
        case .nazik: return nazik
        case .israrci: return israrci
        case .birakmaz: return birakmaz
        case .takip: return takip
        case .etkinlik: return etkinlik
        }
    }

    enum CodingKeys: String, CodingKey { case nazik, israrci, birakmaz, takip, etkinlik }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nazik = c.lenient(NagProfile.self, forKey: .nazik, default: .nazik)
        israrci = c.lenient(NagProfile.self, forKey: .israrci, default: .israrci)
        birakmaz = c.lenient(NagProfile.self, forKey: .birakmaz, default: .birakmaz)
        takip = c.lenient(NagProfile.self, forKey: .takip, default: .takip)
        etkinlik = c.lenient(NagProfile.self, forKey: .etkinlik, default: .etkinlik)
    }
}
