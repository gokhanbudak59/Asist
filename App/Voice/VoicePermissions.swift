// WP6 — 01b §1.5 verbatim, plus two read-only helpers used by VoiceCoordinator (04 §3.6.7).
import AVFoundation
import Speech
import UIKit

enum VoicePermissions {
    static var isFullyAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized &&
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// Onboarding'de bir kez çağrılır. İki izin penceresini sırayla gösterir.
    static func requestAll() async -> Bool {
        let speech = await requestSpeech()
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech == .authorized && mic
    }

    static func requestSpeech() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)   // handler arbitrary queue; resume is thread-safe
            }
        }
    }

    @MainActor
    static func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: WP6 additions (read-only)

    /// true → at least one of the two permissions has never been asked (a system prompt can still be shown).
    static var canStillAsk: Bool {
        SFSpeechRecognizer.authorizationStatus() == .notDetermined ||
        AVAudioApplication.shared.recordPermission == .undetermined
    }

    /// Turkish text for the missing permission (03 §7.12 listen.err.*); nil when both are granted.
    static var missingPermissionMessage: String? {
        if AVAudioApplication.shared.recordPermission != .granted {
            return "Mikrofon izni kapalı. Klavyeyle yazabilirsin."
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            return "Konuşma tanıma izni kapalı. Klavyeyle yazabilirsin."
        }
        return nil
    }
}
