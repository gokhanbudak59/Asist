// WP10 — Kayıt detayı (03 §4.8, 04 §5.2).
import SwiftUI
import AsistCore

/// Store mutations shared by the WP10 screens (detail, lists, projects, end of day): each one persists through
/// `DataStore`, shows the Turkish toast with "Geri Al" and gives haptic feedback. A nil store result means
/// "not persisted" (toast `error.save_failed`) or "nothing changed" (log only) — 05a #3.
@MainActor
enum DetailItemActions {
    static let saveFailedText = "Kaydedilemedi. Lütfen tekrar dene."

    static func reportNil(_ action: String, store: DataStore, toasts: ToastCenter) {
        if store.canPersist {
            AsistLog.info("Arayüz: " + action + " — değişiklik yok (kayıt yok ya da kapalı)", .app)
        } else {
            AsistLog.error("Arayüz: " + action + " kaydedilemedi", .store)
            toasts.show(store.lastSaveError ?? saveFailedText)
            Haptics.error()
        }
    }

    @discardableResult
    static func markDone(_ id: UUID, store: DataStore, toasts: ToastCenter) -> DoneResult? {
        let now = Date()
        let hasTime = store.item(id)?.hasTime ?? true
        guard let outcome = store.markDone(id, at: now) else {
            reportNil("tamamla", store: store, toasts: toasts)
            return nil
        }
        let result: DoneResult = outcome.0
        let token: UndoToken = outcome.1
        switch result {
        case .completed:
            toasts.show("Tamamlandı", undo: token)
        case .nextOccurrence(let next):
            let label = TurkishDateFormatter.shortDateTime(next, now: now, calendar: AppTime.calendar,
                                                           includeTime: hasTime)
            toasts.show("Bu seferlik tamamlandı · Sıradaki: " + label, undo: token)
        }
        Haptics.success()
        return result
    }

    static func reopen(_ id: UUID, store: DataStore, toasts: ToastCenter) {
        guard let token = store.reopen(id, at: Date()) else {
            reportNil("yeniden aç", store: store, toasts: toasts)
            return
        }
        toasts.show("Yeniden açıldı", undo: token)
        Haptics.selection()
    }

    static func snooze(_ id: UUID, until target: Date, store: DataStore, toasts: ToastCenter) {
        let now = Date()
        let whole = AsistCalendar.floorToMinute(target)
        guard whole > now else {
            toasts.show("Geçmiş bir zamana ertelenemez.")
            Haptics.warning()
            return
        }
        guard let token = store.snooze(id, until: whole, at: now) else {
            reportNil("ertele", store: store, toasts: toasts)
            return
        }
        let label = TurkishDateFormatter.shortDateTime(whole, now: now, calendar: AppTime.calendar, includeTime: true)
        toasts.show("Ertelendi · " + label, undo: token)
        Haptics.success()
    }

    static func delete(_ id: UUID, store: DataStore, toasts: ToastCenter) {
        guard let token = store.delete(id, at: Date()) else {
            reportNil("sil", store: store, toasts: toasts)
            return
        }
        toasts.show("Silindi", undo: token)
        Haptics.medium()
    }

    static func restore(_ id: UUID, store: DataStore, toasts: ToastCenter) {
        guard let token = store.restoreDeleted(id, at: Date()) else {
            reportNil("geri getir", store: store, toasts: toasts)
            return
        }
        toasts.show("Geri getirildi", undo: token)
        Haptics.success()
    }

    /// "Doğru" on an "Emin değilim" item (05b D8): clears the review flag.
    static func confirmReview(_ id: UUID, store: DataStore, toasts: ToastCenter) {
        guard let token = store.update(id, event: .edited, { edited in
            edited.needsReview = false
        }) else {
            reportNil("onayla", store: store, toasts: toasts)
            return
        }
        toasts.show("Onaylandı", undo: token)
        Haptics.success()
    }

    /// End-of-day row action "Sonraki iş günü" (one item; same rule as the bulk move, 05b B6).
    static func moveToNextWorkday(_ id: UUID, store: DataStore, toasts: ToastCenter) {
        guard let item = store.item(id), item.isOpen else { return }
        let now = Date()
        let calendar = AppTime.calendar
        let moved = AgendaBuilder.movedToTomorrow(item, now: now, settings: store.settings, calendar: calendar)
        guard let token = store.update(id, event: nil, { edited in
            edited = moved
        }) else {
            reportNil("taşı", store: store, toasts: toasts)
            return
        }
        var label = "sonraki iş günü"
        if let anchor = moved.anchorDate {
            label = TurkishDateFormatter.shortDateTime(anchor, now: now, calendar: calendar, includeTime: moved.hasTime)
        }
        toasts.show("Taşındı · " + label, undo: token)
        Haptics.success()
    }
}

@MainActor
struct ItemDetailView: View {
    let itemID: UUID

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    private enum DetailField: Hashable {
        case title, notes, person
    }

    private struct RecurrenceChoice: Identifiable {
        let id: String
        let title: String
        let rule: Recurrence
    }

    private struct LeadChoice: Identifiable {
        let id: Int          // minutes; 0 = none
        let title: String
    }

    private static let leadChoices: [LeadChoice] = [
        LeadChoice(id: 0, title: "Yok"),
        LeadChoice(id: 10, title: "10 dk"),
        LeadChoice(id: 15, title: "15 dk"),
        LeadChoice(id: 30, title: "30 dk"),
        LeadChoice(id: 60, title: "1 saat"),
        LeadChoice(id: 1440, title: "1 gün"),
        LeadChoice(id: 10080, title: "1 hafta"),
        LeadChoice(id: 43200, title: "30 gün")
    ]

    @State private var now = Date()
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var personDraft = ""
    @State private var isEventDraft = false
    @State private var draftsLoaded = false
    @State private var showDeleteConfirm = false
    @State private var showDictationHint = false
    @FocusState private var focusedField: DetailField?

    /// Explicit: private @State/@FocusState/@Environment storage must not narrow the synthesized memberwise
    /// initializer's access level (RouteDestination.swift constructs this view).
    init(itemID: UUID) {
        self.itemID = itemID
    }

    var body: some View {
        Group {
            if let item = store.item(itemID), item.status != .deleted {
                detail(item)
            } else if let deleted = store.item(itemID) {
                deletedState(deleted)
            } else {
                EmptyStateView(title: "Kayıt bulunamadı",
                               message: "Bu kayıt silinmiş ya da artık mevcut değil.",
                               systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(store.item(itemID)?.kind.label ?? "Kayıt")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Layout

    private func detail(_ item: Item) -> some View {
        List {
            headerSection(item)
            if item.needsReview && item.isOpen {
                reviewSection(item)
            }
            if item.kind != .note {
                timeSection(item)
            }
            propertiesSection(item)
            notesSection(item)
            ChecklistSection(item: item)
            if let original = item.originalText, !original.isEmpty {
                Section {
                    Text("“" + original + "”")
                        .font(.body)
                        .foregroundStyle(Color.secondary)
                        .textSelection(.enabled)
                } header: {
                    SectionHeader(title: "ORİJİNAL CÜMLE")
                }
            }
            HistorySection(item: item)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            bottomBar(item)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu(item)
            }
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Bitti") {
                        focusedField = nil
                    }
                }
            }
        }
        .confirmationDialog("Bu kayıt silinsin mi?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                deleteItem()
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .onAppear {
            loadDrafts(item)
        }
        .onDisappear {
            commitAll()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .title && newValue != .title { commitTitle() }
            if oldValue == .notes && newValue != .notes { commitNotes() }
            if oldValue == .person && newValue != .person { commitPerson() }
        }
        .onChange(of: titleDraft) { _, newValue in
            if newValue.contains("\n") {
                titleDraft = newValue.replacingOccurrences(of: "\n", with: " ")
                focusedField = nil
            }
        }
        .onChange(of: item.title) { _, newValue in
            if focusedField != .title { titleDraft = newValue }
        }
        .onChange(of: item.notes) { _, newValue in
            if focusedField != .notes { notesDraft = newValue }
        }
        .onChange(of: item.person) { _, newValue in
            if focusedField != .person { personDraft = newValue ?? "" }
        }
        .onChange(of: item.isEvent) { _, newValue in
            if isEventDraft != newValue { isEventDraft = newValue }
        }
        .onChange(of: isEventDraft) { _, newValue in
            setEvent(newValue)
        }
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func deletedState(_ item: Item) -> some View {
        VStack(spacing: Metrics.cardSpacing) {
            EmptyStateView(title: "Bu kayıt silindi",
                           message: "Silinen kayıtlar 30 gün boyunca geri getirilebilir.",
                           systemImage: "trash")
            Button {
                DetailItemActions.restore(item.id, store: store, toasts: toasts)
            } label: {
                Label("Geri getir", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Metrics.padding)
        }
        .padding(.bottom, Metrics.padding)
    }

    private func headerSection(_ item: Item) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Başlık", text: $titleDraft, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                badges(item)
                if item.status == .done {
                    Label(doneText(item), systemImage: Symbol.taskDone)
                        .font(.subheadline)
                        .foregroundStyle(Color.asistDone)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func badges(_ item: Item) -> some View {
        HStack(spacing: 8) {
            Label(item.kind.label, systemImage: item.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            if item.isEvent {
                Label("Etkinlik", systemImage: Symbol.event)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            PriorityBadge(priority: item.priority)
            if let project = store.project(item.projectID) {
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(Color.project(project.color))
            }
            Spacer(minLength: 0)
        }
    }

    private func reviewSection(_ item: Item) -> some View {
        Section {
            HStack(spacing: Metrics.cardSpacing) {
                Image(systemName: Symbol.review)
                    .foregroundStyle(Color.asistReview)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Emin değilim")
                        .font(.body.weight(.semibold))
                    Text("Bilgileri kontrol et; doğruysa onayla.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 8)
                Button("Doğru") {
                    DetailItemActions.confirmReview(item.id, store: store, toasts: toasts)
                }
                .font(.headline)
                .buttonStyle(.borderless)
                .frame(minWidth: 64, minHeight: 44)
            }
        }
    }

    private func timeSection(_ item: Item) -> some View {
        Section {
            dueRow(item)
            if let snoozed = item.snoozedUntil, item.isOpen {
                Label("Ertelendi → " + TurkishDateFormatter.shortDateTime(snoozed, now: now, calendar: AppTime.calendar,
                                                                           includeTime: true),
                      systemImage: Symbol.snooze)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            if item.isOpen && item.isNotifiable {
                SnoozeGrid(item: item, now: now)
            }
            recurrenceMenu(item)
            leadTimeMenu(item)
            nagMenu(item)
            if item.kind == .reminder || item.kind == .task {
                Toggle(isOn: $isEventDraft) {
                    Label("Etkinlik (toplantı, ziyaret…)", systemImage: Symbol.event)
                }
                .frame(minHeight: 44)
                .disabled(!item.isOpen)
            }
            if item.dueDate != nil && item.kind == .task && item.isOpen {
                Button(role: .destructive) {
                    clearDue()
                } label: {
                    Label("Zamanı kaldır", systemImage: "calendar.badge.minus")
                }
                .frame(minHeight: 44)
            }
        } header: {
            SectionHeader(title: "ZAMAN")
        }
    }

    private func dueRow(_ item: Item) -> some View {
        Button {
            focusedField = nil
            router.present(.datePicker(DatePickerRequest(itemID: item.id, purpose: .due)))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: Symbol.event)
                    .foregroundStyle(item.statusColor(now: now, calendar: AppTime.calendar))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dueTitle(item))
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)
                    if let relative = relativeText(item) {
                        Text(relative)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(item.statusColor(now: now, calendar: AppTime.calendar))
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isOpen)
        .accessibilityHint("Zamanı değiştir")
    }

    private func recurrenceMenu(_ item: Item) -> some View {
        Menu {
            Button {
                setRecurrence(nil)
            } label: {
                choiceLabel("Yok", selected: item.recurrence == nil)
            }
            if let due = item.dueDate {
                ForEach(recurrenceChoices(due: due)) { choice in
                    Button {
                        setRecurrence(choice.rule)
                    } label: {
                        choiceLabel(choice.title, selected: item.recurrence == choice.rule)
                    }
                }
            }
        } label: {
            valueRow("Tekrar", value: recurrenceValue(item), systemImage: Symbol.recurrence)
        }
        .disabled(item.dueDate == nil || !item.isOpen)
    }

    private func leadTimeMenu(_ item: Item) -> some View {
        Menu {
            ForEach(ItemDetailView.leadChoices) { choice in
                Button {
                    setLeadTime(choice.id)
                } label: {
                    choiceLabel(choice.title, selected: isLeadSelected(choice.id, item: item))
                }
            }
        } label: {
            valueRow("Ön uyarı", value: leadValue(item), systemImage: Symbol.preAlert)
        }
        .disabled(item.dueDate == nil || !item.isOpen)
    }

    private func nagMenu(_ item: Item) -> some View {
        Menu {
            Button {
                setNagProfile(nil)
            } label: {
                choiceLabel("Otomatik (" + autoNagLabel(item) + ")", selected: item.nagProfile == nil)
            }
            ForEach(NagProfileKind.selectable, id: \.self) { kind in
                Button {
                    setNagProfile(kind)
                } label: {
                    choiceLabel(kind.label, selected: item.nagProfile == kind)
                }
            }
        } label: {
            valueRow("Israr düzeyi", value: nagValue(item), systemImage: "bell.and.waves.left.and.right")
        }
        .disabled(item.kind == .waiting || !item.isOpen)
    }

    private func propertiesSection(_ item: Item) -> some View {
        Section {
            Menu {
                ForEach(ItemKind.allCases, id: \.self) { kind in
                    Button {
                        setKind(kind)
                    } label: {
                        choiceLabel(kind.label, selected: item.kind == kind)
                    }
                }
            } label: {
                valueRow("Tür", value: item.kind.label, systemImage: item.kind.symbol)
            }
            Menu {
                ForEach(ItemDetailView.priorityChoices, id: \.self) { priority in
                    Button {
                        setPriority(priority)
                    } label: {
                        choiceLabel(priority.label, selected: item.priority == priority)
                    }
                }
            } label: {
                valueRow("Öncelik", value: item.priority.label, systemImage: Symbol.important)
            }
            projectMenu(item)
            HStack(spacing: 12) {
                Image(systemName: Symbol.person)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 24)
                Text("Kişi / Firma")
                Spacer(minLength: 8)
                TextField("—", text: $personDraft)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .person)
                    .submitLabel(.done)
                    .onSubmit {
                        focusedField = nil
                    }
            }
            .frame(minHeight: 44)
            if let place = store.place(item.placeID) {
                HStack(spacing: 12) {
                    Image(systemName: Symbol.place)
                        .foregroundStyle(Color.secondary)
                        .frame(width: 24)
                    Text("Yer")
                    Spacer(minLength: 8)
                    Text(place.name)
                        .foregroundStyle(Color.secondary)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private static let priorityChoices: [Priority] = [.critical, .high, .normal, .low]

    private func projectMenu(_ item: Item) -> some View {
        Menu {
            Button {
                setProject(nil)
            } label: {
                choiceLabel("Yok", selected: item.projectID == nil)
            }
            ForEach(selectableProjects(current: item.projectID)) { project in
                Button {
                    setProject(project.id)
                } label: {
                    choiceLabel(project.name, selected: item.projectID == project.id)
                }
            }
            Divider()
            Button {
                focusedField = nil
                router.present(.projectEditor(nil))
            } label: {
                Label("Yeni Proje", systemImage: "plus")
            }
        } label: {
            valueRow("Proje", value: store.projectName(for: item) ?? "Yok", systemImage: Symbol.project)
        }
    }

    private func notesSection(_ item: Item) -> some View {
        Section {
            ZStack(alignment: .topLeading) {
                if notesDraft.isEmpty && focusedField != .notes {
                    Text(item.kind == .note ? "Notunu yaz…" : "Not ekle…")
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notesDraft)
                    .frame(minHeight: 110)
                    .focused($focusedField, equals: .notes)
                    .scrollContentBackground(.hidden)
            }
            Button {
                focusedField = .notes
                showDictationHint = true
            } label: {
                Label("Sesle not ekle", systemImage: Symbol.mic)
            }
            .frame(minHeight: 44)
            if showDictationHint {
                Text("Klavyedeki mikrofon tuşuna dokunup konuşabilirsin; söylediklerin nota eklenir.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        } header: {
            SectionHeader(title: "NOTLAR")
        }
    }

    @ViewBuilder
    private func bottomBar(_ item: Item) -> some View {
        if item.kind != .note {
            VStack(spacing: 8) {
                if item.kind == .waiting && item.isOpen {
                    Button {
                        commitAll()
                        focusedField = nil
                        router.present(.followUpMessage(item.id))
                    } label: {
                        Label("Hatırlatma mesajı gönder…", systemImage: Symbol.message)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Color.asistFollowUp, filled: false))
                }
                if item.isOpen {
                    Button {
                        completeItem(item)
                    } label: {
                        Text(item.kind == .waiting ? "✓ Geldi" : "✓ Yaptım")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Color.asistDone))
                } else if item.status == .done {
                    Button {
                        DetailItemActions.reopen(item.id, store: store, toasts: toasts)
                    } label: {
                        Label("Yeniden aç", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                }
            }
            .padding(.horizontal, Metrics.padding)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func moreMenu(_ item: Item) -> some View {
        Menu {
            Button {
                duplicate(item)
            } label: {
                Label("Çoğalt", systemImage: "plus.square.on.square")
            }
            ShareLink(item: shareText(item)) {
                Label("Paylaş", systemImage: Symbol.export)
            }
            Button(role: .destructive) {
                focusedField = nil
                showDeleteConfirm = true
            } label: {
                Label("Sil", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Diğer işlemler")
    }

    // MARK: - Small views

    @ViewBuilder
    private func choiceLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func valueRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.secondary)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Texts

    private func dueTitle(_ item: Item) -> String {
        guard let due = item.dueDate else { return "Zamanı belirsiz" }
        let calendar = AppTime.calendar
        let day = TurkishDateFormatter.datePhrase(due, now: now, calendar: calendar)
        if item.hasTime {
            return day + " · " + TurkishDateFormatter.time(due, calendar: calendar)
        }
        return day + " · Gün içinde"
    }

    private func relativeText(_ item: Item) -> String? {
        guard item.isOpen, let anchor = item.anchorDate else { return nil }
        return TurkishDateFormatter.relativeShort(to: anchor, now: now, calendar: AppTime.calendar)
    }

    private func doneText(_ item: Item) -> String {
        guard let completed = item.completedAt else { return "Tamamlandı" }
        return "Tamamlandı · " + TurkishDateFormatter.shortDateTime(completed, now: now, calendar: AppTime.calendar,
                                                                   includeTime: true)
    }

    private func recurrenceValue(_ item: Item) -> String {
        if let rule = item.recurrence {
            return TurkishDateFormatter.recurrenceText(rule)
        }
        return item.dueDate == nil ? "Önce zaman seç" : "Yok"
    }

    private func recurrenceChoices(due: Date) -> [RecurrenceChoice] {
        let calendar = AppTime.calendar
        let iso = AsistCalendar.isoWeekday(due, calendar: calendar)
        let comps = calendar.dateComponents([.month, .day], from: due)
        let day = comps.day ?? 1
        let month = comps.month ?? 1
        let weekdayNames = TurkishDateFormatter.weekdays
        let weekdayName = (iso >= 1 && iso <= weekdayNames.count) ? weekdayNames[iso - 1] : ""
        let monthNames = TurkishDateFormatter.months
        let monthName = (month >= 1 && month <= monthNames.count) ? monthNames[month - 1] : ""
        var result: [RecurrenceChoice] = []
        result.append(RecurrenceChoice(id: "daily", title: "Her gün",
                                       rule: Recurrence(frequency: .daily)))
        result.append(RecurrenceChoice(id: "weekdays", title: "Hafta içi her gün",
                                       rule: Recurrence(frequency: .weekly, weekdays: [1, 2, 3, 4, 5])))
        result.append(RecurrenceChoice(id: "weekly", title: "Her " + weekdayName,
                                       rule: Recurrence(frequency: .weekly, weekdays: [iso])))
        result.append(RecurrenceChoice(id: "biweekly", title: "İki haftada bir " + weekdayName,
                                       rule: Recurrence(frequency: .weekly, interval: 2, weekdays: [iso])))
        result.append(RecurrenceChoice(id: "monthly", title: "Her ayın " + TurkishDateFormatter.numeralPossessive(day),
                                       rule: Recurrence(frequency: .monthly, monthDay: day)))
        result.append(RecurrenceChoice(id: "yearly", title: "Her yıl " + String(day) + " " + monthName,
                                       rule: Recurrence(frequency: .yearly, monthDay: day, month: month)))
        return result
    }

    private func isLeadSelected(_ minutes: Int, item: Item) -> Bool {
        if minutes == 0 { return item.leadTimesMinutes.isEmpty }
        return item.leadTimesMinutes == [minutes]
    }

    private func leadValue(_ item: Item) -> String {
        if item.leadTimesMinutes.isEmpty { return "Yok" }
        let parts = item.leadTimesMinutes.map { TurkishDateFormatter.duration(minutes: $0) }
        return parts.joined(separator: ", ") + " önce"
    }

    private func autoNagLabel(_ item: Item) -> String {
        if item.isEvent { return NagProfileKind.etkinlik.label }
        return store.settings.profileKind(for: item.priority).label
    }

    private func nagValue(_ item: Item) -> String {
        if item.kind == .waiting { return NagProfileKind.takip.label }
        if let explicit = item.nagProfile, NagProfileKind.selectable.contains(explicit) {
            return explicit.label
        }
        return autoNagLabel(item) + (item.isEvent ? " (etkinlik)" : " (önceliğe göre)")
    }

    private func selectableProjects(current: UUID?) -> [Project] {
        let visible = store.projects.filter { !$0.archived || $0.id == current }
        return visible.sorted { lhs, rhs in
            TurkishText.searchKey(lhs.name) < TurkishText.searchKey(rhs.name)
        }
    }

    private func shareText(_ item: Item) -> String {
        let calendar = AppTime.calendar
        var lines: [String] = [item.title]
        if let due = item.dueDate {
            let when = TurkishDateFormatter.shortDateTime(due, now: now, calendar: calendar, includeTime: item.hasTime)
            lines.append(item.kind == .waiting ? "Son tarih: " + when : "Zaman: " + when)
        }
        if let person = item.person, !person.isEmpty {
            lines.append("Kişi / Firma: " + person)
        }
        if let projectName = store.projectName(for: item) {
            lines.append("Proje: " + projectName)
        }
        let trimmedNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            lines.append("")
            lines.append(trimmedNotes)
        }
        if !item.checklist.isEmpty {
            lines.append("")
            for entry in item.checklist {
                lines.append((entry.done ? "☑ " : "☐ ") + entry.text)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Drafts

    private func loadDrafts(_ item: Item) {
        guard !draftsLoaded else { return }
        titleDraft = item.title
        notesDraft = item.notes
        personDraft = item.person ?? ""
        isEventDraft = item.isEvent
        now = Date()
        draftsLoaded = true
    }

    private func commitAll() {
        commitTitle()
        commitNotes()
        commitPerson()
    }

    private func currentEditableItem() -> Item? {
        guard let item = store.item(itemID), item.status != .deleted else { return nil }
        return item
    }

    private func commitTitle() {
        guard draftsLoaded, let item = currentEditableItem() else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            titleDraft = item.title
            return
        }
        guard trimmed != item.title else { return }
        if store.update(itemID, event: .edited, { edited in
            edited.title = trimmed
        }) == nil {
            DetailItemActions.reportNil("başlık", store: store, toasts: toasts)
            titleDraft = item.title
        }
    }

    private func commitNotes() {
        guard draftsLoaded, let item = currentEditableItem() else { return }
        let text = notesDraft
        guard text != item.notes else { return }
        if store.update(itemID, event: nil, { edited in
            edited.notes = text
        }) == nil {
            DetailItemActions.reportNil("not", store: store, toasts: toasts)
        }
    }

    private func commitPerson() {
        guard draftsLoaded, let item = currentEditableItem() else { return }
        let trimmed = personDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        guard value != item.person else { return }
        if store.update(itemID, event: .edited, { edited in
            edited.person = value
        }) == nil {
            DetailItemActions.reportNil("kişi", store: store, toasts: toasts)
            personDraft = item.person ?? ""
        }
    }

    // MARK: - Mutations

    private func applyEdit(_ label: String, event: HistoryEvent?, _ mutate: (inout Item) -> Void) {
        guard currentEditableItem() != nil else { return }
        if store.update(itemID, event: event, mutate) == nil {
            DetailItemActions.reportNil(label, store: store, toasts: toasts)
        } else {
            Haptics.selection()
        }
    }

    private func setRecurrence(_ rule: Recurrence?) {
        guard let item = currentEditableItem(), item.recurrence != rule else { return }
        applyEdit("tekrar", event: .edited) { edited in
            edited.recurrence = rule
        }
    }

    private func setLeadTime(_ minutes: Int) {
        guard let item = currentEditableItem() else { return }
        let newValue: [Int] = minutes > 0 ? [minutes] : []
        guard item.leadTimesMinutes != newValue else { return }
        applyEdit("ön uyarı", event: .edited) { edited in
            edited.leadTimesMinutes = newValue
        }
    }

    private func setNagProfile(_ kind: NagProfileKind?) {
        guard let item = currentEditableItem(), item.nagProfile != kind else { return }
        applyEdit("ısrar düzeyi", event: .edited) { edited in
            edited.nagProfile = kind
        }
    }

    private func setEvent(_ value: Bool) {
        guard let item = currentEditableItem(), item.isEvent != value else { return }
        let lead = store.settings.eventDefaultLeadMinutes
        if store.update(itemID, event: .edited, { edited in
            edited.isEvent = value
            if value && edited.leadTimesMinutes.isEmpty && lead > 0 {
                edited.leadTimesMinutes = [lead]
            }
        }) == nil {
            DetailItemActions.reportNil("etkinlik", store: store, toasts: toasts)
            isEventDraft = item.isEvent
        } else {
            Haptics.selection()
        }
    }

    private func setKind(_ kind: ItemKind) {
        guard let item = currentEditableItem(), item.kind != kind else { return }
        let settings = store.settings
        let calendar = AppTime.calendar
        let at = Date()
        applyEdit("tür", event: .edited) { edited in
            edited.kind = kind
            if kind == .waiting && edited.dueDate == nil {
                edited.dueDate = ItemFactory.defaultWaitingDue(now: at, settings: settings, calendar: calendar)
                edited.hasTime = false
            }
            if kind == .note || kind == .waiting {
                edited.isEvent = false
            }
        }
    }

    private func setPriority(_ priority: Priority) {
        guard let item = currentEditableItem(), item.priority != priority else { return }
        applyEdit("öncelik", event: .edited) { edited in
            edited.priority = priority
        }
    }

    private func setProject(_ projectID: UUID?) {
        guard let item = currentEditableItem(), item.projectID != projectID else { return }
        applyEdit("proje", event: .edited) { edited in
            edited.projectID = projectID
        }
    }

    private func clearDue() {
        guard let item = currentEditableItem(), item.dueDate != nil else { return }
        applyEdit("zamanı kaldır", event: .rescheduled) { edited in
            edited.dueDate = nil
            edited.hasTime = false
            edited.recurrence = nil
            edited.leadTimesMinutes = []
            edited.resetNagState()
        }
    }

    private func completeItem(_ item: Item) {
        commitAll()
        focusedField = nil
        let result = DetailItemActions.markDone(item.id, store: store, toasts: toasts)
        if case .some(.completed) = result {
            dismiss()
        }
    }

    private func deleteItem() {
        focusedField = nil
        DetailItemActions.delete(itemID, store: store, toasts: toasts)
        if let item = store.item(itemID), item.status == .deleted {
            dismiss()
        }
    }

    private func duplicate(_ item: Item) {
        commitAll()
        let at = Date()
        let freshChecklist: [ChecklistEntry] = item.checklist.map { entry in
            ChecklistEntry(text: entry.text, done: false)
        }
        let createdEntry = HistoryEntry(date: at, event: .created, detail: "çoğaltıldı")
        let copy = Item(kind: item.kind,
                        title: item.title,
                        notes: item.notes,
                        originalText: item.originalText,
                        priority: item.priority,
                        dueDate: item.dueDate,
                        hasTime: item.hasTime,
                        recurrence: item.recurrence,
                        leadTimesMinutes: item.leadTimesMinutes,
                        nagProfile: item.nagProfile,
                        isEvent: item.isEvent,
                        person: item.person,
                        projectID: item.projectID,
                        tags: item.tags,
                        checklist: freshChecklist,
                        source: .other,
                        createdAt: at,
                        history: [createdEntry])
        guard let token = store.add(copy) else {
            DetailItemActions.reportNil("çoğalt", store: store, toasts: toasts)
            return
        }
        toasts.show("Kopyası oluşturuldu", undo: token)
        Haptics.success()
    }
}
