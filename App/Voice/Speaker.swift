// WP6 — 01b §2.1 adapted per D2 (04 §3.6.7): no ObservableObject/@Published, `var rate: TTSRate`,
// delegate methods `nonisolated` with the hop pattern (04 §4.1 r5), and **no `override init`** (04 §9 r8):
// the synthesizer is configured on the first `speak`.
import Foundation
import AVFoundation
import AsistCore

@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    var rate: TTSRate = .normal
    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()          // güçlü referans şart
    private var continuation: CheckedContinuation<Void, Never>?
    private var currentID: ObjectIdentifier?
    private var watchdog: Task<Void, Never>?

    // Bilerek `override init()` YOK: @MainActor sınıfta NSObject.init'i ezmek izolasyon hatası üretebilir.
    private func configureIfNeeded() {
        if synthesizer.delegate == nil {
            synthesizer.delegate = self
            synthesizer.usesApplicationAudioSession = false   // sistem ducking/interruption yönetir
        }
    }

    static func bestTurkishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "tr-TR" }
        if let premium = voices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) { return enhanced }
        return voices.first ?? AVSpeechSynthesisVoice(language: "tr-TR")
    }

    /// Settings "Konuşma hızı" (Yavaş / Normal / Hızlı) → AVSpeechUtterance rate.
    static func utteranceRate(for rate: TTSRate) -> Float {
        let factor: Float
        switch rate {
        case .slow: factor = 0.85
        case .normal: factor = 1.0
        case .fast: factor = 1.15
        }
        let value: Float = AVSpeechUtteranceDefaultSpeechRate * factor
        return min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, value))
    }

    /// Konuşma bitene (veya iptal edilene) kadar bekler.
    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configureIfNeeded()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Speaker.bestTurkishVoice()
        utterance.rate = Speaker.utteranceRate(for: rate)
        utterance.postUtteranceDelay = 0.1
        let id = ObjectIdentifier(utterance)
        let characterCount = trimmed.count
        isSpeaking = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let previous = self.continuation
            self.continuation = continuation
            self.currentID = id
            previous?.resume()                                 // önceki bekleyeni serbest bırak
            self.startWatchdog(for: id, characterCount: characterCount)
            self.synthesizer.speak(utterance)
        }
    }

    /// Stops immediately; the pending `speak` returns right away (the late didCancel callback is ignored).
    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        if let id = currentID { complete(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.complete(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.complete(id) }
    }

    /// Safety net: if the synthesizer never reports finish/cancel (no voice installed, audio failure), `speak`
    /// must still return so the voice state machine never stays in `.speaking`.
    private func startWatchdog(for id: ObjectIdentifier, characterCount: Int) {
        watchdog?.cancel()
        let seconds = min(180.0, 8.0 + Double(characterCount) * 0.15)
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard let self = self, !Task.isCancelled, self.currentID == id else { return }
            AsistLog.error("Seslendirme zaman aşımı; durduruluyor", .voice)
            if self.synthesizer.isSpeaking { self.synthesizer.stopSpeaking(at: .immediate) }
            self.complete(id)
        }
    }

    private func complete(_ id: ObjectIdentifier) {
        guard id == currentID else { return }                // eski (iptal edilmiş) cümlenin geri çağrısı
        currentID = nil
        isSpeaking = false
        watchdog?.cancel()
        watchdog = nil
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
