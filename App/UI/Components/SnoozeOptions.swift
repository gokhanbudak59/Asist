// WP9 (04 §5.3, signature frozen; 03 §3.6, §7.12 detail.snooze.*): `SnoozeOption` (declared only here), the shared
// snooze menu content, and the quick item actions (done / snooze / delete / "Sesle ertele") used by the Today rows,
// the hero card and the capture sheets. Every action persists synchronously through DataStore and reports with a
// toast (+ undo) and a haptic; the UI never claims success when the store refused the change (05a #3).
import Foundation
import SwiftUI
import AsistCore

enum SnoozeOption: String, CaseIterable, Identifiable {
    case min10, min30, hour1, hour2, thisEvening, tomorrowMorning, monday, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .min10: return "10 dk"
        case .min30: return "30 dk"
        case .hour1: return "1 saat"
        case .hour2: return "2 saat"
        case .thisEvening: return "Bu akşam"
        case .tomorrowMorning: return "Yarın sabah"
        case .monday: return "Pazartesi"
        case .custom: return "Tarih seç…"
        }
    }

    var systemImage: String {
        switch self {
        case .min10, .min30, .hour1, .hour2: return "clock"
        case .thisEvening: return "moon"
        case .tomorrowMorning: return Symbol.briefing
        case .monday: return "calendar"
        case .custom: return "calendar.badge.clock"
        }
    }

    /// nil for .custom, and for .thisEvening after 18:30 (or when "akşam" has already passed).
    /// Uses NagPlanner helpers; results ceil to the minute.
    func target(now: Date, settings: AppSettings, calendar: Calendar) -> Date? {
        switch self {
        case .min10:
            return AsistCalendar.ceilToMinute(now.addingTimeInterval(10 * 60))
        case .min30:
            return AsistCalendar.ceilToMinute(now.addingTimeInterval(30 * 60))
        case .hour1:
            return AsistCalendar.ceilToMinute(now.addingTimeInterval(60 * 60))
        case .hour2:
            return AsistCalendar.ceilToMinute(now.addingTimeInterval(2 * 60 * 60))
        case .thisEvening:
            guard let evening = NagPlanner.thisEvening(now: now, settings: settings, calendar: calendar) else {
                return nil
            }
            let rounded = AsistCalendar.ceilToMinute(evening)
            return rounded > now ? rounded : nil
        case .tomorrowMorning:
            return AsistCalendar.ceilToMinute(NagPlanner.tomorrowMorning(after: now, settings: settings, calendar: calendar))
        case .monday:
            return AsistCalendar.ceilToMinute(NagPlanner.nextMonday(now: now, settings: settings, calendar: calendar))
        case .custom:
            return nil
        }
    }

    /// Menu order (rows, hero overflow, detail). `.custom` is always offered.
    static let menuOrder: [SnoozeOption] = [.min10, .min30, .hour1, .hour2, .thisEvening, .tomorrowMorning, .monday,
                                            .custom]

    /// Options that currently have a target (plus `.custom`).
    static func available(now: Date, settings: AppSettings, calendar: Calendar) -> [SnoozeOption] {
        var result: [SnoozeOption] = []
        for option in menuOrder {
            if option == .custom || option.target(now: now, settings: settings, calendar: calendar) != nil {
                result.append(option)
            }
        }
        return result
    }

    /// "Yarın sabah · 08:30" for the fixed-clock options, plain title otherwise.
    func menuTitle(now: Date, settings: AppSettings, calendar: Calendar) -> String {
        switch self {
        case .thisEvening, .tomorrowMorning, .monday:
            guard let date = target(now: now, settings: settings, calendar: calendar) else { return title }
            return title + " · " + TurkishDateFormatter.time(date, calendar: calendar)
        case .min10, .min30, .hour1, .hour2, .custom:
            return title
        }
    }
}

/// Buttons for a `Menu` or `confirmationDialog` (one per available option).
struct SnoozeMenuContent: View {
    let now: Date
    let settings: AppSettings
    let onSelect: (SnoozeOption) -> Void

    var body: some View {
        ForEach(SnoozeOption.available(now: now, settings: settings, calendar: AppTime.calendar)) { option in
            Button {
                onSelect(option)
            } label: {
                Label(option.menuTitle(now: now, settings: settings, calendar: AppTime.calendar),
                      systemImage: option.systemImage)
            }
        }
    }
}

/// One-tap item actions shared by Today rows, HeroCard, AgendaAnswerSheet and row accessibility actions.
@MainActor
enum ItemQuickActions {
    static let saveFailedText = "Kaydedilemedi. Lütfen tekrar dene."

    /// ✓ Yaptım / ✓ Geldi. Recurring → next occurrence ("Bu seferlik tamamlandı · Sıradaki: …").
    static func complete(_ id: UUID, store: DataStore, toasts: ToastCenter) {
        let now = Date()
        let calendar = AppTime.calendar
        let showsClock = store.item(id)?.hasTime ?? true
        guard let outcome = store.markDone(id, at: now), store.canPersist else {
            reportFailure(id, store: store, toasts: toasts, action: "tamamlama")
            return
        }
        switch outcome.0 {
        case .completed:
            toasts.show("Tamamlandı", undo: outcome.1)
        case .nextOccurrence(let next):
            let when = TurkishDateFormatter.shortDateTime(next, now: now, calendar: calendar, includeTime: showsClock)
            toasts.show("Bu seferlik tamamlandı · Sıradaki: " + when, undo: outcome.1)
        }
        Haptics.success()
    }

    /// Snooze to a preset; `.custom` opens the date picker sheet.
    static func snooze(_ id: UUID, option: SnoozeOption, store: DataStore, toasts: ToastCenter, router: AppRouter) {
        let now = Date()
        let calendar = AppTime.calendar
        if option == .custom {
            router.present(.datePicker(DatePickerRequest(itemID: id, purpose: .snooze)))
            return
        }
        guard let target = option.target(now: now, settings: store.settings, calendar: calendar) else {
            toasts.show("Bu seçenek şu an kullanılamıyor.")
            Haptics.warning()
            return
        }
        guard let token = store.snooze(id, until: target, at: now), store.canPersist else {
            reportFailure(id, store: store, toasts: toasts, action: "erteleme")
            return
        }
        let when = TurkishDateFormatter.shortDateTime(target, now: now, calendar: calendar, includeTime: true)
        toasts.show("Ertelendi · " + when, undo: token)
        Haptics.success()
    }

    /// Soft delete with undo (30 days in "Son silinenler").
    static func delete(_ id: UUID, store: DataStore, toasts: ToastCenter) {
        guard let token = store.delete(id, at: Date()), store.canPersist else {
            reportFailure(id, store: store, toasts: toasts, action: "silme")
            return
        }
        toasts.show("Silindi", undo: token)
        Haptics.success()
    }

    /// "Doğru" on an "Emin değilim" record (05b D8): clears the flag only.
    static func confirmReview(_ id: UUID, store: DataStore, toasts: ToastCenter) {
        guard let token = store.update(id, event: .edited, { item in item.needsReview = false }), store.canPersist else {
            reportFailure(id, store: store, toasts: toasts, action: "onaylama")
            return
        }
        toasts.show("Onaylandı", undo: token)
        Haptics.success()
    }

    /// "Sesle ertele" (05b D5): the next utterance is a new time for this item, never a new capture.
    static func voiceSnooze(_ id: UUID, voice: VoiceCoordinator) {
        Task { @MainActor in
            await voice.startListening(ListenRequest(snoozeItemID: id))
        }
    }

    private static func reportFailure(_ id: UUID, store: DataStore, toasts: ToastCenter, action: String) {
        if let item = store.item(id), item.isOpen {
            toasts.show(store.lastSaveError ?? saveFailedText, seconds: 6)
            AsistLog.error("Hızlı eylem kaydedilemedi (" + action + ")", .ui)
        } else {
            toasts.show("Bu kayıt artık açık değil.")
            AsistLog.info("Hızlı eylem: kayıt bulunamadı/kapalı (" + action + ")", .ui)
        }
        Haptics.error()
    }
}
