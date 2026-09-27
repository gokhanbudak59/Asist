// Revision 4 (07 §7.6, §8.1): the Bugün toolbar "…" menu — Haftalık rapor and Kişiler, pushed on the Bugün stack.
import SwiftUI

@MainActor
struct TodayMoreMenu: View {
    @Environment(AppRouter.self) private var router

    init() {}

    var body: some View {
        Menu {
            Button {
                router.push(.weeklyReport)
            } label: {
                Label("Haftalık rapor", systemImage: "doc.text")
            }
            Button {
                router.push(.people)
            } label: {
                Label("Kişiler", systemImage: "person.2")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Diğer")
    }
}
