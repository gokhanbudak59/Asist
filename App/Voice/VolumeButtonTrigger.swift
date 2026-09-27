// WP6 — 01b §3.3 adapted per D2 / D16 (04 §3.6.7): plain @MainActor class reporting through closures.
// Foreground only: KVO on AVAudioSession.outputVolume with an active `.playback` + `.mixWithOthers` session.
// Two volume-DOWN events within `pressWindow` (1 s) fire once no third event arrives within `confirmDelay`
// (held button / triple press rejection), then `cooldown`. The previous volume is restored through the hidden
// MPVolumeView slider (SystemVolumeAnchor) when `restoreVolumeAfterTrigger` is on (D16, device test D-f).
import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class VolumeButtonTrigger {
    private(set) var isArmed = false
    /// true → iki "kısma" olayı algılanamayacak kadar düşük ses.
    private(set) var volumeTooLow = false

    var onDoublePress: (() -> Void)?
    var onLowVolumeChanged: ((Bool) -> Void)?
    var pressWindow: TimeInterval = 1.0          // kullanıcı şartı: max 1 sn
    var confirmDelay: TimeInterval = 0.3         // basılı tutmayı ayırt etmek için
    var cooldown: TimeInterval = 1.5
    var holdCooldown: TimeInterval = 0.8
    var restoreVolumeAfterTrigger = true

    private var observation: NSKeyValueObservation?
    private var sessionObservers: [NSObjectProtocol] = []
    private var firstDownAt: Date?
    private var volumeBeforeGesture: Float?
    private var pendingConfirm: Task<Void, Never>?
    private var cooldownUntil = Date.distantPast
    private var holdBlockedUntil = Date.distantPast
    private var ignoreUntil = Date.distantPast
    private var loggedMissingSlider = false
    private weak var volumeView: MPVolumeView?

    func attach(_ view: MPVolumeView) {
        volumeView = view
    }

    /// Activates the mixable playback session and starts observing the volume. Only call while the app is active.
    @discardableResult
    func arm() -> Bool {
        guard !isArmed else { return true }
        do {
            try AudioSessionConfigurator.activateForVolumeTrigger()
        } catch {
            let nsError = error as NSError
            AsistLog.error("Ses tuşu tetikleyicisi etkinleştirilemedi: " + nsError.domain + " " + String(nsError.code), .voice)
            return false
        }
        ignoreUntil = Date().addingTimeInterval(0.5)          // activation itself may report a volume change
        observation = VolumeButtonTrigger.observeOutputVolume(owner: self)
        removeSessionObservers()
        sessionObservers.append(VolumeButtonTrigger.makeInterruptionObserver(owner: self))
        sessionObservers.append(VolumeButtonTrigger.makeMediaResetObserver(owner: self))
        isArmed = true
        updateLowVolumeFlag(currentVolume())
        return true
    }

    /// Stops observing. Does not deactivate the audio session (the caller decides: listening re-configures it,
    /// background deactivates it).
    func disarm() {
        observation?.invalidate()
        observation = nil
        removeSessionObservers()
        resetGesture()
        isArmed = false
    }

    func currentVolume() -> Float {
        if let slider = volumeSlider() { return slider.value }
        return AVAudioSession.sharedInstance().outputVolume
    }

    /// Gizli MPVolumeView kaydırıcısı ile sistem sesini ayarlar (resmî API değildir).
    func setSystemVolume(_ value: Float) {
        guard let slider = volumeSlider() else {
            if !loggedMissingSlider {
                loggedMissingSlider = true
                AsistLog.error("Ses kaydırıcısı bulunamadı; ses seviyesi geri yüklenemedi", .voice)
            }
            return
        }
        ignoreUntil = Date().addingTimeInterval(0.6)          // kendi değişikliğimizi yok say
        slider.setValue(min(max(value, 0), 1), animated: false)
        slider.sendActions(for: .valueChanged)
    }

    /// "Sesi biraz aç" (03 listen.vol.hint_zero): 4 of 16 steps, enough for two detectable presses.
    func raiseVolumeForDetection() {
        setSystemVolume(0.25)
        updateLowVolumeFlag(0.25)
    }

    // MARK: Private

    private func volumeSlider() -> UISlider? {
        guard let view = volumeView else { return nil }
        return VolumeButtonTrigger.findSlider(in: view)
    }

    private static func findSlider(in view: UIView) -> UISlider? {
        for subview in view.subviews {
            if let slider = subview as? UISlider { return slider }
            if let nested = findSlider(in: subview) { return nested }
        }
        return nil
    }

    nonisolated private static func observeOutputVolume(owner: VolumeButtonTrigger) -> NSKeyValueObservation {
        AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.old, .new]) { [weak owner] _, change in
            guard let old = change.oldValue, let new = change.newValue else { return }
            Task { @MainActor [weak owner] in
                owner?.volumeChanged(from: old, to: new)
            }
        }
    }

    nonisolated private static func makeInterruptionObserver(owner: VolumeButtonTrigger) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance(),
                                               queue: .main) { [weak owner] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak owner] in
                owner?.handleInterruption(rawType: raw)
            }
        }
    }

    nonisolated private static func makeMediaResetObserver(owner: VolumeButtonTrigger) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                               object: nil,
                                               queue: .main) { [weak owner] _ in
            Task { @MainActor [weak owner] in
                owner?.handleMediaServicesReset()
            }
        }
    }

    private func handleInterruption(rawType: UInt?) {
        guard isArmed, let raw = rawType,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        do {
            try AudioSessionConfigurator.activateForVolumeTrigger()   // arama/alarm sonrası yeniden etkinleştir
            ignoreUntil = Date().addingTimeInterval(0.5)
        } catch {
            AsistLog.error("Kesinti sonrası ses oturumu yeniden etkinleştirilemedi", .voice)
        }
    }

    private func handleMediaServicesReset() {
        guard isArmed else { return }
        AsistLog.info("Ses hizmetleri sıfırlandı; ses tuşu tetikleyicisi yeniden kuruluyor", .voice)
        disarm()
        arm()
    }

    private func removeSessionObservers() {
        for token in sessionObservers { NotificationCenter.default.removeObserver(token) }
        sessionObservers.removeAll()
    }

    private func volumeChanged(from old: Float, to new: Float) {
        guard isArmed else { return }
        updateLowVolumeFlag(new)
        let now = Date()
        guard now >= ignoreUntil else { return }
        guard new != old else { return }
        guard new < old else {                                  // "açma" tuşu hareketi iptal eder
            resetGesture()
            return
        }
        if now < holdBlockedUntil {                             // button still held: keep blocking
            holdBlockedUntil = now.addingTimeInterval(holdCooldown)
            return
        }
        guard now >= cooldownUntil else { return }

        if pendingConfirm != nil {                              // 3. olay → basılı tutuluyor / üçlü basış
            resetGesture()
            holdBlockedUntil = now.addingTimeInterval(holdCooldown)
            return
        }
        if let first = firstDownAt, now.timeIntervalSince(first) <= pressWindow {
            let delay = UInt64(max(0, confirmDelay) * 1_000_000_000)
            pendingConfirm = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard let self = self, !Task.isCancelled else { return }
                self.fire()
            }
        } else {
            firstDownAt = now
            volumeBeforeGesture = old
        }
    }

    private func fire() {
        let restoreTo = volumeBeforeGesture
        pendingConfirm = nil
        firstDownAt = nil
        volumeBeforeGesture = nil
        cooldownUntil = Date().addingTimeInterval(cooldown)
        guard isArmed else { return }
        AsistLog.info("Ses kısma tuşu ×2 algılandı", .voice)
        if restoreVolumeAfterTrigger, let value = restoreTo {
            setSystemVolume(value)
            updateLowVolumeFlag(value)
        }
        onDoublePress?()
    }

    private func resetGesture() {
        pendingConfirm?.cancel()
        pendingConfirm = nil
        firstDownAt = nil
        volumeBeforeGesture = nil
    }

    private func updateLowVolumeFlag(_ volume: Float) {
        let low = volume < 0.12                                 // < 2 kademe (1/16 = 0.0625)
        guard low != volumeTooLow else { return }
        volumeTooLow = low
        onLowVolumeChanged?(low)
    }
}
