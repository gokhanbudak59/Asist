// WP10 — Tarih/saat seçici (04 §5.2): snooze → store.snooze; due → dueDate + hasTime + resetNagState.
import SwiftUI
import AsistCore

@MainActor
struct DateTimePickerSheet: View {
    let request: DatePickerRequest

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @State private var day = Date()
    @State private var time = Date()
    @State private var loaded = false

    /// Explicit: private @State storage must not narrow the memberwise initializer's access (SheetHost.swift).
    init(request: DatePickerRequest) {
        self.request = request
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(request.purpose == .snooze ? "Ertele" : "Zaman seç")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Vazgeç") {
                            router.dismissSheet()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kaydet") {
                            save()
                        }
                        .disabled(!canSave)
                    }
                }
        }
        .presentationDetents([.large])
        .onAppear {
            load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let item = store.item(request.itemID), item.status != .deleted {
            Form {
                Section {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                Section {
                    DatePicker("Gün", selection: $day, in: minimumDay..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                Section {
                    DatePicker("Saat", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    ChipRow {
                        ForEach(quickTimes, id: \.self) { clock in
                            Chip(title: clock.display) {
                                setTime(clock)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                } header: {
                    SectionHeader(title: "SAAT")
                }
                Section {
                    Label(summaryText, systemImage: request.purpose == .snooze ? Symbol.snooze : Symbol.event)
                        .font(.body.weight(.medium))
                    if isPast {
                        Text(request.purpose == .snooze
                             ? "Geçmiş bir zamana ertelenemez."
                             : "Geçmiş bir zaman seçtin; kayıt hemen geciken olarak görünür.")
                            .font(.footnote)
                            .foregroundStyle(request.purpose == .snooze ? Color.asistOverdue : Color.secondary)
                    }
                }
            }
        } else {
            EmptyStateView(title: "Kayıt bulunamadı",
                           message: "Bu kayıt silinmiş ya da artık mevcut değil.",
                           systemImage: "questionmark.folder")
        }
    }

    // MARK: - Values

    private var minimumDay: Date {
        let calendar = AppTime.calendar
        let today = calendar.startOfDay(for: Date())
        if request.purpose == .snooze {
            return today
        }
        return AsistCalendar.addingDays(-3650, to: today, calendar: calendar)
    }

    private var combined: Date {
        let calendar = AppTime.calendar
        let comps = calendar.dateComponents([.hour, .minute], from: time)
        let clock = ClockTime(comps.hour ?? 9, comps.minute ?? 0)
        return AsistCalendar.date(on: day, at: clock, calendar: calendar)
    }

    private var isPast: Bool {
        combined <= Date()
    }

    private var canSave: Bool {
        guard let item = store.item(request.itemID), item.status != .deleted else { return false }
        if request.purpose == .snooze {
            return item.isOpen && !isPast
        }
        return item.isOpen
    }

    private var summaryText: String {
        let calendar = AppTime.calendar
        let target = combined
        let now = Date()
        let phrase = TurkishDateFormatter.datePhrase(target, now: now, calendar: calendar)
            + " · " + TurkishDateFormatter.time(target, calendar: calendar)
        if target > now {
            return phrase + "  " + TurkishDateFormatter.relativePhrase(to: target, now: now, calendar: calendar)
        }
        return phrase
    }

    private var quickTimes: [ClockTime] {
        let settings = store.settings
        let candidates: [ClockTime] = [settings.sabah, settings.ogle, settings.ogledenSonra,
                                       settings.aksamustu, settings.aksam]
        var seen = Set<ClockTime>()
        var result: [ClockTime] = []
        for clock in candidates.sorted() where !seen.contains(clock) {
            seen.insert(clock)
            result.append(clock)
        }
        return result
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        let now = Date()
        var base = defaultTarget(now: now)
        if let item = store.item(request.itemID) {
            switch request.purpose {
            case .snooze:
                if let snoozed = item.snoozedUntil, snoozed > now {
                    base = snoozed
                }
            case .due:
                if let due = item.dueDate {
                    base = due
                }
            }
        }
        day = base
        time = base
    }

    /// Next full hour after now + 1 h ("10:20" → "11:00"... "11:20" → "12:00").
    private func defaultTarget(now: Date) -> Date {
        let calendar = AppTime.calendar
        let later = now.addingTimeInterval(60 * 60)
        let hour = calendar.component(.hour, from: later)
        return AsistCalendar.date(on: later, at: ClockTime(hour, 0), calendar: calendar)
    }

    private func setTime(_ clock: ClockTime) {
        time = AsistCalendar.date(on: time, at: clock, calendar: AppTime.calendar)
        Haptics.selection()
    }

    private func save() {
        let target = AsistCalendar.floorToMinute(combined)
        let now = Date()
        switch request.purpose {
        case .snooze:
            guard target > now else {
                toasts.show("Geçmiş bir zamana ertelenemez.")
                Haptics.warning()
                return
            }
            DetailItemActions.snooze(request.itemID, until: target, store: store, toasts: toasts)
        case .due:
            let token = store.update(request.itemID, event: .rescheduled, { edited in
                edited.dueDate = target
                edited.hasTime = true
                edited.resetNagState()
            })
            if let token = token {
                let label = TurkishDateFormatter.shortDateTime(target, now: now, calendar: AppTime.calendar,
                                                               includeTime: true)
                toasts.show("Zaman güncellendi · " + label, undo: token)
                Haptics.success()
            } else {
                DetailItemActions.reportNil("zaman", store: store, toasts: toasts)
            }
        }
        router.dismissSheet()
    }
}
