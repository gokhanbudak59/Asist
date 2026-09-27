// WP0 STUB (04 §5.3, signature frozen) — replaced by WP9.
import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .asistAccent
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Metrics.primaryButtonHeight)
            .foregroundStyle(filled ? Color.white : tint)
            .background(filled ? tint : Color.clear, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
