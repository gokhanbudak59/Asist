// WP0 STUB (04 §5.3, signatures frozen) — replaced by WP9 ("Mesai sonuna kadar" via NagPlanner.muteUntilWorkEnd).
import SwiftUI
import AsistCore

struct MuteMenu: View {
    @Environment(DataStore.self) private var store

    var body: some View {
        Menu {
            Button("30 dk") { mute(minutes: 30) }
            Button("1 saat") { mute(minutes: 60) }
            Button("2 saat") { mute(minutes: 120) }
        } label: {
            Image(systemName: Symbol.mute)
        }
        .accessibilityLabel("Sessize al")
    }

    @MainActor
    private func mute(minutes: Int) {
        let until = AsistCalendar.ceilToMinute(Date().addingTimeInterval(TimeInterval(minutes * 60)))
        store.updateSettings { settings in
            settings.muteUntil = until
        }
    }
}

struct MuteBanner: View {
    let until: Date
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Metrics.cardSpacing) {
            Image(systemName: Symbol.mute)
            Text("Sessiz: " + until.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Sessizi kapat")
        }
    }
}
