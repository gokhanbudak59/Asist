// API: Packages/AsistCore/Sources/AsistCore/Update/UpdateManifest.swift
// Revision 4 — F3 (07 §6.2): `surum.json`, published by CI next to Asist.ipa on the GitHub release `son-surum`,
// and the pure "is a check due / is an update available" rules used by the app's UpdateChecker.
import Foundation

/// `{"build": 61, "sha": "…", "date": "2026-09-27T11:32:05Z", "notes": "commit subject"}`.
public struct UpdateManifest: Codable, Equatable {
    public var build: Int
    public var sha: String
    public var date: Date?
    public var notes: String

    /// Notes longer than this are cut (the Bugün band shows at most two lines).
    public static let maxNotesLength = 300
    /// The app refuses bigger responses before decoding (the real file is ~200 bytes).
    public static let maxBytes = 65_536

    public static let manifestURLString = "https://github.com/gokhanbudak59/Asist/releases/download/son-surum/surum.json"
    public static let ipaURLString = "https://github.com/gokhanbudak59/Asist/releases/download/son-surum/Asist.ipa"
    public static let unsignedIPAURLString = "https://github.com/gokhanbudak59/Asist/releases/download/son-surum/Asist-imzasiz.ipa"
    public static let releasePageURLString = "https://github.com/gokhanbudak59/Asist/releases/tag/son-surum"

    public init(build: Int, sha: String = "", date: Date? = nil, notes: String = "") {
        self.build = build
        self.sha = sha
        self.date = date
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey { case build, sha, date, notes }

    /// Lenient: `build` as Int or numeric String (negative / garbage → 0); missing sha/notes → "";
    /// `date` = ISO-8601 "…Z" (decoder strategy `.iso8601`) or nil. Notes are flattened to one line, trimmed and
    /// cut to `maxNotesLength` characters. Throws only when the payload is not a JSON object.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var rawBuild = 0
        if let number = try? c.decodeIfPresent(Int.self, forKey: .build) {
            rawBuild = number
        } else if let text = try? c.decodeIfPresent(String.self, forKey: .build) {
            rawBuild = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        build = max(0, rawBuild)
        sha = c.lenient(String.self, forKey: .sha, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        date = c.lenientOptional(Date.self, forKey: .date)
        notes = UpdateManifest.cleanedNotes(c.lenient(String.self, forKey: .notes, default: ""))
    }

    /// JSONDecoder (`.iso8601`) of `data`; nil when it is not a JSON object or `build <= 0`.
    public static func decode(from data: Data) -> UpdateManifest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(UpdateManifest.self, from: data) else { return nil }
        guard manifest.build > 0 else { return nil }
        return manifest
    }

    /// First 7 characters of the commit SHA ("" when unknown).
    public var shortSHA: String {
        String(sha.prefix(7))
    }

    /// Line breaks / tabs → spaces (scalar-wise, identical on Linux and iOS), trimmed, ≤ maxNotesLength characters.
    static func cleanedNotes(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if scalar == "\n" || scalar == "\r" || scalar == "\t" {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxNotesLength else { return trimmed }
        return String(trimmed.prefix(maxNotesLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// When to read `surum.json` and what the result means (07 R4-D6).
public enum UpdatePolicy {
    public static let checkInterval: TimeInterval = 12 * 3600
    public static let retryAfterFailure: TimeInterval = 30 * 60
    /// A last check this far in the future means the clock was moved back → check again.
    public static let clockSkewTolerance: TimeInterval = 5 * 60

    /// enabled && (lastCheck == nil || now − lastCheck ≥ 12 h || lastCheck > now + 5 min)
    /// && (lastAttempt == nil || now − lastAttempt ≥ 30 min || lastAttempt > now).
    public static func isCheckDue(enabled: Bool, lastCheck: Date?, lastAttempt: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        if let last = lastCheck {
            let elapsed = now.timeIntervalSince(last)
            let clockMovedBack = last > now.addingTimeInterval(clockSkewTolerance)
            guard elapsed >= checkInterval || clockMovedBack else { return false }
        }
        if let attempt = lastAttempt {
            let sinceAttempt = now.timeIntervalSince(attempt)
            guard sinceAttempt >= retryAfterFailure || attempt > now else { return false }
        }
        return true
    }

    /// latest > 0 && latest > installed.
    public static func isUpdateAvailable(latestBuild: Int, installedBuild: Int) -> Bool {
        latestBuild > 0 && latestBuild > installedBuild
    }

    /// "update_<build>" — key of `AppMeta.dismissedBanners` for the Bugün band of that build.
    public static func bannerID(build: Int) -> String {
        "update_" + String(build)
    }
}
