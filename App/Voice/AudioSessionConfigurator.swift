// WP6 — 01b §1.6 verbatim (audio session policy 01b §1.3).
// `.allowBluetooth` is deprecated in the iOS 26 SDK (warning only, 04 §9 r30); do not switch to `.allowBluetoothHFP`.
import AVFoundation

enum AudioSessionConfigurator {
    /// Uygulama ön plandayken ses tuşu KVO'su için: müziği kesmez.
    static func activateForVolumeTrigger() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    /// Dinleme: diğer sesleri duraklatır (Siri gibi), hoparlöre yönlendirir.
    static func activateForListening() throws {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
