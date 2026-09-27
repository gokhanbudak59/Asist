// WP0 STUB (04 §3.6.7; referenced by the VoiceCoordinator API) — replaced by WP6 (01b §1.7 adapted per D2/D19).
import Foundation

@MainActor
final class SpeechListener {
    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
}
