// WP9 (04 §5.2; 03 §4.6, §7.12 compose.*; 05b F2): keyboard entry "Yaz".
// Multi-line field focused on open, live parser preview (300 ms debounce), 56 pt "Ekle" (high confidence → saved
// directly with an undo toast) or "Önizle" (lower confidence → the confirmation card). The unfinished text is kept
// in meta.composeDraft and comes back next time. With request.snoozeItemID the text is only a new time ("Ertele").
import SwiftUI
import AsistCore

struct ComposeSheet: View {
    let request: ListenRequest

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var text = ""
    @State private var preview: CapturePreview?
    @State private var submitted = false
    @State private var loaded = false
    @FocusState private var focused: Bool

    /// Explicit so the private @State storage never narrows the initializer's access level (SheetHost calls it).
    init(request: ListenRequest) {
        self.request = request
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let context = contextText {
                        Label(context, systemImage: contextSymbol)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(.title3)
                        .lineLimit(3...10)
                        .focused($focused)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                                .fill(Color.asistCard)
                        )
                    previewCard
                    if !isSnooze && trimmed.isEmpty {
                        tips
                    }
                }
                .padding(Metrics.padding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.asistBackground)
            .navigationTitle(isSnooze ? "Ertele" : "Yaz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        close()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                addBar
            }
        }
        .onAppear {
            loadDraft()
        }
        .task {
            await focusSoon()
        }
        .task(id: text) {
            await refreshPreview(for: text)
        }
        .onDisappear {
            persistDraft()
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var previewCard: some View {
        if let preview = preview, !trimmed.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: previewSymbol(preview))
                    .font(.title3)
                    .foregroundStyle(Color.asistAccent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.understood.isEmpty ? trimmed : preview.understood)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if preview.level != .autoSave {
                        Label("Emin değilim — kaydetmeden önce kartta göstereceğim", systemImage: Symbol.review)
                            .font(.footnote)
                            .foregroundStyle(Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .fill(Color.asistAccent.opacity(0.08))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Önizleme: " + (preview.understood.isEmpty ? trimmed : preview.understood))
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Örnekler")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Text("Yarın 10'da tedarikçiyi ara")
            Text("Mehmet cumaya kadar I/O listesini gönderecek")
            Text("Kocaeli projesine not: ışık perdesi tekrar ölçülecek")
        }
        .font(.subheadline)
        .foregroundStyle(Color.secondary)
    }

    private var addBar: some View {
        Button {
            add()
        } label: {
            Label(buttonTitle, systemImage: isSnooze ? Symbol.snooze : "plus.circle.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(trimmed.isEmpty)
        .padding(.horizontal, Metrics.padding)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Derived values

    private var isSnooze: Bool { request.snoozeItemID != nil }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var placeholder: String {
        if isSnooze { return "Yeni zaman? Örn: perşembe 10'da" }
        if request.kind == .note { return "Notunu yaz" }
        return "Ne hatırlatayım? Örn: Yarın 10'da tedarikçiyi ara"
    }

    private var buttonTitle: String {
        if isSnooze { return "Ertele" }
        guard let preview = preview, !trimmed.isEmpty else { return "Ekle" }
        return preview.level == .autoSave ? "Ekle" : "Önizle"
    }

    private var contextText: String? {
        if let id = request.snoozeItemID {
            if let item = store.item(id), !item.title.isEmpty {
                return "“" + item.title + "” için yeni zaman"
            }
            return "Yeni zaman"
        }
        var parts: [String] = []
        if request.kind == .note {
            parts.append("Not olarak kaydedilecek")
        }
        if let projectID = request.projectID, let project = store.project(projectID) {
            parts.append("Proje: " + project.name)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var contextSymbol: String {
        if isSnooze { return Symbol.snooze }
        if request.kind == .note { return Symbol.note }
        return Symbol.project
    }

    private func previewSymbol(_ preview: CapturePreview) -> String {
        if isSnooze { return Symbol.snooze }
        guard let kind = preview.kind else { return "text.bubble" }
        return kind.symbol
    }

    // MARK: - Actions

    @MainActor
    private func loadDraft() {
        guard !loaded else { return }
        loaded = true
        if !isSnooze, let saved = store.meta.composeDraft, !saved.isEmpty {
            text = saved
        }
    }

    @MainActor
    private func focusSoon() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
        if !Task.isCancelled {
            focused = true
        }
    }

    @MainActor
    private func refreshPreview(for value: String) async {
        let current = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            preview = nil
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        preview = AppEnvironment.shared.capture.preview(value, request: request)
    }

    /// The sheet is closed first; the capture runs after the dismissal finished, so the sheet's onDismiss
    /// (commitActiveDraftIfNeeded) can never pick up the card this text is about to open.
    @MainActor
    private func add() {
        let value = trimmed
        guard !value.isEmpty, !submitted else { return }
        submitted = true
        focused = false
        let listenRequest = request
        let snooze = isSnooze
        if case .compose? = router.sheet {
            router.dismissSheet()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            let env = AppEnvironment.shared
            if snooze {
                await env.capture.handleTranscript(value, source: .keyboard, request: listenRequest)
            } else {
                await env.capture.addFromKeyboard(value, request: listenRequest)
            }
            if !snooze && env.store.meta.composeDraft != nil {
                env.store.updateMeta { meta in
                    meta.composeDraft = nil
                }
            }
        }
    }

    @MainActor
    private func close() {
        focused = false
        router.dismissSheet()
    }

    /// Unfinished text survives closing the sheet (03 §4.6); a submitted text is cleared after it was handled.
    @MainActor
    private func persistDraft() {
        guard !submitted, !isSnooze else { return }
        let value: String? = trimmed.isEmpty ? nil : text
        if store.meta.composeDraft != value {
            store.updateMeta { meta in
                meta.composeDraft = value
            }
        }
    }
}
