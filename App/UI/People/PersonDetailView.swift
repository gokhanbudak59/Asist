// Revision 4 (07 §8.1, §8.5, F5): one person / firm — counts, the combined Takip reminder message (editable, share,
// copy), "Yeniden sor" for all of their open Takip items at once, and BEKLEDİKLERİM / AÇIK İŞLER / GEÇMİŞ rows
// (ListItemLink, so swipe Yaptım / Sil / Ertele / Düzenle work here too).
import SwiftUI
import UIKit
import AsistCore

@MainActor
struct PersonDetailView: View {
    let personKey: String

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    /// The editable message; regenerated from the records only while the user has not edited it.
    @State private var message = ""
    /// The last generated message (edited = message differs from it).
    @State private var generated = ""
    @State private var loaded = false
    @State private var snoozeTarget: Item? = nil
    @State private var showSnoozeDialog = false

    /// Explicit: private @State storage must not narrow the memberwise initializer's access (RouteDestination).
    init(personKey: String) {
        self.personKey = personKey
    }

    var body: some View {
        // Read the store here (not only inside the TimelineView closure) so Observation re-renders on every change.
        let items = store.items
        let userName = store.settings.userName
        let summary = PeopleBoard.summary(forKey: personKey, items: items, now: Date(), calendar: AppTime.calendar)
        let fresh = freshMessage(summary, items: items, userName: userName)
        TimelineView(.everyMinute) { context in
            content(now: context.date, items: items)
        }
        .navigationTitle(summary?.displayName ?? "Kişi")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshMessage(fresh)
        }
        .onChange(of: fresh) { _, newValue in
            refreshMessage(newValue)
        }
        .confirmationDialog("Ertele", isPresented: $showSnoozeDialog, titleVisibility: .visible,
                            presenting: snoozeTarget) { item in
            // Buttons directly inside ForEach (dialogs do not reliably unwrap custom container views).
            ForEach(SnoozeOption.available(now: Date(), settings: store.settings, calendar: AppTime.calendar)) { option in
                Button(option.menuTitle(now: Date(), settings: store.settings, calendar: AppTime.calendar)) {
                    ItemQuickActions.snooze(item.id, option: option, store: store, toasts: toasts, router: router)
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { item in
            Text(item.title)
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(now: Date, items: [Item]) -> some View {
        if let summary = PeopleBoard.summary(forKey: personKey, items: items, now: now, calendar: AppTime.calendar) {
            detail(summary, now: now)
        } else {
            EmptyStateView(title: "Kişi bulunamadı", message: "Bu kişiye bağlı kayıt kalmamış.",
                           systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private func detail(_ summary: PersonSummary, now: Date) -> some View {
        let names = ListItemSearch.projectNames(store.projects)
        let hasFollowUps = !summary.followUps.isEmpty
        return List {
            Section {
                header(summary, now: now)
            }
            if hasFollowUps {
                messageSection(summary)
                askAgainSection(summary)
                Section {
                    ForEach(summary.followUps) { item in
                        link(item, now: now, names: names)
                    }
                } header: {
                    SectionHeader(title: "BEKLEDİKLERİM", count: summary.followUps.count, color: Color.asistFollowUp)
                }
            }
            if !summary.openItems.isEmpty {
                Section {
                    ForEach(summary.openItems) { item in
                        link(item, now: now, names: names)
                    }
                } header: {
                    SectionHeader(title: "AÇIK İŞLER", count: summary.openItems.count)
                }
            }
            if !summary.recentDone.isEmpty {
                Section {
                    ForEach(summary.recentDone) { item in
                        link(item, now: now, names: names)
                    }
                } header: {
                    SectionHeader(title: "GEÇMİŞ")
                } footer: {
                    Text("Son 60 günde tamamlananlar.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func header(_ summary: PersonSummary, now: Date) -> some View {
        let lastLine = lastActivityLine(summary.lastActivity, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            Text(summary.displayName)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            PeopleRowText.counts(summary)
                .font(.subheadline)
                .monospacedDigit()
            if let lastLine = lastLine {
                Text(lastLine)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "Son hareket: 27 Eylül · 3 gün önce"
    private func lastActivityLine(_ date: Date?, now: Date) -> String? {
        guard let date = date else { return nil }
        let calendar = AppTime.calendar
        let day: String = PeopleRowText.dayMonth(date, calendar: calendar)
        let ago: String = PeopleRowText.daysAgo(date, now: now, calendar: calendar)
        return "Son hareket: " + day + " · " + ago
    }

    private func messageSection(_ summary: PersonSummary) -> some View {
        let count = summary.followUps.count
        let shareTitle: String = "Hatırlatma mesajı gönder (" + String(count) + " konu)"
        return Section {
            TextEditor(text: $message)
                .frame(minHeight: 140)
            ShareLink(item: message) {
                Label(shareTitle, systemImage: Symbol.message)
            }
            .buttonStyle(PrimaryButtonStyle(tint: Color.asistFollowUp))
            .listRowInsets(EdgeInsets(top: 8, leading: Metrics.padding, bottom: 8, trailing: Metrics.padding))
            Button {
                copyMessage()
            } label: {
                Label("Kopyala", systemImage: "doc.on.doc")
                    .frame(minHeight: 44)
            }
        } header: {
            SectionHeader(title: "MESAJ")
        } footer: {
            Text("Göndermeden önce metni düzenleyebilirsin.")
        }
    }

    private func askAgainSection(_ summary: PersonSummary) -> some View {
        let ids = summary.followUps.map { (item: Item) -> UUID in item.id }
        return Section {
            ChipRow {
                Chip(title: "Yarın") {
                    askAgain(workdays: 1, ids: ids)
                }
                Chip(title: "2 gün sonra") {
                    askAgain(workdays: 2, ids: ids)
                }
                Chip(title: "Pazartesi") {
                    askAgainMonday(ids: ids)
                }
            }
            .buttonStyle(.borderless)
        } header: {
            SectionHeader(title: "YENİDEN SOR")
        } footer: {
            Text("Mesajı gönderdikten sonra seç; bu kişideki takipler o zamana kadar ertelenir (zaten daha ileri tarihli olanlar değişmez).")
        }
    }

    private func link(_ item: Item, now: Date, names: [UUID: String]) -> some View {
        let projectName = item.projectID.flatMap { (id: UUID) -> String? in names[id] }
        return ListItemLink(item: item, projectName: projectName, now: now, onSnooze: { target in
            snoozeTarget = target
            showSnoozeDialog = true
        })
    }

    // MARK: - Message

    private func freshMessage(_ summary: PersonSummary?, items: [Item], userName: String) -> String {
        guard let summary = summary else { return "" }
        return PeopleRowText.message(for: summary, items: items, userName: userName, now: Date(),
                                     calendar: AppTime.calendar)
    }

    /// Loads the generated text once, then follows the records (a follow-up done / added) only while the user has
    /// not edited the message.
    private func refreshMessage(_ fresh: String) {
        if !loaded || message == generated {
            message = fresh
        }
        generated = fresh
        loaded = true
    }

    private func copyMessage() {
        UIPasteboard.general.string = message
        toasts.show("Mesaj kopyalandı")
        Haptics.selection()
    }

    // MARK: - Yeniden sor (all open Takip items of this person)

    private func askAgain(workdays: Int, ids: [UUID]) {
        let target = NagPlanner.followUpAsk(after: Date(), workdays: workdays, settings: store.settings,
                                            calendar: AppTime.calendar)
        snoozeAll(ids, until: target)
    }

    private func askAgainMonday(ids: [UUID]) {
        let target = NagPlanner.nextMonday(now: Date(), settings: store.settings, calendar: AppTime.calendar)
        snoozeAll(ids, until: target)
    }

    /// One toast "3 takip ertelendi · Yarın 16:00" with a merged undo, one haptic. Items already anchored at or after
    /// the chosen time (a later deadline or snooze) are left unchanged — "ertele" never pulls a deadline earlier.
    private func snoozeAll(_ ids: [UUID], until target: Date) {
        let now = Date()
        let whole = AsistCalendar.floorToMinute(target)
        guard whole > now else {
            toasts.show("Geçmiş bir zamana ertelenemez.")
            Haptics.warning()
            return
        }
        var before: [Item] = []
        var skipped = 0
        for id in ids {
            guard let item = store.item(id), item.isOpen else { continue }
            if let anchor = item.anchorDate, anchor >= whole {
                skipped += 1
                continue
            }
            if let token = store.snooze(id, until: whole, at: now) {
                before.append(contentsOf: token.before)
            }
        }
        guard !before.isEmpty else {
            if skipped > 0 {
                toasts.show(String(skipped) + " takip zaten daha ileri tarihli")
                Haptics.selection()
            } else {
                DetailItemActions.reportNil("takipleri ertele", store: store, toasts: toasts)
            }
            return
        }
        let label = TurkishDateFormatter.shortDateTime(whole, now: now, calendar: AppTime.calendar, includeTime: true)
        let undo = UndoToken(label: "Takipler ertelendi", before: before)
        var text = String(before.count) + " takip ertelendi · " + label
        if skipped > 0 {
            text += " · " + String(skipped) + " zaten daha ileri"
        }
        toasts.show(text, undo: undo)
        Haptics.success()
    }
}
