// API: App/Platform/SigningMonitor.swift
// WP8 (04 §3.6.11, D17, 01c §3–§4). Reads the embedded provisioning profile (free Apple ID → 7-day signature),
// exposes its expiry to the planner/UI and detects a re-sign (Sideloadly) through the profile CreationDate stamp.
import Foundation
import Observation
import AsistCore

@MainActor
@Observable
final class SigningMonitor {

    /// Banner/status stage derived from `expiryDate` (03 §9 row 20: banner from T-72 h; §3.6.6 red/yellow).
    /// Nested so the name cannot collide with a type of another work package.
    enum ExpiryStage: Equatable {
        /// Profile unreadable (simulator, ad-hoc/unsigned install) → no banner; UI shows the estimate or "bilinmiyor".
        case unknown
        /// More than 72 hours left.
        case valid
        /// ≤ 72 hours left, expiry on a later calendar day (`days` = 1…3 calendar days away).
        case soon(days: Int)
        /// Expiry later today.
        case today
        /// Expiry passed (normally iOS no longer launches the app; possible with a wrong clock).
        case expired
    }

    /// Window in which the signing banner is shown (03 §9 row 20: "T-72 sa bant").
    static let bannerWindow: TimeInterval = 72 * 60 * 60
    /// Inside this window the banner is red instead of yellow.
    static let urgentWindow: TimeInterval = 24 * 60 * 60
    /// Free Apple ID signatures last 7 days (01c §3.1); UI-only estimate when the profile is unreadable.
    static let freeSigningLifetime: TimeInterval = 7 * 24 * 60 * 60

    private(set) var profile: ProvisioningProfileInfo? = nil
    /// profile?.expirationDate. nil when the embedded profile is unreadable → no signing notifications and no
    /// follow-up clamp are planned (05a #28).
    private(set) var expiryDate: Date? = nil

    // Log de-duplication only (not UI state).
    @ObservationIgnored private var loggedStamp: Double? = nil
    @ObservationIgnored private var loggedUnreadable = false

    // MARK: - Contract (04 §3.6.11)

    /// Reads embedded.mobileprovision (ProvisioningProfileReader); sets profile/expiryDate. No store access, no writes.
    /// Called first in bootstrap() so that every process — including background launches — plans with it (05a #4).
    /// Cheap (a few KB read); safe to call on every activation. Never throws: the reader returns nil for a missing
    /// or unparsable profile.
    func reload() {
        let info = ProvisioningProfileReader.readEmbedded()
        if info != profile {
            profile = info
        }
        let newExpiry = info?.expirationDate
        if newExpiry != expiryDate {
            expiryDate = newExpiry
        }
        logReadResult(info)
    }

    /// reload() + compares the profile CreationDate stamp with meta.lastProfileStamp; stores the new stamp via
    /// store.updateMeta (only when store.isLoaded). Returns true when the profile changed (re-sign / first launch)
    /// → caller runs engine.rebuildAll. Returns false when !store.isLoaded.
    func refresh(store: DataStore) -> Bool {
        reload()
        // Never write meta while the data file has not been read (device locked since boot, §9 #41): the stamp
        // is compared again on the next activation after the store loaded.
        guard store.isLoaded else { return false }
        // Unreadable profile: nothing to compare. The old stamp is kept so that the next readable profile is
        // compared against the last known one (no spurious rebuild).
        guard let info = profile else { return false }

        let stamp = SigningMonitor.stamp(of: info)
        let previous = store.meta.lastProfileStamp
        if let previous = previous, SigningMonitor.sameStamp(previous, stamp) {
            return false
        }

        store.updateMeta { meta in
            meta.lastProfileStamp = stamp
        }
        let newText = SigningMonitor.stampText(stamp)
        let expiryText = info.expirationDate.description
        if let previous = previous {
            let oldText = SigningMonitor.stampText(previous)
            let message = "Yeniden imza algılandı: profil damgası " + oldText + " → " + newText
            AsistLog.info(message + ", yeni bitiş " + expiryText + "; tüm bildirimler yeniden kuruluyor", .app)
        } else {
            let message = "İlk profil damgası kaydedildi (" + newText + ")"
            AsistLog.info(message + ", bitiş " + expiryText + "; tüm bildirimler kuruluyor", .app)
        }
        return true
    }

    /// UI only (AppStatus): installDate + 7 days while that is still in the future, else nil →
    /// "İmza bitişi: bilinmiyor". Shown with "(tahmini)".
    func estimatedExpiry(installDate: Date?, now: Date) -> Date? {
        guard let installDate = installDate else { return nil }
        let estimate = installDate.addingTimeInterval(SigningMonitor.freeSigningLifetime)
        return estimate > now ? estimate : nil
    }

    // MARK: - Helpers for banners and the status screen (additive; never planner inputs)

    /// Seconds until expiry (negative when expired); nil when the profile is unreadable.
    func remainingSeconds(now: Date) -> TimeInterval? {
        guard let expiry = expiryDate else { return nil }
        return expiry.timeIntervalSince(now)
    }

    /// true when a readable profile has expired at `now`.
    func isExpired(now: Date) -> Bool {
        guard let expiry = expiryDate else { return false }
        return now >= expiry
    }

    /// true while the signing banner should be red: expired or ≤ 24 hours left. false when unknown.
    func isUrgent(now: Date) -> Bool {
        guard let remaining = remainingSeconds(now: now) else { return false }
        return remaining <= SigningMonitor.urgentWindow
    }

    /// Stage of the signing banner at `now` in `calendar` (the app passes `AppTime.calendar`).
    func expiryStage(now: Date, calendar: Calendar) -> ExpiryStage {
        guard let expiry = expiryDate else { return .unknown }
        let remaining = expiry.timeIntervalSince(now)
        if remaining <= 0 { return .expired }
        if remaining > SigningMonitor.bannerWindow { return .valid }
        let startNow = calendar.startOfDay(for: now)
        let startExpiry = calendar.startOfDay(for: expiry)
        let dayDiff = calendar.dateComponents([.day], from: startNow, to: startExpiry).day ?? 0
        if dayDiff <= 0 { return .today }
        return .soon(days: min(dayDiff, 3))
    }

    /// Turkish banner line for the signing stage (03 §7.12 `banner.sign_days` / `banner.sign_today`), nil when no
    /// signing banner is due (unknown profile or more than 72 hours left).
    func bannerText(now: Date, calendar: Calendar) -> String? {
        switch expiryStage(now: now, calendar: calendar) {
        case .unknown, .valid:
            return nil
        case .soon(let days):
            return "İmza " + String(days) + " gün sonra bitiyor. Yeniden yükleme zamanı yaklaşıyor."
        case .today:
            guard let expiry = expiryDate else { return nil }
            let clock = TurkishDateFormatter.time(expiry, calendar: calendar)
            return "İmza bugün bitiyor (saat " + clock + "). Bilgisayarda yeniden yükle."
        case .expired:
            return "İmzanın süresi doldu. Bilgisayarda Sideloadly ile yeniden yükle; verilerin korunur."
        }
    }

    /// "Ücretsiz Apple ID (7 gün)" / "Geliştirici" / nil (unreadable profile) for the status screen.
    var signingKindText: String? {
        guard let info = profile else { return nil }
        return info.looksLikeFreeAppleID ? "Ücretsiz Apple ID (7 gün)" : "Geliştirici"
    }

    // MARK: - Private

    /// Re-sign stamp: profile CreationDate (seconds since 1970); ExpirationDate when CreationDate is missing
    /// (01c §4.4). Every new profile issued by Sideloadly carries a new CreationDate.
    private static func stamp(of info: ProvisioningProfileInfo) -> Double {
        (info.creationDate ?? info.expirationDate).timeIntervalSince1970
    }

    /// Profile dates are whole seconds; the tolerance absorbs any JSON round-trip noise. A NaN/garbage stored
    /// value compares unequal → treated as changed and overwritten (one extra rebuild, never a crash).
    private static func sameStamp(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1.0
    }

    /// Log text for a stamp: the Double description, never an Int conversion (a corrupt huge value would trap).
    private static func stampText(_ value: Double) -> String {
        String(describing: value)
    }

    private func logReadResult(_ info: ProvisioningProfileInfo?) {
        if let info = info {
            let stamp = SigningMonitor.stamp(of: info)
            if let logged = loggedStamp, SigningMonitor.sameStamp(logged, stamp) { return }
            loggedStamp = stamp
            loggedUnreadable = false
            let kind = info.looksLikeFreeAppleID ? "ücretsiz Apple ID" : "geliştirici"
            let expiryText = info.expirationDate.description
            AsistLog.info("İmza profili okundu: bitiş " + expiryText + ", tür " + kind, .app)
        } else {
            if loggedUnreadable { return }
            loggedUnreadable = true
            loggedStamp = nil
            AsistLog.info("embedded.mobileprovision okunamadı (imzasız/ad-hoc kurulum): imza uyarıları planlanmaz", .app)
        }
    }
}
