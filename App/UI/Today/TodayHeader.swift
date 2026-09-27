// WP0 STUB (04 §5.2) — replaced by WP9.
import SwiftUI
import AsistCore

struct TodayHeader: View {
    let now: Date
    let snapshot: AgendaSnapshot
    let userName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(date: .complete, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(userName.isEmpty ? "Merhaba" : "Merhaba, " + userName)
                .font(.title2.weight(.semibold))
        }
    }
}
