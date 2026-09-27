// WP0 STUB (04 §5.2) — replaced by WP11 (numbered steps per guide).
import SwiftUI

struct GuideView: View {
    let kind: GuideKind

    var body: some View {
        Text(title)
            .foregroundStyle(Color.secondary)
            .navigationTitle(title)
    }

    private var title: String {
        switch kind {
        case .backTap: return "Asist Hızlı Kayıt"
        case .backTapListen: return "Asist Dinle"
        case .siri: return "Siri"
        case .focus: return "Odak"
        case .banners: return "Kalıcı bildirim"
        }
    }
}
