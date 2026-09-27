// WP0 STUB (04 §3.6.7; referenced by the VoiceCoordinator API) — replaced by WP6 (01b §2.1 adapted per D2).
// No `override init` (04 §9 r8); delegate methods (none in the stub) must be `nonisolated`.
import Foundation
import AVFoundation
import AsistCore

@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    var rate: TTSRate = .normal

    /// WP0 STUB: returns immediately without speaking.
    func speak(_ text: String) async {}
}
