// API: App/UI/Today/CalendarTodaySection.swift
// Revision 4 — F7 (07 §10.1, §10.4): List content for Bugün, placed after "BUGÜN" — the "TAKVİM" section with
// today's events, the one-time "Toplantıların Bugün'de görünsün" card, or nothing. "15 dk önce" creates an Asist
// event item (R4-D8); the calendar itself is never written.
import SwiftUI
import AsistCore

struct CalendarTodaySection: View {
    let now: Date

    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    /// Key of `AppMeta.dismissedBanners` for the opt-in card ("Şimdi değil").
    static let optInBannerID = "calendar_optin"

    init(now: Date) {
        self.now = now
    }

    var body: some View {
        let service = CalendarService.shared
        let access = service.access
        let settings = store.settings
        if settings.calendarOnToday {
            if access == .granted {
                eventsSection(events: todaysEvents(service.todayEvents), items: store.items,
                              lead: settings.calendarLeadMinutes)
            } else if access == .notDetermined && !isOptInDismissed(store.meta) {
                optInSection
            }
        }
    }

    // MARK: - Events

    /// Events overlapping `now`'s day (the service list may still be yesterday's until it refreshes).
    private func todaysEvents(_ events: [CalendarEventInfo]) -> [CalendarEventInfo] {
        let calendar = AppTime.calendar
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = AsistCalendar.addingDays(1, to: dayStart, calendar: calendar)
        return events.filter { event in
            event.start < dayEnd && (event.end > dayStart || (event.end == event.start && event.start >= dayStart))
        }
    }

    @ViewBuilder
    private func eventsSection(events: [CalendarEventInfo], items: [Item], lead: Int) -> some View {
        if !events.isEmpty {
            Section {
                ForEach(events) { event in
                    eventRow(event, items: items, lead: lead)
                }
            } header: {
                SectionHeader(title: "TAKVİM", count: events.count, color: Color.teal)
            }
        }
    }

    private func eventRow(_ event: CalendarEventInfo, items: [Item], lead: Int) -> some View {
        let calendar = AppTime.calendar
        let dayStart = calendar.startOfDay(for: now)
        let range = CalendarReminderRules.displayRange(start: event.start, end: event.end, isAllDay: event.isAllDay,
                                                       dayStart: dayStart, calendar: calendar)
        let isPast = !event.isAllDay && event.end <= now
        let hasReminder = CalendarReminderRules.hasReminder(items: items, eventKey: event.id)
        let canRemind = CalendarReminderRules.canRemind(start: event.start, isAllDay: event.isAllDay, now: now)
        let title = event.title.isEmpty ? "Başlıksız etkinlik" : event.title
        let leadText = CalendarSettingsText.leadLabel(lead)
        return HStack(alignment: .center, spacing: Metrics.cardSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(range)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isPast ? Color.secondary : Color.teal)
                Text(title)
                    .font(.body)
                    .foregroundStyle(isPast ? Color.secondary : Color.primary)
                    .lineLimit(2)
                if let location = event.location {
                    Text(location)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if hasReminder {
                Label("Kuruldu", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.asistDone)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Hatırlatma kuruldu")
            } else if canRemind {
                Button {
                    createReminder(event, lead: lead)
                } label: {
                    Label(leadText + " önce", systemImage: "bell.badge")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.teal)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color.teal.opacity(0.15)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Toplantıdan " + leadText + " önce hatırlat")
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 2)
    }

    // MARK: - Opt-in card

    private func isOptInDismissed(_ meta: AppMeta) -> Bool {
        guard let hiddenUntil = meta.dismissedBanners[CalendarTodaySection.optInBannerID] else { return false }
        return hiddenUntil > now
    }

    private var optInSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: Metrics.cardSpacing) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(Color.teal)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Toplantıların Bugün'de görünsün")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Takvimini yalnızca okurum; istersen toplantıdan önce hatırlatırım. Takvimine hiçbir şey yazmam.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        dismissOptIn()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Şimdi değil")
                }
                Button {
                    requestAccess()
                } label: {
                    Text("Takvime eriş")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: Metrics.primaryButtonHeight)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                                .fill(Color.teal)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Actions

    @MainActor
    private func requestAccess() {
        Task { @MainActor in
            let granted = await CalendarService.shared.requestAccess()
            if granted {
                Haptics.success()
            }
        }
    }

    @MainActor
    private func dismissOptIn() {
        let until = Date().addingTimeInterval(3650 * 86_400)
        store.updateMeta { meta in
            meta.dismissedBanners[CalendarTodaySection.optInBannerID] = until
        }
        Haptics.selection()
    }

    /// CalendarReminderRules.makeItem → store.add → toast "Hatırlatma kuruldu · 09:45" with Geri Al.
    @MainActor
    private func createReminder(_ event: CalendarEventInfo, lead: Int) {
        let now = Date()
        let calendar = AppTime.calendar
        guard CalendarReminderRules.canRemind(start: event.start, isAllDay: event.isAllDay, now: now) else {
            toasts.show("Toplantı başlamak üzere; hatırlatma kurulmadı.")
            Haptics.warning()
            return
        }
        guard !CalendarReminderRules.hasReminder(items: store.items, eventKey: event.id) else { return }
        let item = CalendarReminderRules.makeItem(title: event.title, start: event.start, end: event.end,
                                                  location: event.location, eventKey: event.id, leadMinutes: lead,
                                                  now: now, calendar: calendar)
        guard let token = store.add(item) else {
            DetailItemActions.reportNil("takvim hatırlatması", store: store, toasts: toasts)
            return
        }
        let alert = CalendarReminderRules.alertTime(start: event.start, leadMinutes: lead, now: now)
        toasts.show("Hatırlatma kuruldu · " + TurkishDateFormatter.time(alert, calendar: calendar), undo: token)
        Haptics.success()
        AsistLog.info("Takvim: toplantı hatırlatması kuruldu (ön uyarı " + String(lead) + " dk)", .app)
    }
}
