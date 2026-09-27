// WP9 (04 §5.3, signature frozen; 03 §7.3–7.5): 56 pt primary button style used everywhere.
// filled = tint background + white text; outlined (filled: false) = soft tint background + tint text.
import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .asistAccent
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, tint: tint, filled: filled)
    }
}

/// Separate view so the style can read `isEnabled` / Reduce Motion from the environment.
private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let filled: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(configuration: ButtonStyleConfiguration, tint: Color, filled: Bool) {
        self.configuration = configuration
        self.tint = tint
        self.filled = filled
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
        let pressed = configuration.isPressed
        let baseOpacity: Double = pressed ? 0.75 : 1
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Metrics.primaryButtonHeight)
            .foregroundStyle(filled ? Color.white : tint)
            .background(shape.fill(filled ? tint : tint.opacity(0.14)))
            .overlay(shape.stroke(filled ? Color.clear : tint.opacity(0.35), lineWidth: 1))
            .contentShape(shape)
            .opacity(isEnabled ? baseOpacity : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
    }
}
