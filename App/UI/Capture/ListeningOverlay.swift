// WP9 (04 §5.1–5.2; 03 §4.4, §5.3, §7.7–7.8; 05b B9/D5): full-screen listening layer.
// Phase text, live transcript (≤ 5 lines, newest words kept), level ring (Reduce Motion → bar), rotating example,
// Vazgeç / Klavye (44 pt) and Bitti (72 pt). Tapping the background = Bitti. Snooze mode: "Yeni zamanı söyle".
// The layer is always dark (material + 60 % black) so it reads the same in light and dark mode.
import SwiftUI
import AsistCore

struct ListeningOverlay: View {
    @Environment(VoiceCoordinator.self) private var voice
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hintIndex = Int.random(in: 0..<5)

    private static let hints: [String] = [
        "Örnek: \"Yarın 10'da tedarikçiyi aramayı hatırlat\"",
        "Örnek: \"Mehmet cuma gününe kadar I/O listesini gönderecek\"",
        "Örnek: \"Kocaeli projesine not: ışık perdesi tekrar ölçülecek\"",
        "Örnek: \"Bugün ne var?\"",
        "Örnek: \"Her pazartesi 9'da haftalık raporu hatırlat\""
    ]

    var body: some View {
        ZStack {
            backgroundLayer
            VStack(spacing: 18) {
                topBar
                Spacer(minLength: 4)
                if let title = modeTitle {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .accessibilityAddTraits(.updatesFrequently)
                    transcript
                    contextChips
                    levelIndicator
                    if let message = voice.message, !message.isEmpty {
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.yellow)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Text(hintText)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                doneButton
            }
            .padding(.horizontal, Metrics.padding)
            .padding(.vertical, 8)
            .foregroundStyle(Color.white)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Parts

    private var backgroundLayer: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Color.black.opacity(0.6)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            finish()
        }
        .accessibilityHidden(true)
    }

    private var topBar: some View {
        HStack {
            Button {
                cancel()
            } label: {
                Label("Vazgeç", systemImage: "xmark")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button {
                switchToKeyboard()
            } label: {
                Label("Klavye", systemImage: Symbol.keyboard)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var transcript: some View {
        let text = voice.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            Text(voice.phase == .listening ? "Seni dinliyorum…" : " ")
                .font(.title2)
                .foregroundStyle(Color.white.opacity(0.5))
        } else {
            Text("“" + text + "”")
                .font(.title2)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .truncationMode(.head)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var contextChips: some View {
        let labels = contextLabels
        if !labels.isEmpty {
            HStack(spacing: 8) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
            }
        }
    }

    @ViewBuilder
    private var levelIndicator: some View {
        let level = CGFloat(min(1, max(0, voice.level)))
        switch voice.phase {
        case .processing:
            ProgressView()
                .controlSize(.large)
                .tint(Color.white)
                .frame(height: 140)
                .accessibilityLabel("Anlamaya çalışıyorum")
        case .idle, .preparing, .listening, .speaking:
            if reduceMotion {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 200, height: 10)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 200 * level, height: 10)
                }
                .frame(height: 140)
                .accessibilityHidden(true)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.asistAccent.opacity(0.35))
                        .frame(width: 130, height: 130)
                        .scaleEffect(0.9 + 0.4 * level)
                        .animation(.easeOut(duration: 0.15), value: level)
                    Circle()
                        .fill(Color.asistAccent)
                        .frame(width: 88, height: 88)
                    Image(systemName: Symbol.mic)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .opacity(voice.phase == .listening ? 1 : 0.45)
                .frame(height: 170)
                .accessibilityHidden(true)
            }
        }
    }

    private var doneButton: some View {
        Button {
            finish()
        } label: {
            Label("Bitti", systemImage: Symbol.stop)
                .frame(maxWidth: .infinity, minHeight: Metrics.listeningDoneHeight - 16)
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(minHeight: Metrics.listeningDoneHeight)
        .disabled(voice.phase == .processing)
        .accessibilityHint("Dinlemeyi bitirir ve söylediklerini işler")
    }

    // MARK: - Texts

    private var statusText: String {
        switch voice.phase {
        case .preparing: return "Hazırlanıyor…"
        case .listening: return "Dinliyorum…"
        case .processing: return "Anlamaya çalışıyorum…"
        case .speaking: return "Konuşuyorum…"
        case .idle: return " "
        }
    }

    private var modeTitle: String? {
        guard let id = voice.request.snoozeItemID else { return nil }
        if let item = store.item(id), !item.title.isEmpty {
            return "Yeni zamanı söyle\n“" + item.title + "”"
        }
        return "Yeni zamanı söyle"
    }

    private var hintText: String {
        if voice.request.snoozeItemID != nil {
            return "Örnek: \"perşembe 10'da\", \"yarın öğleden sonra\", \"2 saat sonra\""
        }
        let hints = ListeningOverlay.hints
        return hints[abs(hintIndex) % hints.count]
    }

    private var contextLabels: [String] {
        var labels: [String] = []
        if voice.request.kind == .note {
            labels.append("Not")
        } else if voice.request.kind == .waiting {
            labels.append("Takip")
        }
        if let projectID = voice.request.projectID, let project = store.project(projectID) {
            labels.append("Proje: " + project.name)
        }
        return labels
    }

    // MARK: - Actions

    @MainActor
    private func finish() {
        guard voice.phase == .listening || voice.phase == .preparing else { return }
        voice.finishListening()
    }

    @MainActor
    private func cancel() {
        voice.cancelListening()
    }

    /// "Klavye": stop listening without the "Vazgeçildi" toast and continue in Yaz with what was heard so far.
    @MainActor
    private func switchToKeyboard() {
        let partial = voice.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = voice.request
        voice.cancelListening()
        toasts.dismiss()
        if !partial.isEmpty && request.snoozeItemID == nil {
            store.updateMeta { meta in
                meta.composeDraft = partial
            }
        }
        router.present(.compose(request))
    }
}
