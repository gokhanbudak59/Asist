// WP10 — Gün Sonu (03 §3.10/§4.10 basit liste sürümü; 05b B6/F1/F6). Kart kart akış v1.1'de.
import SwiftUI
import AsistCore

@MainActor
struct EndOfDayView: View {
    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .navigationTitle("Gün Sonu")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Layout

    private func content(now: Date) -> some View {
        let calendar = AppTime.calendar
        let candidates = AgendaBuilder.endOfDayCandidates(items: store.items, now: now, calendar: calendar)
        let evening = laterToday(now: now, calendar: calendar, excluding: candidates)
        let names = ListItemSearch.projectNames(store.projects)
        let headline: String = candidates.isEmpty
            ? "Açık iş kalmadı"
            : "Gün Sonu — " + String(candidates.count) + " iş açık"
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.title3.weight(.semibold))
                    Text("Taşınacağı gün: " + targetDayText(now: now, calendar: calendar))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                .padding(.vertical, 4)
            }
            if candidates.isEmpty {
                Section {
                    EmptyStateView(title: "Gün kapandı", message: "Yarın sabah brifingde görüşürüz.",
                                   systemImage: Symbol.endOfDay)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(candidates) { item in
                        candidateRow(item, now: now, projectName: item.projectID.flatMap { names[$0] })
                    }
                } header: {
                    SectionHeader(title: "AÇIK KALANLAR", count: candidates.count)
                } footer: {
                    Text("Notlar, etkinlikler ve tekrarlayan işler taşınmaz; tekrarlayanların sıradaki zamanı zaten planlı.")
                }
            }
            if !evening.isEmpty {
                Section {
                    ForEach(evening) { item in
                        ListItemLink(item: item, projectName: item.projectID.flatMap { names[$0] }, now: now)
                    }
                } header: {
                    SectionHeader(title: "BU AKŞAM", count: evening.count)
                } footer: {
                    Text("Saati henüz gelmediği için taşınmaz.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            moveAllBar(count: candidates.count)
        }
    }

    private func candidateRow(_ item: Item, now: Date, projectName: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemRow(item: item, projectName: projectName, now: now) {
                _ = DetailItemActions.markDone(item.id, store: store, toasts: toasts)
            }
            .buttonStyle(.borderless)
            if item.snoozeCount > 0 {
                Text(String(item.snoozeCount) + " kez ertelendi")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            HStack(spacing: Metrics.chipSpacing) {
                rowButton(item.kind == .waiting ? "✓ Geldi" : "✓ Yaptım", tint: Color.asistDone) {
                    _ = DetailItemActions.markDone(item.id, store: store, toasts: toasts)
                }
                rowButton("Sonraki iş günü", tint: Color.asistAccent) {
                    DetailItemActions.moveToNextWorkday(item.id, store: store, toasts: toasts)
                }
                rowButton("Sil", tint: Color.asistOverdue) {
                    DetailItemActions.delete(item.id, store: store, toasts: toasts)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func rowButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: Metrics.chipHeight)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
        }
    }

    private func moveAllBar(count: Int) -> some View {
        let title: String = count > 0
            ? "Sonraki iş gününe taşı (" + String(count) + ")"
            : "Sonraki iş gününe taşı"
        return Button {
            moveAll()
        } label: {
            Label(title, systemImage: "arrow.right.circle.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
        .padding(.horizontal, Metrics.padding)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Data

    /// Open timed items later today that the move leaves alone ("Bu akşam: 18:00 Ekmek al", 05b B6).
    private func laterToday(now: Date, calendar: Calendar, excluding candidates: [Item]) -> [Item] {
        var excluded = Set<UUID>()
        for item in candidates {
            excluded.insert(item.id)
        }
        var result: [Item] = []
        for item in store.items where item.isOpen && item.kind != .note && !excluded.contains(item.id) {
            guard let anchor = item.anchorDate else { continue }
            guard anchor > now, calendar.isDate(anchor, inSameDayAs: now) else { continue }
            guard item.hasTime || item.isEvent || item.snoozedUntil != nil else { continue }
            result.append(item)
        }
        return result.sorted(by: ListItemSearch.timeOrder)
    }

    private func targetDayText(now: Date, calendar: Calendar) -> String {
        let settings = store.settings
        let target: Date
        if settings.moveSkipsWeekend {
            target = AsistCalendar.addingWorkdays(1, to: now, workdays: settings.workdays, calendar: calendar)
        } else {
            target = AsistCalendar.addingDays(1, to: calendar.startOfDay(for: now), calendar: calendar)
        }
        return TurkishDateFormatter.datePhrase(target, now: now, calendar: calendar)
    }

    // MARK: - Actions

    private func moveAll() {
        guard let token = store.moveOpenItemsToTomorrow(now: Date()) else {
            DetailItemActions.reportNil("sonraki iş gününe taşı", store: store, toasts: toasts)
            return
        }
        let count = token.before.count
        let text = count > 0 ? String(count) + " iş sonraki iş gününe taşındı." : "Sonraki iş gününe taşındı."
        toasts.show(text, undo: token)
        Haptics.success()
    }
}
