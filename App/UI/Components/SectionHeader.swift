// WP9 (04 §5.3, signature frozen; §5.4 typography): uppercase Turkish literal header ("GECİKENLER") + optional count.
// Titles are passed already uppercase (D28); `.textCase(nil)` keeps List from re-casing them.
import SwiftUI

struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
            if let count = count {
                Text(String(count))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(color.opacity(0.15)))
            }
        }
        .foregroundStyle(color)
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
