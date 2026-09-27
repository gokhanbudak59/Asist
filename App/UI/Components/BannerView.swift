// WP9 (04 §5.3, signature frozen; 03 §7.5, §9): one warning band — symbol + one sentence + one action button;
// dismissible bands get an × (permission/data problems are not dismissible, PermissionCenter decides).
import SwiftUI

struct BannerView: View {
    let banner: AppBanner
    let onAction: () -> Void
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.cardSpacing) {
            Image(systemName: banner.severity == .red ? Symbol.overdue : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(banner.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle = banner.actionTitle, banner.action != .none {
                    Button(action: onAction) {
                        Text(actionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(accent.opacity(0.22)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if banner.dismissible, let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Kapat")
            }
        }
        .padding(Metrics.padding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(accent.opacity(banner.severity == .red ? 0.14 : 0.2))
        )
        .accessibilityElement(children: .contain)
    }

    private var accent: Color {
        banner.severity == .red ? Color.asistOverdue : Color.asistReview
    }
}
