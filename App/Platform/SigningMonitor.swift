// API: App/Platform/SigningMonitor.swift
// WP0 STUB (04 §3.6.11) — replaced by WP8. Reads the embedded profile; never reports a re-sign.
import Foundation
import Observation
import AsistCore

@MainActor
@Observable
final class SigningMonitor {
    private(set) var profile: ProvisioningProfileInfo? = nil
    /// profile?.expirationDate. nil when the embedded profile is unreadable.
    private(set) var expiryDate: Date? = nil

    /// Reads embedded.mobileprovision; sets profile/expiryDate. No store access, no writes.
    func reload() {
        let info = ProvisioningProfileReader.readEmbedded()
        profile = info
        expiryDate = info?.expirationDate
    }

    /// WP0 STUB: reload() only; never reports a changed profile (so no rebuildAll).
    func refresh(store: DataStore) -> Bool {
        reload()
        return false
    }

    /// UI only (AppStatus): installDate + 7 days while that is still in the future, else nil.
    func estimatedExpiry(installDate: Date?, now: Date) -> Date? {
        guard let installDate = installDate else { return nil }
        let estimate = installDate.addingTimeInterval(7 * 24 * 60 * 60)
        return estimate > now ? estimate : nil
    }
}
