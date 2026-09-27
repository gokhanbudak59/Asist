// WP9 (04 §5.3, signature frozen; 03 §7.5): the single toast at the bottom, above the microphone / tab bar.
// "Geri Al" when toast.hasUndo → toasts.performUndo(); tapping the text dismisses; VoiceOver announces each toast.
// Two hosts exist: the root one (RootView) and one inside the presented sheet (SheetHost, `inSheet`), because a sheet
// covers the root overlay. Exactly one is active: the sheet's while a sheet is shown, the root one otherwise.
import SwiftUI
import UIKit

struct ToastHost: View {
    @Environment(ToastCenter.self) private var toasts
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True for the host inside the presented sheet (SheetHost).
    let inSheet: Bool

    /// DEVIATION(04 §5.3): additive — the frozen `ToastHost()` call still compiles (defaulted parameter).
    /// Explicit so the private environment storage never narrows the initializer's access level.
    init(inSheet: Bool = false) {
        self.inSheet = inSheet
    }

    var body: some View {
        let current = isActive ? toasts.current : nil
        VStack(spacing: 0) {
            if let toast = current {
                toastView(toast)
                    .id(toast.id)
                    .transition(reduceMotion ? AnyTransition.opacity
                                : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, Metrics.padding)
        .padding(.bottom, bottomOffset)
        .allowsHitTesting(current != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: current?.id)
        .onChange(of: toasts.current?.id) { _, newID in
            // Only the active host announces, and only a new toast (not one moving between hosts).
            guard isActive, newID != nil, let text = toasts.current?.text else { return }
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    private var isActive: Bool {
        inSheet == (router.sheet != nil)
    }

    private func toastView(_ toast: ToastCenter.Toast) -> some View {
        HStack(spacing: 8) {
            Text(toast.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    toasts.dismiss()
                }
            if toast.hasUndo {
                Button {
                    toasts.performUndo()
                } label: {
                    Text("Geri Al")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.asistAccent)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.hasUndo ? 6 : 16)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }

    /// Keeps the toast above the tab bar and, on Bugün, above the Yaz / Mic / Oku bar (03 §7.5).
    private var bottomOffset: CGFloat {
        if inSheet { return 96 }                     // above a sheet's bottom button bar (Kaydet, Ekle, Durdur)
        switch router.selectedTab {
        case .today: return 170
        case .lists, .projects: return 130
        case .settings: return 64
        }
    }
}
