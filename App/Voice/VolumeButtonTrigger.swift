// WP0 STUB (04 §3.6.7; referenced by the VoiceCoordinator API) — replaced by WP6 (01b §3.3 adapted per D2).
import Foundation

@MainActor
final class VolumeButtonTrigger {
    var onDoublePress: (() -> Void)?
    var onLowVolumeChanged: ((Bool) -> Void)?
}
