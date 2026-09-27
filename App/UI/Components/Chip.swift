// WP0 STUB (04 §5.3, signatures frozen) — replaced by WP9.
// Chip.swift declares Chip, ChipRow and StatChip (only here, 05a #31).
import SwiftUI

struct StatChip: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .frame(minHeight: Metrics.chipHeight)
                .background(Color.asistCard, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var isUncertain: Bool = false         // dashed border + "?" (03 §7.5)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                }
                Text(isUncertain ? title + " ?" : title)
            }
            .padding(.horizontal, 12)
            .frame(minWidth: Metrics.chipMinWidth, minHeight: Metrics.chipHeight)
            .background(isSelected ? Color.asistAccent.opacity(0.2) : Color.asistCard, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ChipRow<Content: View>: View {     // horizontal ScrollView, 8 pt spacing
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.chipSpacing) {
                content()
            }
        }
    }
}
