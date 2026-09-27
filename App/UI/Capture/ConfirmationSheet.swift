// WP9 (04 §5.2; 03 §4.5, §5.5, §7.5, §7.12 confirm.*; D10/D20/D31/D33; 05b D11/P2/P3): the confirmation card.
// Heard text + "Tekrar söyle", kind, editable title, relative date, chip rows Gün / Saat / Öncelik / Tür / Proje /
// Tekrar / Kişi / Etkinlik / Ön uyarı, "Ne zaman?" when a reminder has no time, alternative times, and
// Vazgeç / Kaydet with the auto-save countdown ring. Any touch stops the countdown (draft.autoSaveActive = false).
// Nothing is lost: swiping the sheet away commits the draft (RootView onDismiss → commitActiveDraftIfNeeded).
import SwiftUI
import UIKit
import AsistCore

struct ConfirmationSheet: View {
    let draft: CaptureDraft

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(VoiceCoordinator.self) private var voice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var remaining = 0
    @State private var total = 0
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var pickedDate = Date()
    @State private var pickedTime = Date()
    @State private var personText = ""
    @State private var dayConfirmed = false
    @State private var timeConfirmed = false
    @State private var didSetUp = false
    /// Programmatic picker preloads must not count as a user choice.
    @State private var ignoreDateChange = false
    @State private var ignoreTimeChange = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title, person
    }

    /// Explicit so the private @State storage never narrows the initializer's access level (SheetHost calls it).
    init(draft: CaptureDraft) {
        self.draft = draft
    }

    var body: some View {
        @Bindable var draft = draft
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heardSection
                if draft.level == .review {
                    lowConfidenceHint
                }
                VStack(alignment: .leading, spacing: 6) {
                    kindLine
                    TextField("Başlık", text: $draft.item.title, axis: .vertical)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1...4)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.done)
                    whenSummary
                }
                Group {
                    if draft.needsTime {
                        needsTimeSection
                    }
                    if draft.parse.flags.contains(.rolledToTomorrow) && draft.item.dueDate != nil {
                        pastHintSection
                    }
                    if !draft.alternativeTimes.isEmpty && draft.item.dueDate != nil {
                        alternativesSection
                    }
                }
                if showsDateRows {
                    daySection
                    if showDatePicker {
                        DatePicker("Tarih", selection: $pickedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                    }
                    timeSection
                    if showTimePicker {
                        DatePicker("Saat", selection: $pickedTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                    }
                }
                Group {
                    prioritySection
                    kindSection
                    projectSection
                    if draft.item.dueDate != nil && draft.item.kind != .note {
                        recurrenceSection
                    }
                    personSection
                    if showsEventAndLead {
                        eventSection
                        leadSection
                    }
                }
            }
            .padding(Metrics.padding)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            buttonBar
        }
        .simultaneousGesture(TapGesture().onEnded {
            stopCountdown()
        })
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: draft.id) {
            await runCountdown()
        }
        .onAppear {
            setUp()
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue != nil {
                stopCountdown()
            }
        }
        .onChange(of: personText) { _, newValue in
            applyPerson(newValue)
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
                let calendar = AppTime.calendar
                let minutes = AsistCalendar.minuteOfDay(newValue, calendar: calendar)
                setTime(ClockTime(minutesOfDay: minutes))
            }
        }
    }

    // MARK: - Header parts

    private var heardSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.source == .voice ? "Duyduğum" : "Yazdığın")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            HStack(alignment: .top, spacing: 8) {
                Text("“" + draft.heardText + "”")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if draft.source == .voice {
                    Button {
                        redo()
                    } label: {
                        Label("Tekrar söyle", systemImage: Symbol.mic)
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var lowConfidenceHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Symbol.review)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bunu mu demek istedin?")
                    .font(.headline)
                Text("Tam emin olamadım. Doğruysa kaydet, değilse düzelt.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cornerRadius).fill(Color.asistReview.opacity(0.18)))
    }

    private var kindLine: some View {
        let item = draft.item
        let symbol = item.isEvent ? Symbol.event : item.kind.symbol
        let label = item.isEvent ? "Etkinlik" : item.kind.label
        return Label(label, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(timeColor)
    }

    private var whenSummary: some View {
        let calendar = AppTime.calendar
        let now = Date()
        let item = draft.item
        return VStack(alignment: .leading, spacing: 2) {
            if let due = item.dueDate {
                Text(primaryWhenText(due, now: now, calendar: calendar))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(timeColor)
                Text(secondaryWhenText(due, now: now, calendar: calendar))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if showsClock(item) && due < now {
                    Text("Bu saat geçti.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.asistOverdue)
                }
            } else if draft.needsTime {
                Text("Ne zaman?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.orange)
            } else if item.kind == .note {
                Text(noteLabel(item))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.asistNote)
            } else {
                Text("Zamanı belirsiz")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.asistNote)
            }
        }
    }

    // MARK: - Chip rows

    private var needsTimeSection: some View {
        let now = Date()
        let calendar = AppTime.calendar
        let evening = SnoozeOption.thisEvening.target(now: now, settings: store.settings, calendar: calendar)
        return chipSection("Ne zaman?", highlighted: true) {
            Chip(title: "1 saat sonra", systemImage: "clock") {
                setInstant(AsistCalendar.ceilToMinute(Date().addingTimeInterval(3600)))
            }
            if let evening = evening {
                Chip(title: "Bu akşam", systemImage: "moon") {
                    setInstant(evening)
                }
            }
            Chip(title: "Yarın sabah", systemImage: Symbol.briefing) {
                setInstant(NagPlanner.tomorrowMorning(after: Date(), settings: store.settings,
                                                      calendar: AppTime.calendar))
            }
            Chip(title: "Zamanı belirsiz") {
                setUndated()
            }
        }
    }

    private var pastHintSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bu saat geçti; yarına ayarladım.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Chip(title: "Bugün hemen", systemImage: "bolt.fill") {
                setInstant(AsistCalendar.ceilToMinute(Date().addingTimeInterval(5 * 60)))
            }
        }
    }

    private var alternativesSection: some View {
        chipSection("Belki şunu demek istedin", highlighted: false) {
            ForEach(draft.alternativeTimes, id: \.self) { alternative in
                Chip(title: alternativeLabel(alternative), isSelected: draft.item.dueDate == alternative) {
                    applyAlternative(alternative)
                }
            }
        }
    }

    private var daySection: some View {
        let options = dayOptions()
        let uncertainDay = !dayConfirmed && dayIsUncertain
        return chipSection("Gün", highlighted: false) {
            ForEach(options) { option in
                Chip(title: option.title, isSelected: option.isSelected,
                     isUncertain: option.isSelected && uncertainDay) {
                    setDay(option.day)
                }
            }
            if draft.item.kind == .task {
                Chip(title: "Zamanı belirsiz", isSelected: draft.item.dueDate == nil) {
                    setUndated()
                }
            }
            Chip(title: "Tarih…", systemImage: "calendar", isSelected: showDatePicker) {
                toggleDatePicker()
            }
        }
    }

    private var timeSection: some View {
        let options = timeOptions()
        let uncertainTime = !timeConfirmed && timeIsUncertain
        return chipSection("Saat", highlighted: false) {
            if draft.item.kind == .task || draft.item.kind == .waiting {
                Chip(title: "Gün içinde", isSelected: draft.item.dueDate != nil && !draft.item.hasTime) {
                    setAllDay()
                }
            }
            ForEach(options, id: \.self) { minutes in
                let clock = ClockTime(minutesOfDay: minutes)
                let selected = isSelectedTime(clock)
                Chip(title: clock.display, isSelected: selected, isUncertain: selected && uncertainTime) {
                    setTime(clock)
                }
            }
            Chip(title: "Saat…", systemImage: "clock", isSelected: showTimePicker) {
                toggleTimePicker()
            }
        }
    }

    private var prioritySection: some View {
        let current = draft.item.priority
        let choices: [Priority] = current == .low ? [.low, .normal, .high, .critical] : [.normal, .high, .critical]
        return chipSection("Öncelik", highlighted: false) {
            ForEach(choices, id: \.self) { priority in
                Chip(title: priority.label, systemImage: prioritySymbol(priority), isSelected: current == priority) {
                    touch()
                    draft.item.priority = priority
                }
            }
        }
    }

    private var kindSection: some View {
        let current = draft.item.kind
        return chipSection("Tür", highlighted: false) {
            ForEach(ItemKind.allCases, id: \.self) { kind in
                Chip(title: kind.label, systemImage: kind.symbol, isSelected: current == kind) {
                    setKind(kind)
                }
            }
        }
    }

    private var projectSection: some View {
        let projects = visibleProjects()
        let selectedID = draft.item.projectID
        let newName = newProjectName()
        return chipSection("Proje", highlighted: false) {
            Chip(title: "Yok", isSelected: selectedID == nil) {
                touch()
                draft.item.projectID = nil
            }
            ForEach(projects) { project in
                Chip(title: project.name, systemImage: Symbol.project, isSelected: selectedID == project.id) {
                    touch()
                    draft.item.projectID = project.id
                }
            }
            if let newName = newName {
                // 05b D11: never pre-selected; created only when tapped.
                Chip(title: "Yeni proje: " + newName, systemImage: "plus") {
                    createProject(named: newName)
                }
            }
        }
    }

    private var recurrenceSection: some View {
        let presets = recurrencePresets()
        let current = draft.item.recurrence
        let matchesPreset = presets.contains { $0.rule == current }
        return chipSection("Tekrar", highlighted: false) {
            Chip(title: "Yok", isSelected: current == nil) {
                touch()
                draft.item.recurrence = nil
            }
            if let current = current, !matchesPreset {
                Chip(title: TurkishDateFormatter.recurrenceText(current), systemImage: Symbol.recurrence,
                     isSelected: true) {
                    touch()
                }
            }
            ForEach(presets) { preset in
                Chip(title: preset.title, systemImage: Symbol.recurrence, isSelected: current == preset.rule) {
                    touch()
                    draft.item.recurrence = preset.rule
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
                .padding(.horizontal, 12)
                .frame(minHeight: Metrics.chipHeight)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .tertiarySystemFill)))
        }
    }

    private var eventSection: some View {
        chipSection("Etkinlik", highlighted: false) {
            Chip(title: "Etkinlik (toplantı, ziyaret…)", systemImage: Symbol.event, isSelected: draft.item.isEvent) {
                toggleEvent()
            }
        }
    }

    private var leadSection: some View {
        let leads = draft.item.leadTimesMinutes
        let choices: [Int] = [10, 15, 30, 60, 1440]
        return chipSection("Ön uyarı", highlighted: false) {
            Chip(title: "Yok", isSelected: leads.isEmpty) {
                touch()
                draft.item.leadTimesMinutes = []
            }
            ForEach(choices, id: \.self) { minutes in
                Chip(title: leadTitle(minutes), systemImage: Symbol.preAlert, isSelected: leads.contains(minutes)) {
                    toggleLead(minutes)
                }
            }
        }
    }

    private func chipSection<Content: View>(_ title: String, highlighted: Bool,
                                            @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(highlighted ? Color.orange : Color.secondary)
            ChipRow(content: content)
        }
        .padding(highlighted ? 10 : 0)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .fill(highlighted ? Color.orange.opacity(0.12) : Color.clear)
        )
    }

    // MARK: - Buttons

    private var buttonBar: some View {
        HStack(spacing: Metrics.cardSpacing) {
            Button {
                cancel()
            } label: {
                Text("Vazgeç")
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
            Button {
                save()
            } label: {
                HStack(spacing: 10) {
                    Text("Kaydet")
                    if remaining > 0 && draft.autoSaveActive {
                        CountdownRing(remaining: remaining, total: total, animated: !reduceMotion)
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(titleIsEmpty)
        }
        .padding(.horizontal, Metrics.padding)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Derived values

    private var titleIsEmpty: Bool {
        draft.item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsDateRows: Bool {
        draft.item.kind != .note || draft.item.dueDate != nil
    }

    private var showsEventAndLead: Bool {
        let item = draft.item
        return item.dueDate != nil && item.hasTime && (item.kind == .reminder || item.kind == .task)
    }

    private var timeColor: Color {
        let item = draft.item
        guard let due = item.dueDate else { return Color.asistNote }
        if item.kind == .note { return Color.asistNote }
        if item.kind == .waiting { return Color.asistFollowUp }
        if AppTime.calendar.isDate(due, inSameDayAs: Date()) { return Color.asistToday }
        return Color.asistUpcoming
    }

    private var dayIsUncertain: Bool {
        let flags = draft.parse.flags
        return flags.contains(.nextWeekAmbiguous) || flags.contains(.vagueDate) || flags.contains(.conflictingDates)
    }

    private var timeIsUncertain: Bool {
        let flags = draft.parse.flags
        return flags.contains(.ambiguousHourPM) || flags.contains(.ambiguousHourNearest)
            || flags.contains(.ambiguousDotted)
    }

    /// "Not · <Proje>" / "Not".
    private func noteLabel(_ item: Item) -> String {
        guard let project = store.project(item.projectID) else { return "Not" }
        return "Not · " + project.name
    }

    private func showsClock(_ item: Item) -> Bool {
        item.hasTime || item.kind == .reminder
    }

    private func primaryWhenText(_ due: Date, now: Date, calendar: Calendar) -> String {
        let item = draft.item
        let day = TurkishDateFormatter.shortDateTime(due, now: now, calendar: calendar, includeTime: false)
        var text: String
        if showsClock(item) {
            text = day + " · " + TurkishDateFormatter.time(due, calendar: calendar)
        } else {
            text = day + " · Gün içinde"
        }
        if !timeConfirmed && timeIsUncertain && showsClock(item) {
            text += "?"
        }
        return text
    }

    private func secondaryWhenText(_ due: Date, now: Date, calendar: Calendar) -> String {
        var parts: [String] = [TodayDateText.dayMonthWeekday(due, calendar: calendar),
                               TodayDateText.relativeDays(due, now: now, calendar: calendar)]
        if let recurrence = draft.item.recurrence {
            parts.append(TurkishDateFormatter.recurrenceText(recurrence))
        }
        return parts.joined(separator: " · ")
    }

    private func isSelectedTime(_ clock: ClockTime) -> Bool {
        guard let due = draft.item.dueDate, showsClock(draft.item) else { return false }
        return AsistCalendar.minuteOfDay(due, calendar: AppTime.calendar) == clock.minutesOfDay
    }

    /// Bugün, Yarın, the parsed day (if different), next Monday — de-duplicated by day.
    private func dayOptions() -> [DayOption] {
        let calendar = AppTime.calendar
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var days: [Date] = [today, AsistCalendar.addingDays(1, to: today, calendar: calendar)]
        if let due = draft.item.dueDate {
            days.append(calendar.startOfDay(for: due))
        }
        days.append(calendar.startOfDay(for: NagPlanner.nextMonday(now: now, settings: store.settings,
                                                                    calendar: calendar)))
        var result: [DayOption] = []
        var seen = Set<String>()
        for day in days {
            let key = AsistCalendar.dayKey(day, calendar: calendar)
            if seen.contains(key) { continue }
            seen.insert(key)
            let title = TurkishDateFormatter.shortDateTime(day, now: now, calendar: calendar, includeTime: false)
            var selected = false
            if let due = draft.item.dueDate {
                selected = calendar.isDate(due, inSameDayAs: day)
            }
            result.append(DayOption(id: key, title: title, day: day, isSelected: selected))
        }
        return result
    }

    /// Minutes of day: the parsed time (if any) + 09:00, 12:00, 15:00, 18:00 — unique, sorted.
    private func timeOptions() -> [Int] {
        var minutes: [Int] = [9 * 60, 12 * 60, 15 * 60, 18 * 60]
        if let due = draft.item.dueDate, showsClock(draft.item) {
            let current = AsistCalendar.minuteOfDay(due, calendar: AppTime.calendar)
            if !minutes.contains(current) {
                minutes.append(current)
            }
        }
        return minutes.sorted()
    }

    private func recurrencePresets() -> [RecurrencePreset] {
        let calendar = AppTime.calendar
        guard let due = draft.item.dueDate else { return [] }
        let iso = AsistCalendar.isoWeekday(due, calendar: calendar)
        let weekdayName = TurkishDateFormatter.weekdays[min(6, max(0, iso - 1))]
        var presets: [RecurrencePreset] = [
            RecurrencePreset(id: "daily", title: "Her gün", rule: Recurrence(frequency: .daily)),
            RecurrencePreset(id: "weekdays", title: "Hafta içi",
                             rule: Recurrence(frequency: .weekly, weekdays: [1, 2, 3, 4, 5])),
            RecurrencePreset(id: "weekly", title: "Her " + weekdayName,
                             rule: Recurrence(frequency: .weekly, weekdays: [iso]))
        ]
        let day = calendar.component(.day, from: due)
        if day <= 28 {
            presets.append(RecurrencePreset(id: "monthly", title: "Her ayın " + TurkishDateFormatter.numeralPossessive(day),
                                            rule: Recurrence(frequency: .monthly, monthDay: day)))
        }
        return presets
    }

    private func visibleProjects() -> [Project] {
        let selectedID = draft.item.projectID
        var list: [Project] = []
        for project in store.projects where !project.archived || project.id == selectedID {
            list.append(project)
        }
        list.sort { TurkishText.fold($0.name) < TurkishText.fold($1.name) }
        return list
    }

    /// Parser heard "X projesi…" but no project/alias matches → offer "Yeni proje: X" (never pre-selected).
    private func newProjectName() -> String? {
        guard draft.item.projectID == nil, let raw = draft.parse.item?.project else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let key = TurkishText.fold(name)
        for project in store.projects {
            for existing in project.allNames where TurkishText.fold(existing) == key {
                return nil
            }
        }
        return name
    }

    private func alternativeLabel(_ alternative: Date) -> String {
        let calendar = AppTime.calendar
        let now = Date()
        if let due = draft.item.dueDate {
            let days = ItemRowText.dayDistance(from: due, to: alternative, calendar: calendar)
            let sameClock = AsistCalendar.minuteOfDay(due, calendar: calendar)
                == AsistCalendar.minuteOfDay(alternative, calendar: calendar)
            if sameClock && days == 7 { return "+7 gün" }
            if sameClock && days == -7 { return "−7 gün" }
            if days == 0 { return TurkishDateFormatter.time(alternative, calendar: calendar) }
        }
        return TurkishDateFormatter.shortDateTime(alternative, now: now, calendar: calendar, includeTime: true)
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
        default: return String(minutes) + " dk"
        }
    }

    // MARK: - Mutations (every one stops the countdown)

    @MainActor
    private func touch() {
        stopCountdown()
    }

    @MainActor
    private func stopCountdown() {
        if draft.autoSaveActive {
            draft.autoSaveActive = false
        }
    }

    @MainActor
    private func setDay(_ day: Date) {
        touch()
        let calendar = AppTime.calendar
        let time: ClockTime
        if let due = draft.item.dueDate {
            time = ClockTime(minutesOfDay: AsistCalendar.minuteOfDay(due, calendar: calendar))
        } else {
            time = store.settings.defaultDayTime
        }
        draft.item.dueDate = AsistCalendar.date(on: day, at: time, calendar: calendar)
        draft.item.snoozedUntil = nil
        draft.needsTime = false
        dayConfirmed = true
    }

    @MainActor
    private func setTime(_ clock: ClockTime) {
        touch()
        let calendar = AppTime.calendar
        let now = Date()
        var date: Date
        if let due = draft.item.dueDate {
            date = AsistCalendar.date(on: due, at: clock, calendar: calendar)
        } else {
            date = AsistCalendar.date(on: now, at: clock, calendar: calendar)
            if date <= now {
                date = AsistCalendar.addingDays(1, to: date, calendar: calendar)
            }
        }
        draft.item.dueDate = date
        draft.item.hasTime = true
        draft.item.snoozedUntil = nil
        draft.needsTime = false
        timeConfirmed = true
    }

    /// Task/Takip: keep the day, drop the clock ("Gün içinde").
    @MainActor
    private func setAllDay() {
        touch()
        let calendar = AppTime.calendar
        let day = draft.item.dueDate ?? Date()
        draft.item.dueDate = AsistCalendar.date(on: day, at: store.settings.defaultDayTime, calendar: calendar)
        draft.item.hasTime = false
        draft.item.isEvent = false
        draft.needsTime = false
        timeConfirmed = true
    }

    @MainActor
    private func setInstant(_ date: Date) {
        touch()
        draft.item.dueDate = date
        draft.item.hasTime = true
        draft.item.snoozedUntil = nil
        draft.needsTime = false
        dayConfirmed = true
        timeConfirmed = true
    }

    /// "Zamanı belirsiz": an undated task (a reminder without time is not possible, D20).
    @MainActor
    private func setUndated() {
        touch()
        if draft.item.kind == .reminder || draft.item.kind == .waiting {
            draft.item.kind = .task
        }
        draft.item.dueDate = nil
        draft.item.hasTime = false
        draft.item.snoozedUntil = nil
        draft.item.recurrence = nil
        draft.item.isEvent = false
        draft.item.leadTimesMinutes = []
        draft.needsTime = false
        showDatePicker = false
        showTimePicker = false
    }

    @MainActor
    private func applyAlternative(_ alternative: Date) {
        touch()
        let calendar = AppTime.calendar
        if let due = draft.item.dueDate,
           AsistCalendar.minuteOfDay(due, calendar: calendar) != AsistCalendar.minuteOfDay(alternative, calendar: calendar) {
            draft.item.hasTime = true
        }
        draft.item.dueDate = alternative
        draft.item.snoozedUntil = nil
        dayConfirmed = true
        timeConfirmed = true
    }

    @MainActor
    private func setKind(_ kind: ItemKind) {
        touch()
        let calendar = AppTime.calendar
        draft.item.kind = kind
        switch kind {
        case .note:
            draft.item.isEvent = false
            draft.item.leadTimesMinutes = []
            draft.needsTime = false
        case .waiting:
            draft.item.isEvent = false
            if draft.item.dueDate == nil {
                draft.item.dueDate = ItemFactory.defaultWaitingDue(now: Date(), settings: store.settings,
                                                                    calendar: calendar)
                draft.item.hasTime = false
            }
            draft.needsTime = false
        case .reminder:
            draft.needsTime = draft.item.dueDate == nil
        case .task:
            draft.needsTime = false
        }
    }

    @MainActor
    private func toggleEvent() {
        touch()
        if draft.item.isEvent {
            draft.item.isEvent = false
            return
        }
        draft.item.isEvent = true
        draft.item.kind = .reminder
        let lead = store.settings.eventDefaultLeadMinutes
        if draft.item.leadTimesMinutes.isEmpty && lead > 0 {
            draft.item.leadTimesMinutes = [lead]
        }
    }

    @MainActor
    private func toggleLead(_ minutes: Int) {
        touch()
        var leads = draft.item.leadTimesMinutes
        if let index = leads.firstIndex(of: minutes) {
            leads.remove(at: index)
        } else {
            leads.append(minutes)
        }
        draft.item.leadTimesMinutes = Array(Set(leads)).sorted()
    }

    @MainActor
    private func applyPerson(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        guard draft.item.person != value else { return }
        if focusedField == .person {
            stopCountdown()
        }
        draft.item.person = value
    }

    @MainActor
    private func createProject(named name: String) {
        touch()
        let project = Project(name: name, createdAt: Date())
        store.upsertProject(project)
        if store.project(project.id) != nil {
            draft.item.projectID = project.id
        } else {
            AsistLog.error("Onay kartı: yeni proje kaydedilemedi", .ui)
        }
    }

    @MainActor
    private func toggleDatePicker() {
        touch()
        if !showDatePicker {
            let preset = draft.item.dueDate ?? Date()
            if preset != pickedDate {
                ignoreDateChange = true
                pickedDate = preset
            }
        }
        showTimePicker = false
        showDatePicker.toggle()
    }

    @MainActor
    private func toggleTimePicker() {
        touch()
        if !showTimePicker {
            let preset = draft.item.dueDate ?? Date()
            if preset != pickedTime {
                ignoreTimeChange = true
                pickedTime = preset
            }
        }
        showDatePicker = false
        showTimePicker.toggle()
    }

    // MARK: - Lifecycle

    @MainActor
    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        personText = draft.item.person ?? ""
        if draft.level == .review || draft.needsTime {
            Haptics.warning()
        }
    }

    /// 1 s loop while `draft.autoSaveActive`; at 0 the draft is saved (03 §4.5). No countdown with VoiceOver.
    @MainActor
    private func runCountdown() async {
        var seconds = draft.countdownSeconds
        if UIAccessibility.isVoiceOverRunning {
            seconds = 0
        }
        guard seconds > 0, draft.autoSaveActive, !draft.isResolved else {
            remaining = 0
            return
        }
        total = seconds
        remaining = seconds
        while remaining > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            if !draft.autoSaveActive || draft.isResolved {
                remaining = 0
                return
            }
            remaining -= 1
        }
        if draft.autoSaveActive && !draft.isResolved && !titleIsEmpty {
            save()
        }
    }

    // MARK: - Save / cancel / redo

    @MainActor
    private func save() {
        guard !draft.isResolved else { return }
        focusedField = nil
        let trimmedTitle = draft.item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.item.title = trimmedTitle.isEmpty ? "Kayıt" : trimmedTitle
        // D20: "Kaydet" without answering "Ne zaman?" → in one hour.
        if draft.needsTime && draft.item.dueDate == nil {
            draft.item.dueDate = ItemFactory.noTimeDefault(.inOneHour, now: Date(), settings: store.settings,
                                                          calendar: AppTime.calendar)
            draft.item.hasTime = true
            draft.needsTime = false
            draft.appliedDefaultTime = true
        }
        AppEnvironment.shared.capture.commit(draft)
        dismissIfShown()
    }

    @MainActor
    private func cancel() {
        focusedField = nil
        AppEnvironment.shared.capture.discard(draft)
        dismissIfShown()
    }

    /// "Tekrar söyle": this card is dropped silently (resolved, so onDismiss does not save it) and listening
    /// restarts; VoiceCoordinator closes the sheet first (05a #18).
    @MainActor
    private func redo() {
        stopCountdown()
        focusedField = nil
        draft.isResolved = true
        let voice = self.voice
        Task { @MainActor in
            await voice.startListening(ListenRequest())
        }
    }

    @MainActor
    private func dismissIfShown() {
        if case .confirm(let shown)? = router.sheet, shown.id == draft.id {
            router.dismissSheet()
        }
    }
}

// MARK: - Small value types

private struct DayOption: Identifiable {
    let id: String
    let title: String
    let day: Date
    let isSelected: Bool
}

private struct RecurrencePreset: Identifiable {
    let id: String
    let title: String
    let rule: Recurrence
}

/// Ring inside "Kaydet" that empties while the auto-save countdown runs.
private struct CountdownRing: View {
    let remaining: Int
    let total: Int
    let animated: Bool

    var body: some View {
        let fraction = CGFloat(remaining) / CGFloat(max(1, total))
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animated ? .linear(duration: 1) : nil, value: remaining)
            Text(String(remaining))
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .frame(width: 28, height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Otomatik kayıt: " + String(remaining) + " saniye")
    }
}
