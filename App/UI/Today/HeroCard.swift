// WP0 STUB (04 §5.2) — replaced by WP9.
import SwiftUI
import AsistCore

struct HeroCard: View {
    let item: Item
    let projectName: String?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Şimdi ilgilen")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.asistOverdue)
            Text(item.title)
                .font(.title2.weight(.semibold))
            if let projectName = projectName {
                Text(projectName)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(Metrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.asistCard, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
    }
}
