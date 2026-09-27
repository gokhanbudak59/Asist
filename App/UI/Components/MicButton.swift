// WP0 STUB (04 §5.3, signature frozen) — replaced by WP9.
import SwiftUI

struct MicButton: View {
    let size: CGFloat
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? Symbol.listening : Symbol.mic)
                .font(.system(size: size * 0.4))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .background(Color.asistAccent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dinlemeye başla")
    }
}
