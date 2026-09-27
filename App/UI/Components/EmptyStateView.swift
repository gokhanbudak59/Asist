// WP9 (04 §5.3, signature frozen; 03 §7.10): wraps ContentUnavailableView (iOS 17) — symbol + title + one sentence.
import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity)
    }
}
