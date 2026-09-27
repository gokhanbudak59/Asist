// WP11 — Tanılama (03 §4.11, 04 §4.3, §5.2): last reconcile report, pending notifications (first 30, "n/64"),
// last BG refresh, speech support, in-app log with ShareLink, "Test bildirimi (10 sn)", "Planı yeniden kur".
import SwiftUI
import Speech
import AsistCore

struct DiagnosticsView: View {
    @Environment(ReminderEngine.self) private var engine
    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    struct PendingRow: Identifiable {
        let id: String
        let date: Date?
        let title: String
    }

    @State private var pending: [PendingRow] = []
    @State private var pendingTotal = 0
    @State private var pendingLoaded = false
    @State private var logLines: [String] = []
    @State private var busy = false
    @State private var speech = SpeechSupport(recognizerAvailable: false, onDevice: false, localeOK: false)

    struct SpeechSupport: Equatable {
        let recognizerAvailable: Bool
        let onDevice: Bool
        let localeOK: Bool
    }

    private static let pendingLimit = 30
    private static let systemLimit = 64

    var body: some View {
        let calendar = AppTime.calendar
        List {
            reportSection(calendar: calendar)
            actionsSection
            pendingSection(calendar: calendar)
            systemSection(calendar: calendar)
            logSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tanılama")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            speech = DiagnosticsView.speechSupport()
            await reload()
        }
        .refreshable {
            // `.refreshable` has no inherited actor context: only an awaited call into the main actor here.
            await reload()
        }
    }

    @MainActor
    private func reload() async {
        logLines = Array(AsistLog.recentLines().reversed())
        await loadPending()
    }

    // MARK: Sections

    @ViewBuilder
    private func reportSection(calendar: Calendar) -> some View {
        Section {
            if let report = engine.lastReport {
                LabeledContent("Zaman", value: SettingsFormat.logStamp(report.at, calendar: calendar))
                LabeledContent("Neden", value: report.reason)
                LabeledContent("Bildirim izni", value: report.authorized ? "var" : "yok")
                LabeledContent("Zamana duyarlı", value: report.timeSensitiveAllowed ? "açık" : "kapalı")
                LabeledContent("Planlanan", value: String(report.planned))
                LabeledContent("Sığmayan (bütçe)", value: String(report.dropped))
                LabeledContent("Seyreltilen (hız sınırı)", value: String(report.rateLimited))
                LabeledContent("Kayıt bütçesi", value: String(report.itemBudget))
                LabeledContent("Yeni eklenen istek", value: String(report.added))
                LabeledContent("Rozet", value: String(report.badge))
            } else {
                let meta = store.meta
                LabeledContent("Zaman", value: meta.lastReconcileAt.map { SettingsFormat.logStamp($0, calendar: calendar) } ?? "henüz yok")
                LabeledContent("Neden", value: meta.lastReconcileReason ?? "—")
                LabeledContent("Planlanan", value: String(meta.lastPlannedCount))
                LabeledContent("Sığmayan (bütçe)", value: String(meta.lastDroppedCount))
            }
        } header: {
            Text("Son planlama")
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            Button {
                sendTest()
            } label: {
                Label("Test bildirimi (10 sn)", systemImage: "paperplane")
            }
            .disabled(busy)
            Button {
                rebuild()
            } label: {
                Label("Planı yeniden kur", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(busy || !store.isLoaded)
        } footer: {
            Text("“Planı yeniden kur” bekleyen bütün Asist bildirimlerini silip kayıtlardan baştan planlar. Kayıtların etkilenmez.")
        }
    }

    @ViewBuilder
    private func pendingSection(calendar: Calendar) -> some View {
        Section {
            LabeledContent("Planlanan bildirimler",
                           value: pendingLoaded ? String(pendingTotal) + "/" + String(DiagnosticsView.systemLimit) : "…")
            ForEach(pending) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title.isEmpty ? "(başlıksız)" : row.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Text(pendingDateText(row.date, calendar: calendar) + " · " + row.id)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .monospacedDigit()
                }
            }
            if pendingTotal > pending.count {
                Text("… ve " + String(pendingTotal - pending.count) + " bildirim daha")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        } header: {
            Text("Bekleyen bildirimler")
        } footer: {
            Text("iOS bir uygulama için en yakın 64 bildirimi tutar. Tekrarlayan bildirimlerde sıradaki çalma zamanı gösterilir.")
        }
    }

    @ViewBuilder
    private func systemSection(calendar: Calendar) -> some View {
        let meta = store.meta
        Section {
            LabeledContent("Son arka plan yenilemesi",
                           value: meta.lastBackgroundRefreshAt.map { SettingsFormat.logStamp($0, calendar: calendar) } ?? "henüz yok")
            LabeledContent("Son veri kaydı",
                           value: meta.lastSavedAt.map { SettingsFormat.logStamp($0, calendar: calendar) } ?? "henüz yok")
            LabeledContent("Türkçe konuşma tanıma", value: speech.recognizerAvailable && speech.localeOK ? "var" : "yok")
            LabeledContent("Cihaz içi tanıma", value: speech.onDevice ? "destekleniyor" : "desteklenmiyor")
            LabeledContent("Veri dosyası", value: store.isLoaded ? "okundu" : "okunamadı")
            LabeledContent("Sürüm", value: SettingsFormat.versionText)
        } header: {
            Text("Sistem")
        } footer: {
            Text("Arka plan yenilemesini iOS kendi zamanlar; gelmemesi normaldir, hatırlatmalar ona bağlı değildir.")
        }
    }

    @ViewBuilder
    private var logSection: some View {
        Section {
            ShareLink(item: logLines.reversed().joined(separator: "\n")) {
                Label("Günlüğü paylaş", systemImage: Symbol.export)
            }
            .disabled(logLines.isEmpty)
            if logLines.isEmpty {
                Text("Günlük boş.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            } else {
                ForEach(logLines.indices, id: \.self) { index in
                    Text(logLines[index])
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Günlük (en yeni üstte)")
        } footer: {
            Text("Günlükte söylediğin cümleler ve not içerikleri bulunmaz.")
        }
    }

    // MARK: Actions

    private func loadPending() async {
        let scheduler = AppEnvironment.shared.scheduler
        let summary = await scheduler.pendingSummary()
        var rows: [PendingRow] = []
        for entry in summary.prefix(DiagnosticsView.pendingLimit) {
            rows.append(PendingRow(id: entry.id, date: entry.date, title: entry.title))
        }
        pending = rows
        pendingTotal = summary.count
        pendingLoaded = true
    }

    private func sendTest() {
        busy = true
        Task { @MainActor in
            await engine.sendTestNotification()
            toasts.show("10 saniye içinde bir test bildirimi gelecek.")
            logLines = Array(AsistLog.recentLines().reversed())
            busy = false
        }
    }

    private func rebuild() {
        busy = true
        Task { @MainActor in
            await engine.rebuildAll(reason: "manual")
            await loadPending()
            logLines = Array(AsistLog.recentLines().reversed())
            toasts.show("Plan yeniden kuruldu.")
            busy = false
        }
    }

    private func pendingDateText(_ date: Date?, calendar: Calendar) -> String {
        guard let date = date else { return "zaman yok" }
        return SettingsFormat.shortStamp(date, calendar: calendar)
    }

    static func speechSupport() -> SpeechSupport {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR")) else {
            return SpeechSupport(recognizerAvailable: false, onDevice: false, localeOK: false)
        }
        let localeOK = recognizer.locale.identifier.hasPrefix("tr")
        return SpeechSupport(recognizerAvailable: recognizer.isAvailable,
                             onDevice: localeOK && recognizer.supportsOnDeviceRecognition,
                             localeOK: localeOK)
    }
}
