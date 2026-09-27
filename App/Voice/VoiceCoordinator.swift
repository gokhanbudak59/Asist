// API: App/Voice/VoiceCoordinator.swift
// WP6 (04 §3.6.7). The only observable voice object (D2): state machine idle → preparing → listening →
// processing → idle, plus speaking. SpeechListener / Speaker / VolumeButtonTrigger are plain @MainActor classes
// that report through closures wired in `init` (which never touches AppEnvironment.shared, 04 §4.1 r13).
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
    /// true while the volume-down ×2 trigger is observing (foreground, idle, enabled).
    private(set) var triggerArmed = false
    /// Overlay visible while preparing/listening/processing.
    var isOverlayVisible: Bool {
        phase == .preparing || phase == .listening || phase == .processing
    }
    private(set) var request = ListenRequest()

    let listener = SpeechListener()
    let speaker = Speaker()
    let trigger = VolumeButtonTrigger()

    // Configuration (apply(settings:)) and bookkeeping — not UI state (04 §4.1 r8).
    @ObservationIgnored private var volumeTriggerEnabled = true
    @ObservationIgnored private var silenceSeconds: Double = 1.8
    @ObservationIgnored private var onDeviceOnly = false
    /// true between sceneDidBecomeActive and sceneDidEnterBackground (never true in a background launch).
    @ObservationIgnored private var sceneActive = false
    /// Incremented by every start and by every abort of a start that has not reached the listener yet;
    /// an older `startListening` that resumes later sees the mismatch and leaves the state alone.
    @ObservationIgnored private var listenGeneration = 0
    @ObservationIgnored private var speakGeneration = 0
    /// true while `capture.handleTranscript` runs (a spoken answer returns to `.processing`, not `.idle`).
    @ObservationIgnored private var isProcessingTranscript = false

    /// Wires callbacks only; MUST NOT touch AppEnvironment.shared (§4.1 r13).
    init() {
        trigger.onDoublePress = { [weak self] in
            Haptics.medium()
            Task { @MainActor in
                await self?.startListening()
            }
        }
        trigger.onLowVolumeChanged = { [weak self] low in
            self?.volumeTooLow = low
        }
        trigger.onArmedChanged = { [weak self] armed in
            self?.triggerArmed = armed
        }
        listener.onPartial = { [weak self] text in
            self?.partialText = text
        }
        listener.onLevel = { [weak self] value in
            self?.level = value
        }
        listener.onReady = { [weak self] in
            guard let self = self, self.phase == .preparing else { return }
            self.phase = .listening
            Haptics.light()                                  // mic really ready: the user starts talking now (03 §5.3)
        }
    }

    /// Stores configuration only (volume trigger enabled, restore volume, silence, on-device, TTS rate).
    /// Never touches the audio session in a background launch (05a #25): `sceneActive` is false there.
    func apply(settings: AppSettings) {
        volumeTriggerEnabled = settings.volumeTriggerEnabled
        trigger.restoreVolumeAfterTrigger = settings.restoreVolumeAfterTrigger
        silenceSeconds = min(5, max(0.8, settings.silenceSeconds))
        onDeviceOnly = settings.onDeviceRecognitionOnly
        speaker.rate = settings.ttsRate
        if !volumeTriggerEnabled {
            // Turned off in Ayarlar while the app is in front: stop observing and release the idle session.
            if trigger.isArmed {
                trigger.disarm()
                if phase == .idle { AudioSessionConfigurator.deactivate() }
            }
        } else if !trigger.isArmed {
            // DEVIATION(04 §3.6.7): the contract names sceneDidBecomeActive and the post-listening re-arm as the only
            // arming points. Turning the toggle on in Ayarlar › Tetikleyiciler must work without leaving the app, so
            // apply also arms — but only under the same guards (scene active, app .active, idle, no onboarding).
            // In a background launch `sceneActive` is false, so apply still never touches the audio session there.
            armTriggerIfAllowed()
        }
    }

    /// Reads AppEnvironment.shared.capture / router lazily at call time (04 §3.6.7 order).
    func startListening(_ request: ListenRequest = ListenRequest()) async {
        guard phase == .idle || phase == .speaking else {
            AsistLog.info("Dinleme isteği yok sayıldı (ses meşgul)", .voice)
            return
        }
        let router = AppEnvironment.shared.router
        if router.showOnboarding { return }                  // trigger stays disarmed during onboarding

        listenGeneration += 1
        let generation = listenGeneration
        self.request = request
        message = nil
        partialText = ""
        level = 0
        trigger.disarm()
        if phase == .speaking { speaker.stop() }             // never listen while speaking (TTS would be recorded)
        phase = .preparing
        AsistLog.info("Dinleme hazırlanıyor", .voice)

        // A sheet would cover the overlay; its onDismiss commits an open draft first (05a #18).
        if router.sheet != nil {
            router.dismissSheet()
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard isCurrentPreparation(generation) else { return }
        }

        if !VoicePermissions.isFullyAuthorized {
            if VoicePermissions.canStillAsk {
                _ = await VoicePermissions.requestAll()
                guard isCurrentPreparation(generation) else { return }
            }
            if !VoicePermissions.isFullyAuthorized {
                AsistLog.info("Dinleme başlatılamadı: mikrofon/konuşma izni yok", .voice)
                let text = VoicePermissions.missingPermissionMessage ?? "Mikrofon veya konuşma tanıma izni kapalı."
                phase = .idle
                reportFailure(text, request: request)
                armTriggerIfAllowed()
                return
            }
        }

        // Recording cannot start from the background (01b §1.3).
        guard UIApplication.shared.applicationState != .background else {
            AsistLog.info("Dinleme arka planda başlatılamaz; iptal", .voice)
            phase = .idle
            return
        }

        let capture = AppEnvironment.shared.capture
        var config = ListenConfig()
        config.silenceAfterSpeech = silenceSeconds
        config.onDeviceOnly = onDeviceOnly
        config.contextualStrings = capture.contextualStrings()
        let outcome = await listener.listen(config: config)

        // Cancelled by sceneDidEnterBackground / a newer start meanwhile: that path already handled everything.
        guard generation == listenGeneration else { return }
        level = 0

        switch outcome {
        case .text(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                phase = .idle
                reportNoSpeech()
            } else {
                if listener.stoppedByMaxDuration {
                    message = "Süre doldu; söylediklerini aldım."
                }
                partialText = text
                phase = .processing
                isProcessingTranscript = true
                await capture.handleTranscript(text, source: .voice, request: request)
                isProcessingTranscript = false
            }
        case .noSpeech:
            phase = .idle
            reportNoSpeech()
        case .failed(let text):
            phase = .idle
            reportFailure(text, request: request)
        case .interrupted(let raw):
            phase = .idle
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // needsReview item (03 §5.3); a "Sesle ertele" utterance is never saved. CaptureService shows the toast.
            if !text.isEmpty {
                let saved = capture.saveInterruptedTranscript(text, request: request)
                if saved {
                    message = "Dinleme yarıda kaldı; söylediklerini taslak olarak sakladım."
                }
            }
        case .cancelled:
            break
        }

        guard generation == listenGeneration else { return }
        // A spoken answer that is still running keeps `.speaking`; `speak` returns to idle and re-arms itself.
        if phase == .preparing || phase == .listening || phase == .processing {
            phase = .idle
        }
        armTriggerIfAllowed()                                // only when the app is .active (D16, 05a #25)
    }

    /// "Bitti": process what was heard so far.
    func finishListening() {
        guard phase == .preparing || phase == .listening else { return }
        switch listener.state {
        case .listening:
            listener.stopAndFinalize()
        case .idle:
            // Still preparing (sheet dismissal / permission prompt): nothing was heard — abort quietly.
            listenGeneration += 1
            phase = .idle
            partialText = ""
            armTriggerIfAllowed()
        case .starting, .finishing:
            break
        }
    }

    /// "Vazgeç": nothing saved; if the partial text has ≥ 2 words → toasts.show("Vazgeçildi", undoTranscript: text) (05b B9).
    func cancelListening() {
        guard phase == .preparing || phase == .listening else { return }
        let text = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasSnooze = request.snoozeItemID != nil
        if listener.state != .idle {
            listener.cancel()                                // the pending startListening resumes with .cancelled
        } else {
            listenGeneration += 1                            // abort a start that has not reached the listener
        }
        phase = .idle
        partialText = ""
        level = 0
        armTriggerIfAllowed()
        AsistLog.info("Dinleme kullanıcı tarafından iptal edildi", .voice)
        // The undo re-runs the text as a normal capture, which would be wrong for a "Sesle ertele" utterance.
        if !wasSnooze && VoiceCoordinator.wordCount(text) >= 2 {
            AppEnvironment.shared.toasts.show("Vazgeçildi", undoTranscript: text)
        }
    }

    /// Waits until finished; phase .speaking meanwhile. Never starts listening while speaking.
    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch phase {
        case .preparing, .listening:
            AsistLog.info("Dinleme sürerken seslendirme atlandı", .voice)   // the mic would record it
            return
        case .idle, .processing, .speaking:
            break
        }
        guard UIApplication.shared.applicationState != .background else { return }
        speakGeneration += 1
        let generation = speakGeneration
        // 01b §3.2: no volume trigger during TTS — turning the speech down must not open the mic. Every way out of
        // .speaking re-arms (idle branch below, startListening's end, a superseding speak).
        trigger.disarm()
        phase = .speaking
        await speaker.speak(trimmed)
        guard generation == speakGeneration, phase == .speaking else { return }
        if isProcessingTranscript {
            phase = .processing                              // startListening finishes the cycle
        } else {
            phase = .idle
            armTriggerIfAllowed()
        }
    }

    /// D18: true when settings.speakConfirmations && (speakConfirmationsOnSpeaker || the current route output is
    /// .headphones / .bluetoothA2DP / .bluetoothHFP / .bluetoothLE / .carAudio / .usbAudio).
    func shouldSpeakConfirmation(settings: AppSettings) -> Bool {
        guard settings.speakConfirmations else { return false }
        if settings.speakConfirmationsOnSpeaker { return true }
        return VoiceCoordinator.isPrivateAudioRoute()
    }

    func stopSpeaking() {
        speaker.stop()                                       // the pending speak() returns and resets the phase
    }

    /// Arms the trigger (if enabled in settings) — the only place besides post-listening re-arm (D16).
    func sceneDidBecomeActive() {
        sceneActive = true
        guard phase == .idle else { return }
        trigger.disarm()                                     // oturumu tazele (01b §3.4)
        armTriggerIfAllowed()
    }

    /// Disarm, cancel, stop TTS, deactivate session; partial transcript → capture.saveInterruptedTranscript.
    func sceneDidEnterBackground() {
        sceneActive = false
        trigger.disarm()
        if phase == .preparing || phase == .listening {
            let text = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            listenGeneration += 1                            // the pending startListening must not handle anything
            if listener.state != .idle { listener.cancel() }
            phase = .idle
            partialText = ""
            level = 0
            if !text.isEmpty {
                AsistLog.info("Arka plana geçiş: yarım kalan döküm taslak olarak saklanıyor", .voice)
                AppEnvironment.shared.capture.saveInterruptedTranscript(text, request: request)
            }
        }
        speaker.stop()
        AudioSessionConfigurator.deactivate()
    }

    // MARK: Private

    private func isCurrentPreparation(_ generation: Int) -> Bool {
        generation == listenGeneration && phase == .preparing
    }

    private func armTriggerIfAllowed() {
        guard volumeTriggerEnabled, sceneActive, phase == .idle, !trigger.isArmed else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        guard !AppEnvironment.shared.router.showOnboarding else { return }
        trigger.arm()
    }

    private func reportNoSpeech() {
        // The toast has no retry action (tapping it only dismisses it), so the copy does not promise one.
        let text = "Seni duyamadım. Tekrar dene."
        message = text
        Haptics.warning()
        AppEnvironment.shared.toasts.show(text)
    }

    /// Speech failures degrade to the keyboard path with a Turkish message (04 §4.2 r7).
    private func reportFailure(_ text: String, request: ListenRequest) {
        message = text
        Haptics.error()
        let env = AppEnvironment.shared
        env.toasts.show(text)
        if env.router.sheet == nil {
            env.router.present(.compose(request))
        }
    }

    private static func isPrivateAudioRoute() -> Bool {
        let privatePorts: [AVAudioSession.Port] = [
            .headphones,
            .bluetoothA2DP,
            .bluetoothHFP,
            .bluetoothLE,
            .carAudio,
            .usbAudio
        ]
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        for output in outputs where privatePorts.contains(output.portType) {
            return true
        }
        return false
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
}
