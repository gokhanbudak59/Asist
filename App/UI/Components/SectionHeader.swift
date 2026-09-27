// WP0 STUB (04 §5.3, signature frozen) — replaced by WP9.
import SwiftUI

struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
            if let count = count {
                Text(String(count))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
    }
}
