// WP0 STUB (04 §5.3, signature frozen) — replaced by WP9.
import SwiftUI

struct BannerView: View {
    let banner: AppBanner
    let onAction: () -> Void
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: Metrics.cardSpacing) {
            Text(banner.text)
                .font(.subheadline)
            Spacer(minLength: 0)
            if let actionTitle = banner.actionTitle {
                Button(actionTitle, action: onAction)
                    .font(.subheadline.weight(.semibold))
            }
            if banner.dismissible, let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Kapat")
            }
        }
        .padding(Metrics.padding)
        .background(banner.severity == .red ? Color.red.opacity(0.15) : Color.yellow.opacity(0.2),
                    in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
    }
}
