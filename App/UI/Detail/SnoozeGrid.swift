// WP10 — Erteleme ızgarası (03 §3.6, §4.8; 05b D5 "Sesle ertele").
import SwiftUI
import AsistCore

/// 2×3 snooze chips + full-width "Sesle ertele". Waiting (Takip) items get the follow-up choices instead
/// ("Yarın tekrar sor", "2 gün sonra", "Pazartesi", "Tarih seç…"), matching the notification actions (04 §6.3).
@MainActor
struct SnoozeGrid: View {
    let item: Item
    let now: Date

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(VoiceCoordinator.self) private var voice

    private enum GridAction: Hashable {
        case option(SnoozeOption)
        case followUp(Int)
        case monday
        case custom
    }

    private struct GridEntry: Identifiable {
        let id: String
        let title: String
        let action: GridAction
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: Metrics.chipSpacing),
        GridItem(.flexible(), spacing: Metrics.chipSpacing),
        GridItem(.flexible(), spacing: Metrics.chipSpacing)
    ]

    /// Explicit: private @Environment storage must not narrow the memberwise initializer's access level.
    init(item: Item, now: Date) {
        self.item = item
        self.now = now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.chipSpacing) {
            if item.snoozeCount >= 3 {
                Label("Birkaç kez ertelendi. Başka bir gün mü?", systemImage: Symbol.snooze)
                    .font(.subheadline)
                    .foregroundStyle(Color.asistToday)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.chipSpacing) {
                ForEach(entries()) { entry in
                    Chip(title: entry.title) {
                        perform(entry.action)
                    }
                }
            }
            Button {
                startVoiceSnooze()
            } label: {
                Label("Sesle ertele", systemImage: Symbol.voiceSnooze)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Metrics.chipHeight)
                    .background(Color.asistAccent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            }
            .accessibilityHint("Yeni zamanı söyle, örneğin perşembe saat on")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private func entries() -> [GridEntry] {
        var result: [GridEntry] = []
        if item.kind == .waiting {
            result.append(GridEntry(id: "fu1", title: "Yarın tekrar sor", action: .followUp(1)))
            result.append(GridEntry(id: "fu2", title: "2 gün sonra", action: .followUp(2)))
            result.append(GridEntry(id: "monday", title: "Pazartesi", action: .monday))
            result.append(GridEntry(id: "custom", title: SnoozeOption.custom.title, action: .custom))
            return result
        }
        let options: [SnoozeOption] = [.min30, .hour1, .thisEvening, .tomorrowMorning, .monday, .custom]
        let settings = store.settings
        let calendar = AppTime.calendar
        for option in options {
            if option == .thisEvening && option.target(now: now, settings: settings, calendar: calendar) == nil {
                continue   // hidden after 18:30 (03 §3.6)
            }
            let action: GridAction = option == .custom ? .custom : .option(option)
            result.append(GridEntry(id: option.id, title: option.title, action: action))
        }
        return result
    }

    private func perform(_ action: GridAction) {
        let at = Date()
        let settings = store.settings
        let calendar = AppTime.calendar
        var target: Date?
        switch action {
        case .option(let option):
            target = option.target(now: at, settings: settings, calendar: calendar)
        case .followUp(let workdays):
            target = NagPlanner.followUpAsk(after: at, workdays: workdays, settings: settings, calendar: calendar)
        case .monday:
            target = NagPlanner.nextMonday(now: at, settings: settings, calendar: calendar)
        case .custom:
            router.present(.datePicker(DatePickerRequest(itemID: item.id, purpose: .snooze)))
            return
        }
        guard let date = target else {
            toasts.show("Bu seçenek için artık geç; başka bir zaman seç.")
            Haptics.warning()
            return
        }
        DetailItemActions.snooze(item.id, until: date, store: store, toasts: toasts)
    }

    private func startVoiceSnooze() {
        let request = ListenRequest(snoozeItemID: item.id)
        Task {
            await voice.startListening(request)
        }
    }
}
