// WP9 (04 §5.3, signatures frozen; 03 §7.4–7.5).
// Chip.swift declares Chip, ChipRow and StatChip (only here, 05a #31).
import SwiftUI
import UIKit

/// Counter chip on the Today header ("2 geciken", "5 bugün", "1 takip").
struct StatChip: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: Metrics.chipMinWidth, minHeight: Metrics.chipHeight)
                .background(Capsule().fill(color.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Selectable chip: selected = filled accent + white text; unselected = light fill; uncertain = dashed border + "?".
struct Chip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var isUncertain: Bool = false         // dashed border + "?" (03 §7.5)
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(isUncertain ? title + " ?" : title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(minWidth: Metrics.chipMinWidth, minHeight: Metrics.chipHeight)
            .background(Capsule().fill(fillColor))
            .overlay(border)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isUncertain ? title + ", emin değilim" : title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var fillColor: Color {
        if isSelected { return Color.asistAccent }
        return Color(uiColor: .tertiarySystemFill)
    }

    @ViewBuilder
    private var border: some View {
        if isUncertain {
            Capsule()
                .strokeBorder(Color.asistReview, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        } else {
            Capsule()
                .strokeBorder(Color.clear, lineWidth: 0)
        }
    }
}

struct ChipRow<Content: View>: View {     // horizontal ScrollView, 8 pt spacing
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.chipSpacing) {
                content()
            }
            .padding(.vertical, 2)
        }
    }
}
