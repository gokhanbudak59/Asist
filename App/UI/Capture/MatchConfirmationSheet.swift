// WP9 (04 §5.2; 03 §5.10, §7.12 tts.confirm_*): confirmation of a voice complete / cancel / snooze command.
// Single match: "“X” tamamlandı mı?" / "“X” silinsin mi?" (red) / "“X” Perşembe 10:00'a ertelensin mi?" with
// [Evet …][Hayır] (56 pt). Several: "Hangisi?" with 64 pt rows; deleting is always confirmed once more.
// CommandExecutor.apply persists and shows the toast (+ undo) and haptic.
import SwiftUI
import AsistCore

struct MatchConfirmationSheet: View {
    let proposal: MatchProposal

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var pendingDelete: Item?
    @State private var showDeleteConfirm = false

    /// Explicit so the private @State storage never narrows the initializer's access level (SheetHost calls it).
    init(proposal: MatchProposal) {
        self.proposal = proposal
    }

    var body: some View {
        let candidates = openCandidates
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if candidates.isEmpty {
                        EmptyStateView(title: "Kayıt bulunamadı",
                                       message: "Bu kayıt artık açık değil.",
                                       systemImage: "questionmark.circle")
                    } else if candidates.count == 1, let item = candidates.first {
                        singleContent(item)
                    } else {
                        multipleContent(candidates)
                    }
                }
                .padding(Metrics.padding)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        close()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Silinsin mi?", isPresented: $showDeleteConfirm, titleVisibility: .visible,
                            presenting: pendingDelete) { item in
            Button("Sil", role: .destructive) {
                apply(item.id)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { item in
            Text("“" + item.title + "” silinsin mi?")
        }
    }

    // MARK: - Content

    private func singleContent(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question(for: item))
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            candidateSummary(item)
            HStack(spacing: Metrics.cardSpacing) {
                Button {
                    close()
                } label: {
                    Text("Hayır")
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                Button {
                    apply(item.id)
                } label: {
                    Text(confirmTitle)
                }
                .buttonStyle(PrimaryButtonStyle(tint: confirmTint))
            }
        }
    }

    private func multipleContent(_ candidates: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hangisi?")
                .font(.title2.weight(.semibold))
            Text(multipleHint)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(candidates) { item in
                Button {
                    choose(item)
                } label: {
                    candidateSummary(item)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func candidateSummary(_ item: Item) -> some View {
        let calendar = AppTime.calendar
        let now = Date()
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.isEvent ? Symbol.event : item.kind.symbol)
                .font(.title3)
                .foregroundStyle(item.statusColor(now: now, calendar: calendar))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title.isEmpty ? "Başlıksız" : item.title)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    PriorityBadge(priority: item.priority)
                }
                Text(ItemRowText.detailLine(for: item, projectName: store.projectName(for: item), now: now,
                                            calendar: calendar))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: Metrics.rowMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(Color.asistCard)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Texts

    private var openCandidates: [Item] {
        var result: [Item] = []
        for id in proposal.candidates {
            if let item = store.item(id), item.isOpen {
                result.append(item)
            }
        }
        return result
    }

    private var navigationTitle: String {
        switch proposal.command.type {
        case .complete: return "Tamamla"
        case .cancel: return "Sil"
        case .snooze: return "Ertele"
        case .query: return "Kayıt"
        }
    }

    private var multipleHint: String {
        switch proposal.command.type {
        case .complete: return "Birden fazla kayıt buldum. Hangisini tamamlayalım?"
        case .cancel: return "Birden fazla kayıt buldum. Hangisini silelim?"
        case .snooze: return "Birden fazla kayıt buldum. Hangisini erteleyelim?"
        case .query: return "Birden fazla kayıt buldum."
        }
    }

    private var confirmTitle: String {
        switch proposal.command.type {
        case .complete: return "Evet, tamamlandı"
        case .cancel: return "Evet, sil"
        case .snooze: return "Evet, ertele"
        case .query: return "Evet"
        }
    }

    private var confirmTint: Color {
        switch proposal.command.type {
        case .complete: return Color.asistDone
        case .cancel: return Color.asistOverdue
        case .snooze: return Color.asistToday
        case .query: return Color.asistAccent
        }
    }

    private func question(for item: Item) -> String {
        let title = "“" + (item.title.isEmpty ? "Bu kayıt" : item.title) + "”"
        switch proposal.command.type {
        case .complete:
            return item.kind == .waiting ? title + " geldi mi?" : title + " tamamlandı mı?"
        case .cancel:
            return title + " silinsin mi?"
        case .snooze:
            return title + " " + ClockDative.phrase(snoozeTarget, now: Date(), calendar: AppTime.calendar,
                                                     includeToday: true) + " ertelensin mi?"
        case .query:
            return title + " bu mu?"
        }
    }

    /// Display only (CommandExecutor computes the real target): command.date ?? now + snoozeMinutes (default 60).
    private var snoozeTarget: Date {
        if let date = proposal.command.date {
            return date
        }
        let minutes = max(1, proposal.command.snoozeMinutes ?? 60)
        return AsistCalendar.ceilToMinute(Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    // MARK: - Actions

    @MainActor
    private func choose(_ item: Item) {
        if proposal.command.type == .cancel {
            pendingDelete = item
            showDeleteConfirm = true
        } else {
            apply(item.id)
        }
    }

    @MainActor
    private func apply(_ id: UUID) {
        AppEnvironment.shared.commands.apply(proposal, itemID: id)
        close()
    }

    @MainActor
    private func close() {
        if case .match(let shown)? = router.sheet, shown.id == proposal.id {
            router.dismissSheet()
        }
    }
}
