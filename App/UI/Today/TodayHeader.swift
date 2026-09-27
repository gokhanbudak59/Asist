// WP9 (04 §5.2; 03 §4.3, §7.12 home.*): date line "27 Eylül Pazar", greeting by hour (+ ", <hitap>") and the
// counter chips "2 geciken" / "5 bugün" / "1 takip" that open Listeler with the matching filter.
import SwiftUI
import AsistCore

struct TodayHeader: View {
    let now: Date
    let snapshot: AgendaSnapshot
    let userName: String

    @Environment(AppRouter.self) private var router

    init(now: Date, snapshot: AgendaSnapshot, userName: String) {
        self.now = now
        self.snapshot = snapshot
        self.userName = userName
    }

    var body: some View {
        let calendar = AppTime.calendar
        VStack(alignment: .leading, spacing: 8) {
            Text(TodayDateText.dayMonthWeekday(now, calendar: calendar))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Text(greetingLine(calendar: calendar))
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if hasStats {
                ChipRow {
                    if snapshot.overdue.count > 0 {
                        StatChip(title: String(snapshot.overdue.count) + " geciken", color: Color.asistOverdue) {
                            openList(for: snapshot.overdue)
                        }
                    }
                    if snapshot.today.count > 0 {
                        StatChip(title: String(snapshot.today.count) + " bugün", color: Color.asistToday) {
                            openList(for: snapshot.today)
                        }
                    }
                    if snapshot.followUps.count > 0 {
                        StatChip(title: String(snapshot.followUps.count) + " takip", color: Color.asistFollowUp) {
                            router.listFilter = .followUps
                            router.selectedTab = .lists
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var hasStats: Bool {
        snapshot.overdue.count > 0 || snapshot.today.count > 0 || snapshot.followUps.count > 0
    }

    private func greetingLine(calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: now)
        let greeting = TodayDateText.greeting(hour: hour)
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? greeting : greeting + ", " + name
    }

    /// Lists has no "geciken" filter: open the kind most of these items have (reminders / tasks / takip).
    @MainActor
    private func openList(for items: [Item]) {
        var reminders = 0
        var tasks = 0
        var waiting = 0
        for item in items {
            switch item.kind {
            case .reminder: reminders += 1
            case .task: tasks += 1
            case .waiting: waiting += 1
            case .note: break
            }
        }
        let filter: ListFilter
        if waiting > reminders && waiting > tasks {
            filter = .followUps
        } else if tasks > reminders {
            filter = .tasks
        } else {
            filter = .reminders
        }
        router.listFilter = filter
        router.selectedTab = .lists
    }
}

/// Turkish date texts for Today and the capture card (tables from TurkishDateFormatter, no DateFormatter).
enum TodayDateText {
    /// "27 Eylül Pazar"
    static func dayMonthWeekday(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        let monthIndex = min(11, max(0, (components.month ?? 1) - 1))
        let weekdayIndex = min(6, max(0, AsistCalendar.isoWeekday(date, calendar: calendar) - 1))
        return String(components.day ?? 1) + " " + TurkishDateFormatter.months[monthIndex] + " "
            + TurkishDateFormatter.weekdays[weekdayIndex]
    }

    /// "bugün", "yarın", "öbür gün", "5 gün sonra", "dün", "3 gün önce".
    static func relativeDays(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = ItemRowText.dayDistance(from: now, to: date, calendar: calendar)
        switch days {
        case 0: return "bugün"
        case 1: return "yarın"
        case 2: return "öbür gün"
        case -1: return "dün"
        default:
            return days > 0 ? String(days) + " gün sonra" : String(-days) + " gün önce"
        }
    }

    /// 04 §5.2: Günaydın < 12, İyi günler < 18, İyi akşamlar < 22, else İyi geceler.
    /// DEVIATION(04 §5.2): 00:00–04:59 also says "İyi geceler" ("Günaydın" at 02:00 reads as a bug).
    static func greeting(hour: Int) -> String {
        if hour < 5 { return "İyi geceler" }
        if hour < 12 { return "Günaydın" }
        if hour < 18 { return "İyi günler" }
        if hour < 22 { return "İyi akşamlar" }
        return "İyi geceler"
    }
}
