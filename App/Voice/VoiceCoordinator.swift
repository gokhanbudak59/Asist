// API: App/Voice/VoiceCoordinator.swift
// WP0 STUB (04 §3.6.7) — replaced by WP6. Never touches the audio session, never listens or speaks.
import Foundation
import Observation
import UIKit
import AVFoundation
import AsistCore

@MainActor
@Observable
final class VoiceCoordinator {
    enum Phase: Equatable { case idle, preparing, listening, processing, speaking }

    private(set) var phase: Phase = .idle
    private(set) var partialText: String = ""
    private(set) var level: Float = 0
    /// Last user-facing error/info (Turkish, 03 §7.12 listen.*); cleared on next start.
    private(set) var message: String? = nil
    private(set) var volumeTooLow = false
    /// Overlay visible while preparing/listening/processing.
    var isOverlayVisible: Bool {
        phase == .preparing || phase == .listening || phase == .processing
    }
    private(set) var request = ListenRequest()

    let listener = SpeechListener()
    let speaker = Speaker()
    let trigger = VolumeButtonTrigger()

    /// Wires callbacks only; MUST NOT touch AppEnvironment.shared (§4.1 r13). (WP0 STUB: nothing to wire.)
    init() {}

    /// Stores configuration only (WP0 STUB: no-op).
    func apply(settings: AppSettings) {}

    /// WP0 STUB: remembers the request; no listening happens.
    func startListening(_ request: ListenRequest = ListenRequest()) async {
        self.request = request
    }

    func finishListening() {
        phase = .idle
    }

    func cancelListening() {
        phase = .idle
        partialText = ""
    }

    func speak(_ text: String) async {}

    func shouldSpeakConfirmation(settings: AppSettings) -> Bool {
        false
    }

    func stopSpeaking() {}

    func sceneDidBecomeActive() {}

    func sceneDidEnterBackground() {
        phase = .idle
    }
}
