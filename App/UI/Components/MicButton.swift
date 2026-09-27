// WP9 (04 §5.3, signature frozen; 03 §4.1, §7.4, §7.7): 88 pt (Bugün) / 64 pt (floating) microphone.
// Active (listening) → waveform symbol + a soft pulse ring (none with Reduce Motion).
import SwiftUI

struct MicButton: View {
    let size: CGFloat
    let isActive: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(size: CGFloat, isActive: Bool, action: @escaping () -> Void) {
        self.size = size
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isActive && !reduceMotion {
                    MicPulseRing(size: size)
                }
                Circle()
                    .fill(Color.asistAccent)
                    .frame(width: size, height: size)
                    .shadow(color: Color.asistAccent.opacity(0.35), radius: 8, x: 0, y: 4)
                Image(systemName: isActive ? Symbol.listening : Symbol.mic)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(MicPressStyle())
        .accessibilityLabel("Dinlemeye başla")
        .accessibilityHint(isActive ? "Dinleniyor" : "Söylediğini kaydeder")
    }
}

private struct MicPulseRing: View {
    let size: CGFloat
    @State private var animate = false

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        Circle()
            .stroke(Color.asistAccent.opacity(0.6), lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(animate ? 1.35 : 1)
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
            .accessibilityHidden(true)
    }
}

private struct MicPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
