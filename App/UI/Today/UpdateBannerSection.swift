// API: App/UI/Today/UpdateBannerSection.swift
// Revision 4 — F3 (07 §6.1, §6.5): blue "Yeni sürüm hazır (#61)" band on Bugün, under the main warning band.
// A List `Section` or nothing. "Nasıl kurulur?" opens Ayarlar › Güncelleme; × hides the band for that build.
import SwiftUI
import AsistCore

struct UpdateBannerSection: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router

    init() {}

    /// Visible when settings.updateCheckEnabled && UpdateSettingsText.isAvailable(meta:)
    /// && meta.dismissedBanners[UpdatePolicy.bannerID(build:)] is nil or ≤ now.
    static func isVisible(meta: AppMeta, settings: AppSettings, now: Date) -> Bool {
        guard settings.updateCheckEnabled, UpdateSettingsText.isAvailable(meta: meta) else { return false }
        if let hiddenUntil = meta.dismissedBanners[UpdatePolicy.bannerID(build: meta.latestBuildSeen)] {
            return hiddenUntil <= now
        }
        return true
    }

    var body: some View {
        let meta = store.meta
        if UpdateBannerSection.isVisible(meta: meta, settings: store.settings, now: Date()) {
            Section {
                band(meta: meta)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func band(meta: AppMeta) -> some View {
        let build = meta.latestBuildSeen
        let notes = meta.latestBuildNotes ?? ""
        return HStack(alignment: .top, spacing: Metrics.cardSpacing) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Yeni sürüm hazır (#" + String(build) + ")")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
                Button {
                    router.openRoute(.updates, in: .settings)
                } label: {
                    Text("Nasıl kurulur?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color.blue.opacity(0.22)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dismiss(build: build)
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Kapat")
        }
        .padding(Metrics.padding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(Color.blue.opacity(0.14))
        )
        .accessibilityElement(children: .contain)
    }

    /// Hides the band of this build (3650 days) and drops the keys of older builds.
    @MainActor
    private func dismiss(build: Int) {
        let id = UpdatePolicy.bannerID(build: build)
        let until = Date().addingTimeInterval(3650 * 86_400)
        store.updateMeta { meta in
            let stale = meta.dismissedBanners.keys.filter { key in
                key.hasPrefix("update_") && key != id
            }
            for key in stale {
                meta.dismissedBanners[key] = nil
            }
            meta.dismissedBanners[id] = until
        }
        Haptics.selection()
    }
}
