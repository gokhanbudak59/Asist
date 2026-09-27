// WP0 STUB (04 §5.2) — replaced by WP9 (03 §4.6).
import SwiftUI

struct ComposeSheet: View {
    let request: ListenRequest
    @Environment(AppRouter.self) private var router
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Ne kaydedeyim?", text: $text, axis: .vertical)
            }
            .navigationTitle("Yaz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        router.dismissSheet()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        add()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @MainActor
    private func add() {
        let current = text
        let listenRequest = request
        router.dismissSheet()
        Task { @MainActor in
            await AppEnvironment.shared.capture.addFromKeyboard(current, request: listenRequest)
        }
    }
}
