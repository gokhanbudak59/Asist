// Revision 4 (07 §7, F4): "Haftalık rapor" — this or last week as a plain-text status report (WeeklyReportBuilder)
// to read, copy or share (e-mail, WhatsApp…), optionally rewritten by Smart Mode. Built in `body` from the store
// inside TimelineView(.everyMinute) (like Listeler), so it follows every change and the day texts stay current.
import SwiftUI
import UIKit
import AsistCore

@MainActor
struct WeeklyReportView: View {
    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    /// 0 = bu hafta, −1 = geçen hafta.
    @State private var weekOffset = 0
    /// Smart Mode text shown instead of the built report (cleared on week change / "Orijinal rapora dön").
    @State private var polished: String? = nil
    @State private var busy = false
    @State private var smartStatus: String? = nil
    /// Smart Mode on + key stored (checked on appear: the Keychain is not queried on every render).
    @State private var smartReady = false

    init() {}

    var body: some View {
        // Read the store here (not only inside the TimelineView closure) so Observation re-renders on every change.
        let items = store.items
        let projects = store.projects
        let settings = store.settings
        TimelineView(.everyMinute) { context in
            content(now: context.date, items: items, projects: projects, settings: settings)
        }
        .navigationTitle("Haftalık rapor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            smartReady = SmartModeClient.shared.isReady(store.settings)
        }
        .onChange(of: weekOffset) { _, _ in
            polished = nil
            smartStatus = nil
        }
    }

    // MARK: - Layout

    private func content(now: Date, items: [Item], projects: [Project], settings: AppSettings) -> some View {
        let report = WeeklyReportBuilder.build(items: items, projects: projects, now: now, weekOffset: weekOffset,
                                               calendar: AppTime.calendar)
        let original = WeeklyReportBuilder.text(report, userName: settings.userName)
        let shown = polished ?? original
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Hafta", selection: $weekOffset) {
                    Text("Bu hafta").tag(0)
                    Text("Geçen hafta").tag(-1)
                }
                .pickerStyle(.segmented)
                header(report)
                if report.isEmpty {
                    EmptyStateView(title: "Raporlanacak kayıt yok",
                                   message: emptyMessage,
                                   systemImage: "doc.text")
                } else {
                    reportCard(shown)
                    actions(shown: shown, original: original, rangeTitle: report.rangeTitle, settings: settings)
                }
            }
            .padding(Metrics.padding)
        }
        .background(Color.asistBackground)
    }

    private func header(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.rangeTitle)
                .font(.title3.weight(.semibold))
            Text(report.totals.summaryLine)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func reportCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if polished != nil {
                Label("Akıllı Mod ile düzenlendi", systemImage: Symbol.smartMode)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.purple)
            }
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Metrics.padding)
        .background(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous).fill(Color.asistCard))
    }

    private func actions(shown: String, original: String, rangeTitle: String, settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            ShareLink(item: shown, subject: Text("Haftalık durum · " + rangeTitle)) {
                Label("Paylaş (e-posta, WhatsApp…)", systemImage: Symbol.export)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button {
                copy(shown)
            } label: {
                Label("Kopyala", systemImage: "doc.on.doc")
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
            if smartReady {
                smartControls(original: original, settings: settings)
            }
        }
    }

    @ViewBuilder
    private func smartControls(original: String, settings: AppSettings) -> some View {
        if polished != nil {
            Button {
                polished = nil
                smartStatus = nil
            } label: {
                Label("Orijinal rapora dön", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Color.purple, filled: false))
        } else {
            Button {
                polish(original, settings: settings)
            } label: {
                HStack(spacing: 10) {
                    if busy {
                        ProgressView()
                    }
                    Label(polishTitle, systemImage: Symbol.smartMode)
                }
            }
            .buttonStyle(PrimaryButtonStyle(tint: Color.purple, filled: false))
            .disabled(busy)
        }
        if let status = smartStatus {
            Text(status)
                .font(.footnote)
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("Akıllı Mod rapor metnini (iş başlıkları, kişi ve proje adları) Anthropic'e gönderir.")
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Texts

    private var emptyMessage: String {
        weekOffset == 0
            ? "Bu hafta tamamlanan, geciken ya da açık iş bulunmuyor."
            : "Geçen hafta tamamlanan, geciken ya da açık iş bulunmuyor."
    }

    private var polishTitle: String {
        busy ? "Düzenleniyor…" : "Akıllı Mod ile düzenle"
    }

    // MARK: - Actions

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        toasts.show("Rapor kopyalandı")
        Haptics.selection()
    }

    /// Sends only the report text and the "Hitap" name (SmartModeClient.polishReport). A result that arrives after
    /// the week was switched is dropped; failures keep the built report and say why.
    private func polish(_ text: String, settings: AppSettings) {
        guard !busy else { return }
        busy = true
        smartStatus = nil
        let requestedWeek = weekOffset
        Task { @MainActor in
            let result = await SmartModeClient.shared.polishReport(text, settings: settings)
            busy = false
            guard requestedWeek == weekOffset else { return }
            switch result {
            case .success(let message):
                polished = message
                smartStatus = nil
                Haptics.success()
            case .failure(let error):
                smartStatus = error.userMessage
                Haptics.warning()
            }
        }
    }
}
