// Revision 4 (07 §8, F5): "Kişiler" — people and firms collected from the records' Kişi / Firma field
// (PeopleBoard), what you wait from each of them, and a one-tap combined Takip reminder message per row.
import SwiftUI
import AsistCore

/// Texts shared by the Kişiler screens.
@MainActor
enum PeopleRowText {
    /// "2 bekleniyor · 1 geciken · 3 iş" (only non-zero parts; the overdue part red), else "Açık iş yok".
    static func counts(_ summary: PersonSummary) -> Text {
        var parts: [Text] = []
        if !summary.followUps.isEmpty {
            let waiting: Text = Text(verbatim: String(summary.followUps.count) + " bekleniyor")
                .foregroundColor(Color.secondary)
            parts.append(waiting)
        }
        if summary.overdueFollowUps > 0 {
            let overdue: Text = Text(verbatim: String(summary.overdueFollowUps) + " geciken")
                .foregroundColor(Color.asistOverdue)
            parts.append(overdue)
        }
        if !summary.openItems.isEmpty {
            let open: Text = Text(verbatim: String(summary.openItems.count) + " iş")
                .foregroundColor(Color.secondary)
            parts.append(open)
        }
        guard var result = parts.first else {
            return Text(verbatim: "Açık iş yok").foregroundColor(Color.secondary)
        }
        for part in parts.dropFirst() {
            result = result + Text(verbatim: " · ").foregroundColor(Color.secondary) + part
        }
        return result
    }

    /// "bugün" / "dün" / "3 gün önce" (past days only; TurkishDateFormatter.relativePhrase is future-only).
    static func daysAgo(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = ItemRowText.dayDistance(from: date, to: now, calendar: calendar)
        if days <= 0 { return "bugün" }
        if days == 1 { return "dün" }
        return String(days) + " gün önce"
    }

    /// "Son hareket: dün"
    static func lastActivity(_ date: Date?, now: Date, calendar: Calendar) -> String? {
        guard let date = date else { return nil }
        return "Son hareket: " + daysAgo(date, now: now, calendar: calendar)
    }

    /// "27 Eylül"
    static func dayMonth(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        let months = TurkishDateFormatter.months
        let month = months[min(months.count - 1, max(0, (parts.month ?? 1) - 1))]
        return String(parts.day ?? 1) + " " + month
    }

    /// The combined Takip message; the name is used in the greeting only when it looks like a person (not a firm).
    static func message(for summary: PersonSummary, items: [Item], userName: String, now: Date,
                        calendar: Calendar) -> String {
        let looksLikePerson = FollowUpMessageSheet.looksLikePerson(summary.displayName, allItems: items)
        let greetingName: String? = looksLikePerson ? summary.displayName : nil
        return PeopleBoard.reminderMessage(for: summary, greetingName: greetingName, userName: userName, now: now,
                                           calendar: calendar)
    }
}

@MainActor
struct PeopleView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var query = ""

    init() {}

    var body: some View {
        // Read the store here (not only inside the TimelineView closure) so Observation re-renders on every change.
        let items = store.items
        let userName = store.settings.userName
        TimelineView(.everyMinute) { context in
            list(now: context.date, items: items, userName: userName)
        }
        .navigationTitle("Kişiler")
        .searchable(text: $query, prompt: "Kişi veya firma ara")
    }

    private func list(now: Date, items: [Item], userName: String) -> some View {
        let people = PeopleBoard.build(items: items, now: now, calendar: AppTime.calendar)
        let visible = PeopleView.filter(people, query: query)
        return List {
            if people.isEmpty {
                Section {
                    EmptyStateView(title: "Henüz kişi yok",
                                   message: "Kayıtlarda kişi ya da firma adı geçince burada toplanır. Örn: “Mehmet cumaya kadar listeyi gönderecek”.",
                                   systemImage: "person.2")
                }
                .listRowBackground(Color.clear)
            } else if visible.isEmpty {
                Section {
                    EmptyStateView(title: "Sonuç bulunamadı", message: "Farklı bir ad dene.",
                                   systemImage: "magnifyingglass")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(visible) { summary in
                        row(summary, now: now, items: items, userName: userName)
                    }
                } footer: {
                    Text("Kişi / Firma alanı dolu kayıtlardan toplanır. Kâğıt uçak simgesi, bekleyen tüm konuları tek mesajla sorar.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Main area = Button (not a NavigationLink) so the trailing ShareLink stays separately tappable.
    private func row(_ summary: PersonSummary, now: Date, items: [Item], userName: String) -> some View {
        let calendar = AppTime.calendar
        let key = summary.key
        let hasFollowUps = !summary.followUps.isEmpty
        let lastText = PeopleRowText.lastActivity(summary.lastActivity, now: now, calendar: calendar)
        return HStack(spacing: 4) {
            Button {
                router.push(.person(key))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: Symbol.person)
                        .font(.body)
                        .foregroundStyle(summary.overdueFollowUps > 0 ? Color.asistOverdue : Color.asistFollowUp)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.displayName)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                            .lineLimit(2)
                        PeopleRowText.counts(summary)
                            .font(.subheadline)
                            .monospacedDigit()
                        if let lastText = lastText {
                            Text(lastText)
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: Metrics.rowMinHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Kişinin işlerini açar")
            if hasFollowUps {
                ShareLink(item: PeopleRowText.message(for: summary, items: items, userName: userName, now: now,
                                                      calendar: calendar)) {
                    Image(systemName: Symbol.message)
                        .font(.title3)
                        .foregroundStyle(Color.asistFollowUp)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Hatırlatma mesajı gönder")
            }
        }
    }

    /// Every query token must appear in the key or the folded display name.
    private static func filter(_ people: [PersonSummary], query: String) -> [PersonSummary] {
        let key = TurkishText.searchKey(query)
        guard !key.isEmpty else { return people }
        let tokens = key.split(separator: " ").map { String($0) }
        return people.filter { (summary: PersonSummary) -> Bool in
            let haystack = summary.key + " " + TurkishText.searchKey(summary.displayName)
            for token in tokens where !haystack.contains(token) {
                return false
            }
            return true
        }
    }
}
