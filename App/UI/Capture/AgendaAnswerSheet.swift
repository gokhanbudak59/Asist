// WP9 (04 §5.2; 03 §5.9): answer to a spoken query ("bugün ne var", "neyi unuttum") — the sentence that is being
// read aloud, the listed records (✓ from here too; tapping a row opens it) and a 56 pt "Durdur" while speaking.
import SwiftUI
import AsistCore

struct AgendaAnswerSheet: View {
    let answer: SpokenAnswer

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(VoiceCoordinator.self) private var voice
    @Environment(ToastCenter.self) private var toasts

    init(answer: SpokenAnswer) {
        self.answer = answer
    }

    var body: some View {
        let items = listedItems
        NavigationStack {
            TimelineView(.everyMinute) { context in
                List {
                    Section {
                        Label(answer.text, systemImage: Symbol.speak)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if items.isEmpty {
                        Section {
                            EmptyStateView(title: "Listelenecek kayıt yok",
                                           message: "Yeni bir şey söylemek için mikrofona dokunabilirsin.",
                                           systemImage: Symbol.tabToday)
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        Section {
                            ForEach(items) { item in
                                listRow(item, now: context.date)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(answer.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        close()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if voice.phase == .speaking {
                    Button {
                        voice.stopSpeaking()
                    } label: {
                        Label("Durdur", systemImage: Symbol.stop)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Color.asistOverdue))
                    .padding(.horizontal, Metrics.padding)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            if voice.phase == .speaking {
                voice.stopSpeaking()
            }
        }
    }

    private func listRow(_ item: Item, now: Date) -> some View {
        let id = item.id
        return ItemRow(item: item, projectName: store.projectName(for: item), now: now) {
            ItemQuickActions.complete(id, store: store, toasts: toasts)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            open(id)
        }
        .accessibilityAction(named: Text("Aç")) {
            open(id)
        }
    }

    /// Records of the answer that still exist and are open, in spoken order.
    private var listedItems: [Item] {
        var result: [Item] = []
        for id in answer.itemIDs {
            if let item = store.item(id), item.isOpen {
                result.append(item)
            }
        }
        return result
    }

    @MainActor
    private func open(_ id: UUID) {
        if voice.phase == .speaking {
            voice.stopSpeaking()
        }
        router.openItem(id)          // closes the sheet and pushes the detail on Bugün
    }

    @MainActor
    private func close() {
        if voice.phase == .speaking {
            voice.stopSpeaking()
        }
        if case .agenda? = router.sheet {
            router.dismissSheet()
        }
    }
}
