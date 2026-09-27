// Revision 4 (07 §4, F1): the "Düzenle" sheet — the capture card's choices (gün, saat, öncelik, tür, proje, tekrar,
// kişi, etkinlik, ön uyarı) for an existing open record, opened by swiping a row, the hero card chip or
// asist://kayit/<uuid>?eylem=duzenle. The sheet edits a copy; one "Kaydet" = one store.update through the pure
// ItemEditRules (only the fields changed here are written onto the store's latest copy) = one "Geri Al".
// Nothing auto-saves: "Vazgeç" or swiping the sheet down discards the edits.
import SwiftUI
import UIKit
import AsistCore

@MainActor
struct ItemEditSheet: View {
    let itemID: UUID

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    /// The record as it was when the sheet opened (nil until loaded, or when it is missing / no longer open).
    @State private var original: Item? = nil
    /// Edited copy; the chips mutate it.
    @State private var draft = Item(kind: .task, title: "", createdAt: Date(timeIntervalSince1970: 0))
    @State private var loadAttempted = false
    @State private var foundClosed = false
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var pickedDate = Date()
    @State private var pickedTime = Date()
    /// Programmatic picker preloads must not count as a user choice.
    @State private var ignoreDateChange = false
    @State private var ignoreTimeChange = false
    @State private var personText = ""
    @FocusState private var focusedField: EditField?

    private enum EditField: Hashable {
        case title, person
    }

    private static let leadChoices: [Int] = [10, 15, 30, 60, 1440]
    private static let priorityChoices: [Priority] = [.low, .normal, .high, .critical]

    /// Explicit: private @State storage must not narrow the memberwise initializer's access level (SheetHost).
    init(itemID: UUID) {
        self.itemID = itemID
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Düzenle")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancelTitle) {
                            cancel()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if original != nil {
                            Button("Kaydet") {
                                save()
                            }
                            .disabled(titleIsEmpty)
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            load()
        }
        .onChange(of: draft.title) { _, newValue in
            flattenTitle(newValue)
        }
        .onChange(of: pickedDate) { _, newValue in
            if ignoreDateChange {
                ignoreDateChange = false
            } else if showDatePicker {
                setDay(newValue)
            }
        }
        .onChange(of: pickedTime) { _, newValue in
            if ignoreTimeChange {
                ignoreTimeChange = false
            } else if showTimePicker {
                let minutes = AsistCalendar.minuteOfDay(newValue, calendar: AppTime.calendar)
                setTime(ClockTime(minutesOfDay: minutes))
            }
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        if original != nil {
            editor
        } else if loadAttempted {
            unavailable
        } else {
            Color.clear
        }
    }

    private var unavailable: some View {
        VStack(spacing: Metrics.cardSpacing) {
            if foundClosed {
                EmptyStateView(title: "Bu kayıt artık açık değil",
                               message: "Tamamlanan ya da silinen kayıtlar buradan düzenlenemez.",
                               systemImage: "checkmark.circle")
            } else {
                EmptyStateView(title: "Kayıt bulunamadı",
                               message: "Bu kayıt silinmiş ya da artık mevcut değil.",
                               systemImage: "questionmark.folder")
            }
            Button {
                router.dismissSheet()
            } label: {
                Text("Kapat")
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
            .padding(.horizontal, Metrics.padding)
        }
        .frame(maxHeight: .infinity)
    }

    private var editor: some View {
        let now = Date()
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleSection(now: now)
                Group {
                    if showsDayRows {
                        daySection(now: now)
                        if showDatePicker {
                            DatePicker("Tarih", selection: $pickedDate, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .environment(\.locale, Locale(identifier: "tr_TR"))
                        }
                    }
                    if draft.dueDate != nil {
                        timeSection
                        if showTimePicker {
                            DatePicker("Saat", selection: $pickedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .environment(\.locale, Locale(identifier: "tr_TR"))
                        }
                    }
                }
                Group {
                    prioritySection
                    kindSection
                    projectSection
                    if draft.dueDate != nil && draft.kind != .note {
                        recurrenceSection
                    }
                    personSection
                    if showsEvent {
                        eventSection
                    }
                    if showsLead {
                        leadSection
                    }
                }
                detailsButton
            }
            .padding(Metrics.padding)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func titleSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(draft.isEvent ? "Etkinlik" : draft.kind.label,
                  systemImage: draft.isEvent ? Symbol.event : draft.kind.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
            TextField("Başlık", text: $draft.title, axis: .vertical)
                .font(.title2.weight(.semibold))
                .lineLimit(1...4)
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
            Text(whenText(now: now))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(whenColor(now: now))
            if let snoozed = draft.snoozedUntil, !timeChanged {
                Label("Ertelendi → " + TurkishDateFormatter.shortDateTime(snoozed, now: now,
                                                                           calendar: AppTime.calendar,
                                                                           includeTime: true),
                      systemImage: Symbol.snooze)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            if isPastSelection(now: now) {
                Text("Bu zaman geçti; kayıt hemen geciken olarak görünür.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func daySection(now: Date) -> some View {
        let options = dayOptions(now: now)
        let offersUndated = draft.kind == .task || draft.kind == .note
        let undated = draft.dueDate == nil
        return chipSection("Gün") {
            ForEach(options) { option in
                Chip(title: option.title, isSelected: option.isSelected) {
                    setDay(option.day)
                }
            }
            Chip(title: "Tarih…", systemImage: "calendar", isSelected: showDatePicker) {
                toggleDatePicker()
            }
            if offersUndated {
                Chip(title: "Zamanı belirsiz", isSelected: undated) {
                    setUndated()
                }
            }
        }
    }

    private var timeSection: some View {
        let options = timeOptions()
        let offersAllDay = draft.kind == .task || draft.kind == .waiting
        let allDay = draft.dueDate != nil && !draft.hasTime
        return chipSection("Saat") {
            if offersAllDay {
                Chip(title: "Gün içinde", isSelected: allDay) {
                    setAllDay()
                }
            }
            ForEach(options, id: \.self) { minutes in
                let clock = ClockTime(minutesOfDay: minutes)
                Chip(title: clock.display, isSelected: isSelectedTime(clock)) {
                    setTime(clock)
                }
            }
            Chip(title: "Saat…", systemImage: "clock", isSelected: showTimePicker) {
                toggleTimePicker()
            }
        }
    }

    private var prioritySection: some View {
        let current = draft.priority
        return chipSection("Öncelik") {
            ForEach(ItemEditSheet.priorityChoices, id: \.self) { priority in
                Chip(title: priority.label, systemImage: prioritySymbol(priority), isSelected: current == priority) {
                    draft.priority = priority
                }
            }
        }
    }

    private var kindSection: some View {
        let current = draft.kind
        let waitingHint = current == .waiting && draft.dueDate == nil
        let workdays = store.settings.waitingDefaultWorkdays
        return VStack(alignment: .leading, spacing: 6) {
            chipSection("Tür") {
                ForEach(ItemKind.allCases, id: \.self) { kind in
                    Chip(title: kind.label, systemImage: kind.symbol, isSelected: current == kind) {
                        draft.kind = kind
                    }
                }
            }
            if waitingHint {
                Text("Gün seçmezsen " + String(workdays) + " iş günü sonra “Geldi mi?” diye sorarım.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var projectSection: some View {
        let projects = visibleProjects()
        let selectedID = draft.projectID
        return chipSection("Proje") {
            Chip(title: "Yok", isSelected: selectedID == nil) {
                draft.projectID = nil
            }
            ForEach(projects) { project in
                Chip(title: project.name, systemImage: Symbol.project, isSelected: selectedID == project.id) {
                    draft.projectID = project.id
                }
            }
        }
    }

    private var recurrenceSection: some View {
        let calendar = AppTime.calendar
        let presets = draft.dueDate.map { (due: Date) in RecurrencePresets.presets(for: due, calendar: calendar) } ?? []
        let current = draft.recurrence
        let matchesPreset = presets.contains { $0.rule == current }
        return chipSection("Tekrar") {
            Chip(title: "Yok", isSelected: current == nil) {
                draft.recurrence = nil
            }
            if let current = current, !matchesPreset {
                Chip(title: TurkishDateFormatter.recurrenceText(current), systemImage: Symbol.recurrence,
                     isSelected: true) {
                    draft.recurrence = current
                }
            }
            ForEach(presets) { preset in
                Chip(title: preset.title, systemImage: Symbol.recurrence, isSelected: current == preset.rule) {
                    draft.recurrence = preset.rule
                }
            }
        }
    }

    private var personSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kişi / Firma")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary)
            TextField("Örn: Ahmet, ABB", text: $personText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .focused($focusedField, equals: .person)
                .onSubmit {
                    focusedField = nil
                }
                .padding(.horizontal, 12)
                .frame(minHeight: Metrics.chipHeight)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .tertiarySystemFill)))
        }
    }

    private var eventSection: some View {
        let isEvent = draft.isEvent
        return chipSection("Etkinlik") {
            Chip(title: "Etkinlik (toplantı, ziyaret…)", systemImage: Symbol.event, isSelected: isEvent) {
                toggleEvent()
            }
        }
    }

    private var leadSection: some View {
        let leads = draft.leadTimesMinutes
        var shown: [Int] = ItemEditSheet.leadChoices
        for minutes in leads where !shown.contains(minutes) {
            shown.append(minutes)
        }
        let choices = shown.sorted()
        return chipSection("Ön uyarı") {
            Chip(title: "Yok", isSelected: leads.isEmpty) {
                draft.leadTimesMinutes = []
            }
            ForEach(choices, id: \.self) { minutes in
                Chip(title: leadTitle(minutes), systemImage: Symbol.preAlert, isSelected: leads.contains(minutes)) {
                    toggleLead(minutes)
                }
            }
        }
    }

    private var detailsButton: some View {
        VStack(spacing: 4) {
            Button {
                openDetails()
            } label: {
                Label("Tüm ayrıntılar", systemImage: "list.bullet.rectangle")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            Text("Kontrol listesi, notlar, geçmiş ve ısrar düzeyi orada.")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }

    /// Caption + horizontal chip row (a private copy of ConfirmationSheet.chipSection).
    private func chipSection<Content: View>(_ title: String,
                                            @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary)
            ChipRow(content: content)
                .buttonStyle(.borderless)
        }
    }

    // MARK: - Derived values

    private var cancelTitle: String {
        original == nil ? "Kapat" : "Vazgeç"
    }

    private var titleIsEmpty: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Notes without a date have no day row (like the capture card).
    private var showsDayRows: Bool {
        draft.kind != .note || draft.dueDate != nil
    }

    private var showsClock: Bool {
        draft.hasTime || draft.kind == .reminder
    }

    private var showsEvent: Bool {
        draft.dueDate != nil && draft.hasTime && (draft.kind == .reminder || draft.kind == .task)
    }

    private var showsLead: Bool {
        draft.dueDate != nil && showsClock && draft.kind != .note
    }

    /// The day or the clock was changed in this sheet.
    private var timeChanged: Bool {
        guard let original = original else { return false }
        return draft.dueDate != original.dueDate || draft.hasTime != original.hasTime
    }

    private func whenText(now: Date) -> String {
        let calendar = AppTime.calendar
        guard let due = draft.dueDate else { return "Zamanı belirsiz" }
        let day = TurkishDateFormatter.datePhrase(due, now: now, calendar: calendar)
        if showsClock {
            return day + " · " + TurkishDateFormatter.time(due, calendar: calendar)
        }
        return day + " · Gün içinde"
    }

    private func whenColor(now: Date) -> Color {
        guard let due = draft.dueDate, draft.kind != .note else { return Color.asistNote }
        if isPastSelection(now: now) { return Color.asistOverdue }
        if draft.kind == .waiting { return Color.asistFollowUp }
        if AppTime.calendar.isDate(due, inSameDayAs: now) { return Color.asistToday }
        return Color.asistUpcoming
    }

    /// A day/time chosen in this sheet that is already overdue (snooze ignored: a new time clears it on save).
    private func isPastSelection(now: Date) -> Bool {
        guard timeChanged, draft.dueDate != nil else { return false }
        var probe = draft
        probe.snoozedUntil = nil
        probe.status = .open
        return probe.isOverdue(at: now, calendar: AppTime.calendar)
    }

    private func isSelectedTime(_ clock: ClockTime) -> Bool {
        guard let due = draft.dueDate, showsClock else { return false }
        return AsistCalendar.minuteOfDay(due, calendar: AppTime.calendar) == clock.minutesOfDay
    }

    /// Bugün, Yarın, the next 5 days ("Per 2"); the current day first when it lies outside that week.
    private func dayOptions(now: Date) -> [EditDayOption] {
        let calendar = AppTime.calendar
        let today = calendar.startOfDay(for: now)
        var result: [EditDayOption] = []
        var coversCurrent = false
        for offset in 0..<7 {
            let day = AsistCalendar.addingDays(offset, to: today, calendar: calendar)
            var selected = false
            if let due = draft.dueDate {
                selected = calendar.isDate(due, inSameDayAs: day)
            }
            if selected {
                coversCurrent = true
            }
            result.append(EditDayOption(id: AsistCalendar.dayKey(day, calendar: calendar),
                                        title: dayTitle(day, offset: offset, calendar: calendar),
                                        day: day, isSelected: selected))
        }
        if let due = draft.dueDate, !coversCurrent {
            let day = calendar.startOfDay(for: due)
            let title = TurkishDateFormatter.shortDateTime(day, now: now, calendar: calendar, includeTime: false)
            result.insert(EditDayOption(id: AsistCalendar.dayKey(day, calendar: calendar), title: title, day: day,
                                        isSelected: true), at: 0)
        }
        return result
    }

    private func dayTitle(_ day: Date, offset: Int, calendar: Calendar) -> String {
        if offset == 0 { return "Bugün" }
        if offset == 1 { return "Yarın" }
        let iso = AsistCalendar.isoWeekday(day, calendar: calendar)
        let names = TurkishDateFormatter.weekdaysShort
        let name = names[min(names.count - 1, max(0, iso - 1))]
        return name + " " + String(calendar.component(.day, from: day))
    }

    /// The user's daypart clocks (sabah, öğle, öğleden sonra, akşamüstü, akşam) + the current clock; unique, sorted.
    private func timeOptions() -> [Int] {
        let settings = store.settings
        let dayparts: [ClockTime] = [settings.sabah, settings.ogle, settings.ogledenSonra, settings.aksamustu,
                                     settings.aksam]
        var minutes: [Int] = []
        for clock in dayparts where !minutes.contains(clock.minutesOfDay) {
            minutes.append(clock.minutesOfDay)
        }
        if let due = draft.dueDate, showsClock {
            let current = AsistCalendar.minuteOfDay(due, calendar: AppTime.calendar)
            if !minutes.contains(current) {
                minutes.append(current)
            }
        }
        return minutes.sorted()
    }

    /// Active projects + the current one if archived, by name.
    private func visibleProjects() -> [Project] {
        let selectedID = draft.projectID
        var list: [Project] = []
        for project in store.projects where !project.archived || project.id == selectedID {
            list.append(project)
        }
        list.sort { TurkishText.fold($0.name) < TurkishText.fold($1.name) }
        return list
    }

    private func prioritySymbol(_ priority: Priority) -> String? {
        switch priority {
        case .critical: return Symbol.critical
        case .high: return Symbol.important
        case .low, .normal: return nil
        }
    }

    private func leadTitle(_ minutes: Int) -> String {
        switch minutes {
        case 60: return "1 saat"
        case 1440: return "1 gün"
        default:
            if minutes < 60 {
                return String(minutes) + " dk"
            }
            return TurkishDateFormatter.duration(minutes: minutes)
        }
    }

    // MARK: - Mutations (the draft only; nothing is stored before "Kaydet")

    private func load() {
        guard !loadAttempted else { return }
        loadAttempted = true
        guard let item = store.item(itemID) else { return }
        guard item.isOpen else {
            foundClosed = true
            return
        }
        original = item
        draft = item
        personText = item.person ?? ""
    }

    /// Keeps the clock: an existing due keeps its time on the new day; no due yet → default day time (a timed
    /// reminder, an untimed task/Takip).
    private func setDay(_ day: Date) {
        let calendar = AppTime.calendar
        if let due = draft.dueDate {
            let clock = ClockTime(minutesOfDay: AsistCalendar.minuteOfDay(due, calendar: calendar))
            draft.dueDate = AsistCalendar.date(on: day, at: clock, calendar: calendar)
        } else {
            let settings = store.settings
            let clock = draft.kind == .waiting ? settings.waitingDefaultTime : settings.defaultDayTime
            draft.dueDate = AsistCalendar.date(on: day, at: clock, calendar: calendar)
            draft.hasTime = draft.kind == .reminder
        }
    }

    private func setTime(_ clock: ClockTime) {
        let base = draft.dueDate ?? Date()
        draft.dueDate = AsistCalendar.date(on: base, at: clock, calendar: AppTime.calendar)
        draft.hasTime = true
    }

    /// "Gün içinde": the day is kept, the clock no longer counts.
    private func setAllDay() {
        guard draft.dueDate != nil else { return }
        draft.hasTime = false
        draft.isEvent = false
        showTimePicker = false
    }

    /// "Zamanı belirsiz" (Görev / Not): no due date (ItemEditRules clears repeat, pre-alerts and event too).
    private func setUndated() {
        draft.dueDate = nil
        draft.hasTime = false
        draft.recurrence = nil
        draft.leadTimesMinutes = []
        draft.isEvent = false
        showDatePicker = false
        showTimePicker = false
    }

    private func toggleEvent() {
        if draft.isEvent {
            draft.isEvent = false
            return
        }
        draft.isEvent = true
        let lead = store.settings.eventDefaultLeadMinutes
        if draft.leadTimesMinutes.isEmpty && lead > 0 {
            draft.leadTimesMinutes = [lead]
        }
    }

    private func toggleLead(_ minutes: Int) {
        var leads = draft.leadTimesMinutes
        if let index = leads.firstIndex(of: minutes) {
            leads.remove(at: index)
        } else {
            leads.append(minutes)
        }
        draft.leadTimesMinutes = Array(Set(leads)).sorted()
    }

    private func toggleDatePicker() {
        if !showDatePicker {
            let preset = draft.dueDate ?? Date()
            if preset != pickedDate {
                ignoreDateChange = true
                pickedDate = preset
            }
        }
        showTimePicker = false
        showDatePicker.toggle()
    }

    private func toggleTimePicker() {
        if !showTimePicker {
            let preset = draft.dueDate ?? Date()
            if preset != pickedTime {
                ignoreTimeChange = true
                pickedTime = preset
            }
        }
        showDatePicker = false
        showTimePicker.toggle()
    }

    /// Return in the (vertical-axis) title field inserts a newline: turn it into a space and close the keyboard.
    private func flattenTitle(_ value: String) {
        guard value.contains("\n") else { return }
        draft.title = value.replacingOccurrences(of: "\n", with: " ")
        focusedField = nil
    }

    // MARK: - Save / cancel

    /// The edited copy with the person field applied; an untouched person keeps its stored spelling.
    private func editedCopy(original: Item) -> Item {
        var edited = draft
        let typed = personText.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (original.person ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if typed == stored {
            edited.person = original.person
        } else {
            edited.person = typed.isEmpty ? nil : typed
        }
        return edited
    }

    /// One store.update with ItemEditRules (07 §4.1): "Güncellendi" + "Geri Al" when something changed.
    private func commitEdits() {
        guard let original = original else { return }
        focusedField = nil
        guard let current = store.item(itemID), current.isOpen else {
            toasts.show("Bu kayıt artık açık değil.")
            Haptics.warning()
            return
        }
        let outcome = ItemEditRules.apply(original: original, edited: editedCopy(original: original), onto: current,
                                          now: Date(), settings: store.settings, calendar: AppTime.calendar)
        guard outcome.changed else { return }
        let updated = outcome.item
        if let token = store.update(itemID, event: outcome.event, { edited in
            edited = updated
        }) {
            toasts.show("Güncellendi", undo: token)
            Haptics.success()
        } else {
            DetailItemActions.reportNil("düzenle", store: store, toasts: toasts)
        }
    }

    private func save() {
        commitEdits()
        router.dismissSheet()
    }

    private func cancel() {
        focusedField = nil
        router.dismissSheet()
    }

    /// "Tüm ayrıntılar": keeps what was chosen here (one update, undoable), then opens the full detail screen
    /// (checklist, notes, history, ısrar düzeyi) on the current tab.
    private func openDetails() {
        commitEdits()
        let id = itemID
        router.dismissSheet()
        router.push(.item(id))
    }
}

/// One day chip of the Düzenle sheet.
private struct EditDayOption: Identifiable {
    let id: String
    let title: String
    let day: Date
    let isSelected: Bool
}
