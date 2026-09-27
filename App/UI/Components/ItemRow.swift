// WP0 STUB (04 §5.3, signature frozen) — replaced by WP9.
import SwiftUI
import AsistCore

struct ItemRow: View {
    let item: Item
    let projectName: String?
    let now: Date
    let onToggleDone: () -> Void          // 44 pt circle (28 pt visual)

    var body: some View {
        HStack(spacing: Metrics.cardSpacing) {
            Rectangle()
                .fill(item.statusColor(now: now, calendar: AppTime.calendar))
                .frame(width: Metrics.stripeWidth)
            Button(action: onToggleDone) {
                Image(systemName: item.status == .done ? Symbol.taskDone : Symbol.task)
                    .font(.system(size: Metrics.completionVisual))
                    .frame(width: Metrics.completionHitArea, height: Metrics.completionHitArea)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Yaptım")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                if let projectName = projectName {
                    Text(projectName)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metrics.rowMinHeight)
    }
}
