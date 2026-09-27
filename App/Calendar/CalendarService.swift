// API: App/Calendar/CalendarService.swift
// Revision 4 — F7 (07 §10.3, R4-D8): read-only EventKit access for the Bugün "TAKVİM" section. The only
// `import EventKit` in the project (§2.2 r59). Never writes to the calendar and never asks for write access;
// prompts only from requestAccess() (a button tap). Logs access states and event COUNTS only — never titles,
// locations or identifiers (§2.3). Lazy singleton whose init never touches AppEnvironment.shared (R4-D10).
import Foundation
import Observation
import UIKit                 // UIApplication.significantTimeChangeNotification
import EventKit
import AsistCore

enum CalendarAccess: Equatable {
    case notDetermined, granted, denied, restricted, writeOnly

    var userText: String {
        switch self {
        case .granted: return "Tam erişim"
        case .notDetermined: return "Henüz sorulmadı"
        case .denied: return "Kapalı"
        case .restricted: return "Kısıtlı"
        case .writeOnly: return "Yalnız ekleme izni var — okuma kapalı"
        }
    }

    /// Content-free name for AsistLog.
    var logName: String {
        switch self {
        case .granted: return "tam erişim"
        case .notDetermined: return "sorulmadı"
        case .denied: return "reddedildi"
        case .restricted: return "kısıtlı"
        case .writeOnly: return "yalnız yazma"
        }
    }
}

struct CalendarEventInfo: Identifiable, Equatable {
    /// CalendarReminderRules.eventKey(identifier: eventIdentifier ?? calendarItemIdentifier, start:, calendar:)
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
}

@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    /// Upper bound of events kept for one day (a shared team calendar must not flood Bugün).
    static let maxEventsPerDay = 40

    private(set) var access: CalendarAccess = .notDetermined
    private(set) var todayEvents: [CalendarEventInfo] = []

    @ObservationIgnored private var eventStore: EKEventStore? = nil
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastLoggedCount: Int = -1

    init() {}

    /// Reads authorization; registers once for .EKEventStoreChanged, .NSCalendarDayChanged and
    /// UIApplication.significantTimeChangeNotification (→ refresh). Loads events only when granted. Never prompts.
    func start() {
        if observers.isEmpty {
            let center = NotificationCenter.default
            let names: [Notification.Name] = [.EKEventStoreChanged, .NSCalendarDayChanged,
                                              UIApplication.significantTimeChangeNotification]
            for name in names {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    Task { @MainActor in
                        CalendarService.shared.refresh(now: Date())
                    }
                }
                observers.append(token)
            }
        }
        refresh(now: Date())
    }

    /// requestFullAccessToEvents() (iOS 17); granted → the pre-grant EKEventStore is dropped so the next read uses a
    /// fresh one (an instance created before the grant may return no calendars, 07 §15), then refresh. Errors are
    /// logged (.app) and return false.
    func requestAccess() async -> Bool {
        let store = currentStore()
        do {
            let granted = try await store.requestFullAccessToEvents()
            AsistLog.info("Takvim erişimi istendi: " + (granted ? "verildi" : "verilmedi"), .app)
            if granted {
                eventStore = nil
            }
            refresh(now: Date())
            return granted
        } catch {
            let described = error as NSError
            AsistLog.error("Takvim erişimi istenemedi: " + described.domain + " " + String(described.code), .app)
            refresh(now: Date())
            return false
        }
    }

    /// Access re-read; granted → events of [startOfDay(now), +1 day) from all event calendars (cancelled ones
    /// skipped), sorted all-day first, then start, then title; else [].
    func refresh(now: Date) {
        let status = CalendarService.readAccess()
        let previous = access
        if status != previous {
            access = status
            AsistLog.info("Takvim izni: " + status.logName, .app)
            if status == .granted {
                // Granted just now (button or iOS Settings): never read through a store created before the grant.
                eventStore = nil
            }
        }
        guard status == .granted else {
            if !todayEvents.isEmpty {
                todayEvents = []
            }
            return
        }
        let events = loadEvents(now: now, store: currentStore())
        if events != todayEvents {
            todayEvents = events
        }
        if events.count != lastLoggedCount {
            lastLoggedCount = events.count
            AsistLog.info("Takvim: bugün " + String(events.count) + " etkinlik", .app)
        }
    }

    // MARK: - Private

    private func currentStore() -> EKEventStore {
        if let existing = eventStore {
            return existing
        }
        let created = EKEventStore()
        eventStore = created
        return created
    }

    private func loadEvents(now: Date, store: EKEventStore) -> [CalendarEventInfo] {
        let calendar = AppTime.calendar
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = AsistCalendar.addingDays(1, to: dayStart, calendar: calendar)
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        var seen = Set<String>()
        var result: [CalendarEventInfo] = []
        for event in store.events(matching: predicate) {
            if event.status == .canceled {
                continue
            }
            guard let start = event.startDate, let end = event.endDate else { continue }
            let identifier: String = event.eventIdentifier ?? event.calendarItemIdentifier
            let key = CalendarReminderRules.eventKey(identifier: identifier, start: start, calendar: calendar)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            let title = CalendarService.singleLine(event.title ?? "")
            let place = CalendarService.singleLine(event.location ?? "")
            result.append(CalendarEventInfo(id: key, title: title, start: start, end: max(start, end),
                                            isAllDay: event.isAllDay, location: place.isEmpty ? nil : place))
        }
        result.sort { a, b in
            if a.isAllDay != b.isAllDay {
                return a.isAllDay
            }
            if a.start != b.start {
                return a.start < b.start
            }
            return a.title < b.title
        }
        if result.count > CalendarService.maxEventsPerDay {
            return Array(result.prefix(CalendarService.maxEventsPerDay))
        }
        return result
    }

    private static func singleLine(_ raw: String) -> String {
        raw.components(separatedBy: CharacterSet.newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// EKEventStore.authorizationStatus(for: .event) → CalendarAccess (`default:` covers the deprecated
    /// `.authorized` alias and future cases, §2.2 r57).
    private static func readAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .granted
        case .writeOnly:
            return .writeOnly
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        default:
            return .denied
        }
    }
}
