// WP11 — Son silinenler (05b B8, 04 §5.2): soft-deleted items of the last 30 days, swipe "Geri getir".
import SwiftUI
import AsistCore

struct RecentlyDeletedView: View {
    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        let items = store.recentlyDeleted
        let now = Date()
        Group {
            if items.isEmpty {
                EmptyStateView(title: "Son silinen yok",
                               message: "Sildiğin kayıtlar 30 gün burada durur; istersen geri getirebilirsin.",
                               systemImage: "trash")
            } else {
                List {
                    Section {
                        ForEach(items) { item in
                            row(item, now: now)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        restore(item)
                                    } label: {
                                        Label("Geri getir", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(Color.asistDone)
                                }
                                .contextMenu {
                                    Button {
                                        restore(item)
                                    } label: {
                                        Label("Geri getir", systemImage: "arrow.uturn.backward")
                                    }
                                }
                                .accessibilityAction(named: Text("Geri getir")) {
                                    restore(item)
                                }
                        }
                    } footer: {
                        Text("Geri getirmek için kaydı sağa kaydır. Silinen kayıtlar 30 gün sonra kalıcı olarak silinir.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Son silinenler")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ item: Item, now: Date) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(Color.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? item.kind.label : item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(detailLine(item, now: now))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: Metrics.rowMinHeight - 16, alignment: .leading)
        .padding(.vertical, 4)
    }

    /// "Görev · Silindi: 25 Eyl 14:02 · 28 gün kaldı"
    private func detailLine(_ item: Item, now: Date) -> String {
        var parts: [String] = [item.kind.label]
        if let deleted = item.deletedAt {
            parts.append("Silindi: " + SettingsFormat.shortStamp(deleted, calendar: AppTime.calendar))
            let purge = deleted.addingTimeInterval(30 * 24 * 3600)
            let days = max(0, Int(purge.timeIntervalSince(now) / (24 * 3600)))
            parts.append(days == 0 ? "bugün kalıcı silinecek" : String(days) + " gün kaldı")
        }
        if let name = store.projectName(for: item) {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }

    private func restore(_ item: Item) {
        if let token = store.restoreDeleted(item.id, at: Date()) {
            Haptics.success()
            toasts.show("Geri getirildi: " + TurkishText.truncated(item.title, max: 40), undo: token)
        } else {
            Haptics.error()
            toasts.show(store.canPersist ? "Geri getirilemedi." : "Kaydedilemedi. Lütfen tekrar dene.")
        }
    }
}
