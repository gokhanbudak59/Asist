// WP9 (04 §5.3, signature frozen; 03 §4.3, §7.1, §7.5, §7.9): one record row.
// 4 pt status stripe + kind symbol + title (+ PriorityBadge / "Emin değilim") + second line
// (time text · project · person + repeat/event/pre-alert/checklist symbols) + 44 pt completion circle (28 pt visual).
// ≥ 64 pt tall; VoiceOver actions Yaptım / Ertele / Sil. Callers wrap it in NavigationLink(value: Route.item(id)).
import SwiftUI
import UIKit
import AsistCore

struct ItemRow: View {
    let item: Item
    let projectName: String?
    let now: Date
    let onToggleDone: () -> Void          // 44 pt circle (28 pt visual)

    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checking = false

    /// Explicit (frozen §5.3 signature) so private @State storage never narrows the initializer's access level.
    init(item: Item, projectName: String?, now: Date, onToggleDone: @escaping () -> Void) {
        self.item = item
        self.projectName = projectName
        self.now = now
        self.onToggleDone = onToggleDone
    }

    var body: some View {
        let calendar = AppTime.calendar
        let color = item.statusColor(now: now, calendar: calendar)
        let overdue = item.isOverdue(at: now, calendar: calendar)
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: kindSymbol)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    titleLine
                    detailText(ItemRowText.detailLine(for: item, projectName: projectName, now: now,
                                                      calendar: calendar))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(overdue ? Color.asistOverdue : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, Metrics.stripeWidth + 10)
            .background(alignment: .leading) {
                // Background is proposed the row's full height, so the stripe spans it (a plain HStack child would not).
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: Metrics.stripeWidth)
                    .padding(.vertical, 6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text(doneLabel)) {
                onToggleDone()
            }
            .accessibilityAction(named: Text("Ertele")) {
                ItemQuickActions.snooze(item.id, option: .hour1, store: store, toasts: toasts, router: router)
            }
            .accessibilityAction(named: Text("Sil")) {
                ItemQuickActions.delete(item.id, store: store, toasts: toasts)
            }
            if showsCompletion {
                completionButton
            }
        }
        .frame(minHeight: Metrics.rowMinHeight)
    }

    // MARK: - Parts

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.title.isEmpty ? "Başlıksız" : item.title)
                .font(item.priority == .critical ? Font.body.weight(.semibold) : Font.body.weight(.medium))
                .strikethrough(looksDone)
                .foregroundStyle(looksDone ? Color.secondary : Color.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            PriorityBadge(priority: item.priority)
            if item.needsReview && item.isOpen {
                Text("Emin değilim")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.asistReview))
            }
        }
    }

    private var completionButton: some View {
        Button {
            tapCompletion()
        } label: {
            Image(systemName: looksDone ? Symbol.taskDone : Symbol.task)
                .font(.system(size: Metrics.completionVisual, weight: .regular))
                .foregroundStyle(looksDone ? Color.asistDone : Color.secondary)
                .frame(width: Metrics.completionHitArea, height: Metrics.completionHitArea)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(item.status == .done ? "Yeniden aç" : doneLabel)
    }

    private func detailText(_ line: String) -> Text {
        var text = Text(line)
        if item.recurrence != nil {
            text = text + Text(verbatim: "  ") + Text(Image(systemName: Symbol.recurrence))
        }
        if item.isEvent {
            text = text + Text(verbatim: "  ") + Text(Image(systemName: Symbol.event))
        }
        if !item.leadTimesMinutes.isEmpty {
            text = text + Text(verbatim: "  ") + Text(Image(systemName: Symbol.preAlert))
        }
        if !item.checklist.isEmpty {
            let done = item.checklist.filter { $0.done }.count
            let progress: String = " " + String(done) + "/" + String(item.checklist.count)
            text = text + Text(verbatim: "  ") + Text(Image(systemName: Symbol.checklist))
            text = text + Text(verbatim: progress)
        }
        return text
    }

    // MARK: - Behaviour

    private var looksDone: Bool { item.status == .done || checking }

    /// Notes have no completion circle (they are archived from the detail screen); deleted rows neither.
    private var showsCompletion: Bool {
        item.status != .deleted && !(item.kind == .note && item.status == .open)
    }

    private var doneLabel: String { item.kind == .waiting ? "Geldi" : "Yaptım" }

    private var kindSymbol: String {
        if item.isEvent { return Symbol.event }
        if item.status == .done { return Symbol.taskDone }
        return item.kind.symbol
    }

    /// 03 §4.3: the circle fills and the title is struck through, then after 0.4 s the caller's action runs
    /// (the row leaves the list). Reopening a done row runs immediately.
    @MainActor
    private func tapCompletion() {
        guard !checking else { return }
        if item.status != .open || reduceMotion {
            onToggleDone()
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            checking = true
        }
        let action = onToggleDone
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            action()
            checking = false
        }
    }
}

/// Text rules for row / hero second lines (03 §7.11–7.12 "Göreli zaman"; 05b F8, F13, F14).
enum ItemRowText {
    /// "Bugün 15:00 · 2 saat gecikti", "14:00 · 2 saat sonra", "Gün içinde", "Yarın 09:00", "Salı",
    /// "Dün · 2 gündür bekliyor", "Zamanı belirsiz", "Tamamlandı · Dün 17:10".
    static func timeLine(for item: Item, now: Date, calendar: Calendar) -> String {
        if item.status == .done {
            if let completed = item.completedAt {
                return "Tamamlandı · " + TurkishDateFormatter.shortDateTime(completed, now: now, calendar: calendar,
                                                                           includeTime: true)
            }
            return "Tamamlandı"
        }
        if item.status == .deleted {
            return "Silindi"
        }
        if item.kind == .note {
            return TurkishDateFormatter.shortDateTime(item.createdAt, now: now, calendar: calendar, includeTime: true)
        }
        guard let anchor = item.anchorDate else {
            return "Zamanı belirsiz"
        }
        let showsClock = item.hasTime || item.snoozedUntil != nil || item.kind == .reminder
        if item.isOverdue(at: now, calendar: calendar) {
            if item.kind == .waiting || !showsClock {
                let days = max(1, dayDistance(from: anchor, to: now, calendar: calendar))
                let day = TurkishDateFormatter.shortDateTime(anchor, now: now, calendar: calendar, includeTime: false)
                return day + " · " + String(days) + " gündür bekliyor"
            }
            let when = TurkishDateFormatter.shortDateTime(anchor, now: now, calendar: calendar, includeTime: true)
            return when + " · " + TurkishDateFormatter.relativeShort(to: anchor, now: now, calendar: calendar)
        }
        if calendar.isDate(anchor, inSameDayAs: now) {
            if !showsClock {
                return item.kind == .waiting ? "Bugün" : "Gün içinde"
            }
            let time = TurkishDateFormatter.time(anchor, calendar: calendar)
            if anchor <= now {
                return item.isEvent ? time + " · başladı" : time
            }
            return time + " · " + TurkishDateFormatter.relativeShort(to: anchor, now: now, calendar: calendar)
        }
        return TurkishDateFormatter.shortDateTime(anchor, now: now, calendar: calendar, includeTime: showsClock)
    }

    /// timeLine · project · person (empty parts skipped).
    static func detailLine(for item: Item, projectName: String?, now: Date, calendar: Calendar) -> String {
        var parts: [String] = [timeLine(for: item, now: now, calendar: calendar)]
        if let projectName = projectName {
            let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        if let person = item.person {
            let trimmed = person.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        return parts.joined(separator: " · ")
    }

    /// Calendar days between the two instants' days (b − a).
    static func dayDistance(from a: Date, to b: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: a)
        let end = calendar.startOfDay(for: b)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
