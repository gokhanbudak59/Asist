// WP9 (04 §5.2; 03 §4.3, §7.5; 05b D5): "Şimdi ilgilen" card for the first overdue item.
// Four 56 pt buttons ✓ Yaptım / 10 dk / 1 saat / Yarın (store + undo toast + haptic) and the "Sesle ertele" chip
// (next utterance = new time for this item). Tapping the title opens the detail.
import SwiftUI
import AsistCore

struct HeroCard: View {
    let item: Item
    let projectName: String?
    let now: Date

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(VoiceCoordinator.self) private var voice
    @Environment(ToastCenter.self) private var toasts

    init(item: Item, projectName: String?, now: Date) {
        self.item = item
        self.projectName = projectName
        self.now = now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Şimdi ilgilen", systemImage: Symbol.overdue)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.asistOverdue)
                .textCase(nil)
            Button {
                router.todayPath.append(Route.item(item.id))
            } label: {
                titleBlock
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ayrıntıları açar")
            Button {
                ItemQuickActions.complete(item.id, store: store, toasts: toasts)
            } label: {
                Label(item.kind == .waiting ? "Geldi" : "Yaptım", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Color.asistDone))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    snoozeButtons
                }
                VStack(spacing: 10) {
                    snoozeButtons
                }
            }
            Chip(title: "Sesle ertele", systemImage: Symbol.voiceSnooze) {
                ItemQuickActions.voiceSnooze(item.id, voice: voice)
            }
            .accessibilityHint("Yeni zamanı söyle, örneğin perşembe 10'da")
        }
        .padding(.vertical, Metrics.padding)
        .padding(.trailing, Metrics.padding)
        .padding(.leading, Metrics.padding + 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            Rectangle()
                .fill(Color.asistOverdue)
                .frame(width: 6)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: item.isEvent ? Symbol.event : item.kind.symbol)
                    .foregroundStyle(Color.asistOverdue)
                    .accessibilityHidden(true)
                Text(item.title.isEmpty ? "Başlıksız" : item.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
            }
            PriorityBadge(priority: item.priority)
            Text(ItemRowText.detailLine(for: item, projectName: projectName, now: now, calendar: AppTime.calendar))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.asistOverdue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var snoozeButtons: some View {
        snoozeButton(.min10, title: "10 dk")
        snoozeButton(.hour1, title: "1 saat")
        snoozeButton(.tomorrowMorning, title: "Yarın")
    }

    private func snoozeButton(_ option: SnoozeOption, title: String) -> some View {
        Button {
            ItemQuickActions.snooze(item.id, option: option, store: store, toasts: toasts, router: router)
        } label: {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(PrimaryButtonStyle(tint: Color.asistToday, filled: false))
        .accessibilityLabel(title + " ertele")
    }
}
