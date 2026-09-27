# 01b — Platform: Voice I/O, Triggers, Siri / App Intents, Widgets

Project: **Asist** (iOS, SwiftUI) · Owner topic: voice capture, speech output, triggers, App Intents, WidgetKit, Controls, Live Activities
Status: design, research-verified 2026-09-27 · Deployment target **iOS 17.0**, device **iPhone 14 Pro Max on iOS 26**, Swift language mode **5**, build on GitHub Actions (no local compiler).

> **Türkçe kısa özet (kullanıcı için):** Ses kısma tuşuna 2 kez basma yalnız uygulama **ekrandayken** algılanabilir; iOS, arka planda/kilit ekranında ses tuşlarını hiçbir uygulamaya vermez. Uygulama kapalıyken en hızlı yollar: (1) **Arkaya Dokun** (telefonun arkasına 2 kez vur) → "Metni Dikte Et → Asist'e Kaydet" kestirmesi (uygulama açılmadan kaydeder), (2) **"Hey Siri, Asist'e kaydet"** (kilit ekranında da çalışır, Siri "Ne kaydedeyim?" diye sorar), (3) iOS 18+ **Denetim Merkezi / Kilit Ekranı düğmesi** "Asist Dinle", (4) kilit ekranı / ana ekran **widget**'ı. Konuşma tanıma Türkçe'yi destekler (cihaz üzerinde de). Asist sonucu Türkçe sesle onaylar.

---

## 0. Decisions at a glance

| # | Decision | Why | Confidence |
|---|----------|-----|-----------|
| D1 | STT engine v1 = **`SFSpeechRecognizer(locale: tr-TR)`** + `AVAudioEngine` tap | iOS 10+ API, not deprecated (checked iOS 27 docs), Turkish supported incl. on-device dictation | VERIFIED |
| D2 | Default: **server recognition allowed** (`requiresOnDeviceRecognition = false`), user toggle "Yalnız cihazda tanı" | Apple: on-device "won't be as accurate"; Turkish has no auto-punctuation anyway | VERIFIED |
| D3 | Auto-stop = **1.8 s without new partial text after speech started** (+ loud-audio guard), 7 s no-speech timeout, 55 s hard cap | Server requests are cut at 1 min | VERIFIED (limit) / design |
| D4 | TTS = `AVSpeechSynthesizer` with best installed `tr-TR` voice, `usesApplicationAudioSession = false` | System then manages its own session, ducking and interruptions; no category juggling | VERIFIED (doc text) |
| D5 | Volume ×2 trigger = **foreground only**, KVO on `AVAudioSession.outputVolume` with an active `.playback` + `.mixWithOthers` session | Global/background interception is impossible; this category is what JPSVolumeButtonHandler uses | VERIFIED (impl.) / device test |
| D6 | System-wide triggers: **Back Tap → user Shortcut**, **Siri App Shortcut**, **ControlWidget (iOS 18)**, lock-screen & home widgets (`widgetURL`) | iPhone 14 Pro Max has no Action Button | VERIFIED |
| D7 | `DinleIntent` (opens app) uses `openAppWhenRun` via `@available(*, deprecated) extension` — **no `supportedModes` in v1** | `supportedModes` is iOS 26-only; Apple's documented back-compat pattern | VERIFIED |
| D8 | Intents that must touch the store from a widget button conform to **`LiveActivityIntent`** so they run **in the app process** | Plain widget intents run in the widget extension (no access to app container / notification logic) | VERIFIED (doc) / pragmatic |
| D9 | **Primary data store stays in the app's own container**; App Group holds only a disposable **widget snapshot JSON** | Group ID may be missing/rewritten by free-account re-signing → data must never depend on it | design (risk mitigation) |
| D10 | Turkish Siri phrases: dev language `tr` + phrases written in Turkish in code + `tr.lproj/AppShortcuts.strings` identity mapping | Metadata is extracted at build time; `.strings` is deterministic in CI | PARTLY UNVERIFIED — device test |
| D11 | Live Activities: **not in v1** | Cannot be started when a reminder fires (no code runs; push-to-start needs APNs) | VERIFIED |

---

## 0.1 Build-environment assumptions that affect compile-correctness

* GitHub runner **`macos-26`** is GA; default Xcode there is 26.x, Xcode 27 is in preview. **Pin Xcode 26.x** (iOS 26 SDK). Minimum that this document's code needs: **Xcode 16.1** (iOS 18.1 SDK) because of `ControlWidget` and the WidgetBundle `#available` fix. [VERIFIED: https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/ , https://developer.apple.com/forums/thread/759670]
* Apple docs fetched today already show **iOS 27** deprecations (e.g. `installTap` "Deprecated in 27.0"). Deprecations produce **warnings, not errors**. Do **not** enable "Treat warnings as errors".
* `SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`. Do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` or `SWIFT_APPROACHABLE_CONCURRENCY` (Xcode 26 new-project defaults; XcodeGen does not add them — keep it that way). All code below is written to also survive stricter modes: audio callbacks are created inside `nonisolated static` factories so they are never inferred `@MainActor` (prevents the Swift 6 runtime "wrong executor" trap).
* Deprecation table (things the code below deliberately does/doesn't use):

| API | Status | What we do |
|-----|--------|-----------|
| `AVAudioSession.requestRecordPermission(_:)` | deprecated iOS 17 | use `AVAudioApplication.requestRecordPermission()` (iOS 17+, no `#available` needed) |
| `AVAudioSession.CategoryOptions.allowBluetooth` | deprecated in iOS 26 SDK, replaced by `.allowBluetoothHFP` | use `.allowBluetooth` (compiles on Xcode 16–27, warning only). Switch to `.allowBluetoothHFP` only if Xcode ≥ 26 is guaranteed |
| `AppIntent.openAppWhenRun` | deprecated 26.0 ("provide supportedModes") | declare in `@available(*, deprecated) extension` (Apple's recommended pattern) |
| `AppIntent.supportedModes`, `IntentModes` | iOS 26.0+ only | not used in v1 |
| `ForegroundContinuableIntent` | deprecated 26.0 | not used |
| `AVAudioNode.installTap(onBus:bufferSize:format:block:)` | deprecated 27.0 | still used (only warning on Xcode 27) |
| `View.onChange(of:perform:)` (1-param) | deprecated iOS 17 | use `onChange(of:initial:_:)` (2-param) |

---

## 1. Speech recognition (STT)

### 1.1 Facts

| Fact | Detail | Tag |
|------|--------|-----|
| Turkish supported by `SFSpeechRecognizer` | Turkish (Turkey) is a Dictation language; Speech framework supports the dictation locales. Always check at runtime: `SFSpeechRecognizer(locale:)` **falls back to the keyboard dictation language** if the locale is unsupported → verify `recognizer.locale.identifier.hasPrefix("tr")` | [VERIFIED: https://www.apple.com/ios/feature-availability/ , init doc https://developer.apple.com/documentation/speech/sfspeechrecognizer/init(locale:)] |
| On-device Turkish | Apple lists **Turkish** under "Dictation: On-Device and Modeless Dictation". `supportsOnDeviceRecognition` only becomes `true` once the model is downloaded (Wi-Fi, after Turkish dictation has been used) | [VERIFIED: https://www.apple.com/ios/feature-availability/] + [VERIFIED behaviour: https://developer.apple.com/forums/thread/703770] |
| Turkish auto-punctuation | **Not** in Apple's "Dictation: Auto-Punctuation" list → `addsPunctuation = true` will add little/none. Parser must not rely on punctuation | [VERIFIED: feature-availability page] |
| `requiresOnDeviceRecognition` | iOS 13+. Honoured only if `supportsOnDeviceRecognition == true`; otherwise **silently ignored** and audio may go to the network. "On-device requests won't be as accurate" | [VERIFIED: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition] |
| `addsPunctuation` | iOS 16.0+ | [VERIFIED: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/addspunctuation] |
| One-minute limit / quotas | Framework stops tasks longer than **1 minute**; per-device and per-app daily limits for the network service | [VERIFIED: SFSpeechRecognizer overview https://developer.apple.com/documentation/speech/sfspeechrecognizer] |
| Class not deprecated | iOS 27 doc metadata: `"deprecated": false` for class and `init(locale:)` | [VERIFIED: same] |
| iOS 18.0 bug | Partial results dropped text after a pause; fixed in 18.1 | [VERIFIED: https://developer.apple.com/forums/thread/764809] |
| Siri/Dictation must be enabled | Recognition fails (commonly `kLSRErrorDomain 201`) when Siri and Dictation are both off | [UNVERIFIED: community-reported error code] |

**Exact signatures used** (iOS 10+ unless noted):

```swift
// SFSpeechRecognizer
init?(locale: Locale)
class func requestAuthorization(_ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void)
class func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus
var isAvailable: Bool { get }
var supportsOnDeviceRecognition: Bool { get set }        // iOS 13
func recognitionTask(with request: SFSpeechRecognitionRequest,
                     resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void) -> SFSpeechRecognitionTask

// SFSpeechRecognitionRequest (superclass of SFSpeechAudioBufferRecognitionRequest)
var taskHint: SFSpeechRecognitionTaskHint                // .unspecified / .dictation / .search / .confirmation
var shouldReportPartialResults: Bool
var contextualStrings: [String]
var requiresOnDeviceRecognition: Bool                    // iOS 13
var addsPunctuation: Bool                                // iOS 16

// SFSpeechAudioBufferRecognitionRequest
func append(_ audioPCMBuffer: AVAudioPCMBuffer)
func endAudio()

// AVAudioApplication (iOS 17)
class func requestRecordPermission() async -> Bool
class func requestRecordPermission(completionHandler response: @escaping @Sendable (Bool) -> Void)
var recordPermission: AVAudioApplication.recordPermission { get }   // .undetermined / .denied / .granted  (via AVAudioApplication.shared)

// AVAudioSession
func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                 options: AVAudioSession.CategoryOptions = []) throws
func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions = []) throws
func setAllowHapticsAndSystemSoundsDuringRecording(_ inValue: Bool) throws   // iOS 13

// AVAudioNode
func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount,
                format: AVAudioFormat?, block tapBlock: @escaping AVAudioNodeTapBlock)
func removeTap(onBus bus: AVAudioNodeBus)
```
[VERIFIED: https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:) , https://developer.apple.com/documentation/avfaudio/avaudiosession/setcategory(_:mode:options:) , https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:) , https://developer.apple.com/documentation/avfaudio/avaudiosession/setallowhapticsandsystemsoundsduringrecording(_:)]

### 1.2 Info.plist keys (missing key = **SIGABRT crash** on first access)

| Key | Turkish value |
|-----|---------------|
| `NSMicrophoneUsageDescription` | `Asist, sesli komutlarınızı dinleyip hatırlatıcıya dönüştürmek için mikrofonu kullanır.` |
| `NSSpeechRecognitionUsageDescription` | `Söylediklerinizi yazıya çevirmek için konuşma tanıma kullanılır. Ses kaydı saklanmaz.` |

[VERIFIED: "If an application attempts to access any of the device's microphones without a corresponding purpose string, the app exits." — AVAudioApplication doc]

### 1.3 Audio session policy

| State | Category / mode / options | Effect on user's music |
|-------|--------------------------|------------------------|
| **Idle, volume trigger armed** (app foreground) | `.playback`, `.default`, `[.mixWithOthers]`, active | none (mixes) |
| **Listening** | `.playAndRecord`, `.measurement`, `[.defaultToSpeaker, .allowBluetooth]`, `setActive(true, options: .notifyOthersOnDeactivation)` | music **pauses** (non-mixable, like Siri) → better recognition; resumes when we deactivate with `.notifyOthersOnDeactivation` |
| **Speaking (TTS)** | none of ours — `usesApplicationAudioSession = false` lets the system session duck others | ducked |
| **Background** | `setActive(false, options: .notifyOthersOnDeactivation)` | — |

Notes / pitfalls:
* `.measurement` minimises system DSP (Apple's SpokenWord sample used `.record/.measurement`). Alternative if users want music to keep playing: add `.duckOthers` (lower accuracy in noise).
* **Haptics and system sounds are muted while the mic is live** unless `setAllowHapticsAndSystemSoundsDuringRecording(true)`. Fire the "start" haptic *before* activating, or set that flag.
* Always go **deactivate → setCategory → activate** when changing between a mixable and non-mixable category.
* `setActive(false)` fails ("session busy") while `AVAudioEngine` is running → stop the engine first.
* Recording cannot be *started* from the background → only start when `scenePhase == .active` (add a ~350 ms delay after activation when launched by an intent/URL). [UNVERIFIED: widely reported `cannotStartRecording`; device test]

### 1.4 Silence detection / auto-stop algorithm

1. `lastSpeechActivityAt = nil`, poll every 150 ms (Swift `Task` loop, no `Timer` → no Sendable issues).
2. Each new, *different* partial transcript → `lastSpeechActivityAt = now`.
3. Audio-energy guard: if speech already started and the normalised input level ≥ `speechLevelThreshold` (default 0.6 ≈ −24 dBFS), also refresh `lastSpeechActivityAt` (recogniser lagging while user still talks).
4. Stop (`endAudio()`, wait ≤ 1.5 s for `isFinal`, else use last partial) when `now − lastSpeechActivityAt ≥ silenceAfterSpeech` (default **1.8 s**; Settings: "Yavaş konuşuyorum" = 2.6 s).
5. If no speech after `noSpeechTimeout` (7 s) → `.noSpeech` ("Sizi duyamadım").
6. Hard cap `maxDuration` = 55 s (1-minute server limit).
7. Errors that arrive **after** we stopped (`kAFAssistantErrorDomain 216/1101`, `kLSRErrorDomain 301`) are ignored if we already have text.

### 1.5 Code — `Voice/VoicePermissions.swift` (app target)

```swift
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
}
```

### 1.6 Code — `Voice/AudioSessionConfigurator.swift` (app target)

```swift
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
```

### 1.7 Code — `Voice/SpeechListener.swift` (app target, full)

```swift
import AVFoundation
import Speech

struct ListenConfig {
    var localeIdentifier: String = "tr-TR"
    /// Konuşma başladıktan sonra yeni kısmi metin gelmezse bitirme süresi (sn).
    var silenceAfterSpeech: TimeInterval = 1.8
    /// Hiç konuşma algılanmazsa vazgeçme süresi (sn).
    var noSpeechTimeout: TimeInterval = 7.0
    /// Sunucu tanımasının 1 dakikalık sınırının altında kal.
    var maxDuration: TimeInterval = 55.0
    /// true: yalnız cihaz üzerinde tanı (model yüklüyse). Doğruluk biraz düşer.
    var onDeviceOnly: Bool = false
    /// Bu seviyenin üstündeki ses (0…1) "hâlâ konuşuyor" sayılır.
    var speechLevelThreshold: Float = 0.6
    /// Proje/müşteri adları, PLC terimleri... İlk 100 tanesi kullanılır.
    var contextualStrings: [String] = []
}

enum ListenOutcome: Equatable {
    case text(String)
    case noSpeech
    case failed(String)      // kullanıcıya gösterilecek Türkçe mesaj
    case cancelled
}

enum ListenerError: Error {
    case noAudioInput
}

/// Tap bloğu (ses thread'i) yazar, ana aktör okur.
final class AudioLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0

    func set(_ newValue: Float) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> Float { lock.lock(); defer { lock.unlock() }; return value }

    /// -60 dBFS → 0, 0 dBFS → 1
    static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))
        return max(0, min(1, (decibels + 60) / 60))
    }
}

@MainActor
final class SpeechListener: ObservableObject {
    enum State: Equatable { case idle, starting, listening, finishing }

    @Published private(set) var state: State = .idle
    @Published private(set) var partialText: String = ""
    @Published private(set) var level: Float = 0            // UI ses göstergesi

    private let engine = AVAudioEngine()
    private let levelBox = AudioLevelBox()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var monitor: Task<Void, Never>?
    private var continuation: CheckedContinuation<ListenOutcome, Never>?
    private var observers: [NSObjectProtocol] = []
    private var config = ListenConfig()
    private var startedAt = Date()
    private var lastSpeechActivityAt: Date?

    // MARK: Public API

    /// Tek seferlik dinleme. Sonuç gelene kadar bekler. Aynı anda ikinci çağrı `.cancelled` döner.
    func listen(config: ListenConfig) async -> ListenOutcome {
        guard state == .idle else { return .cancelled }
        guard VoicePermissions.isFullyAuthorized else {
            return .failed("Mikrofon veya konuşma tanıma izni yok. Ayarlar > Asist bölümünden izin verin.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: config.localeIdentifier)),
              recognizer.locale.identifier.hasPrefix("tr") else {
            return .failed("Türkçe konuşma tanıma bu cihazda bulunamadı.")
        }
        guard recognizer.isAvailable else {
            return .failed("Konuşma tanıma şu an kullanılamıyor. İnternet bağlantısını kontrol edin.")
        }
        self.config = config
        self.recognizer = recognizer
        partialText = ""
        state = .starting
        return await withCheckedContinuation { (continuation: CheckedContinuation<ListenOutcome, Never>) in
            self.continuation = continuation
            do {
                try self.beginSession(recognizer: recognizer)
            } catch {
                self.finish(.failed("Mikrofon başlatılamadı (\(error.localizedDescription))."))
            }
        }
    }

    /// Kullanıcı "Bitti"ye bastı: kalan sesi işle, sonucu döndür.
    func stopAndFinalize() {
        guard state == .listening else { return }
        state = .finishing
        monitor?.cancel()
        monitor = nil
        stopAudioEngine()
        request?.endAudio()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self = self, self.state == .finishing else { return }
            self.finish(self.partialText.isEmpty ? .noSpeech : .text(self.partialText))
        }
    }

    /// İptal (ekran kapandı, kullanıcı vazgeçti).
    func cancel() {
        finish(.cancelled)
    }

    // MARK: Session

    private func beginSession(recognizer: SFSpeechRecognizer) throws {
        try AudioSessionConfigurator.activateForListening()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true                       // Türkçe'de etkisi az/yok
        request.contextualStrings = Array(config.contextualStrings.prefix(100))
        if config.onDeviceOnly && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ListenerError.noAudioInput                  // 0 Hz formatla installTap çöker
        }
        input.removeTap(onBus: 0)                             // ikinci tap = çökme
        SpeechListener.installTap(on: input, format: format, request: request, levelBox: levelBox)
        engine.prepare()
        try engine.start()

        task = SpeechListener.startRecognition(recognizer: recognizer, request: request, owner: self)
        startedAt = Date()
        lastSpeechActivityAt = nil
        state = .listening
        observeAudioEvents()
        startMonitor()
    }

    /// nonisolated: blok @MainActor olarak çıkarsanmasın (ses thread'inde çalışır).
    nonisolated private static func installTap(on input: AVAudioInputNode,
                                               format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest,
                                               levelBox: AudioLevelBox) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            levelBox.set(AudioLevelBox.normalizedLevel(of: buffer))
        }
    }

    nonisolated private static func startRecognition(recognizer: SFSpeechRecognizer,
                                                     request: SFSpeechAudioBufferRecognitionRequest,
                                                     owner: SpeechListener) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error.map { $0 as NSError }
            let domain = nsError?.domain
            let code = nsError?.code
            Task { @MainActor [weak owner] in
                owner?.handleRecognition(text: text, isFinal: isFinal, errorDomain: domain, errorCode: code)
            }
        }
    }

    private func handleRecognition(text: String?, isFinal: Bool, errorDomain: String?, errorCode: Int?) {
        guard state == .listening || state == .finishing else { return }
        if let text = text, !text.isEmpty, text != partialText {
            partialText = text
            lastSpeechActivityAt = Date()
        }
        if isFinal {
            finish(partialText.isEmpty ? .noSpeech : .text(partialText))
        } else if let domain = errorDomain, let code = errorCode {
            if !partialText.isEmpty {
                finish(.text(partialText))                   // durdurma sonrası hatalar: eldekini kullan
            } else {
                finish(SpeechListener.outcome(forErrorDomain: domain, code: code))
            }
        }
    }

    // MARK: Silence monitor

    private func startMonitor() {
        monitor?.cancel()
        monitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let self = self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard state == .listening else { return }
        let now = Date()
        let currentLevel = levelBox.get()
        level = currentLevel
        if lastSpeechActivityAt != nil && currentLevel >= config.speechLevelThreshold {
            lastSpeechActivityAt = now
        }
        if now.timeIntervalSince(startedAt) >= config.maxDuration {
            stopAndFinalize()
        } else if let last = lastSpeechActivityAt {
            if now.timeIntervalSince(last) >= config.silenceAfterSpeech {
                stopAndFinalize()
            }
        } else if now.timeIntervalSince(startedAt) >= config.noSpeechTimeout {
            finish(.noSpeech)
        }
    }

    // MARK: Interruptions / route changes

    private func observeAudioEvents() {
        removeObservers()
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: session, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self = self, let raw = raw,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                self.finish(self.partialText.isEmpty ? .cancelled : .text(self.partialText))
            }
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: session, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self = self, let raw = raw,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
                if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable {
                    self.stopAndFinalize()                  // kulaklık takıldı/çıktı
                }
            }
        })

        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopAndFinalize()                      // motor kendini durdurdu
            }
        })
    }

    private func removeObservers() {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
    }

    // MARK: Teardown

    private func stopAudioEngine() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func finish(_ outcome: ListenOutcome) {
        guard state != .idle else { return }
        state = .idle
        monitor?.cancel()
        monitor = nil
        stopAudioEngine()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        removeObservers()
        level = 0
        AudioSessionConfigurator.deactivate()
        let pending = continuation
        continuation = nil
        pending?.resume(returning: outcome)                   // tam olarak bir kez
    }

    /// Hata kodları Apple tarafından belgelenmemiştir; yalnız mesaj seçimi için kullanılır.
    nonisolated static func outcome(forErrorDomain domain: String, code: Int) -> ListenOutcome {
        switch (domain, code) {
        case ("kAFAssistantErrorDomain", 1110):
            return .noSpeech
        case ("kAFAssistantErrorDomain", 216), ("kLSRErrorDomain", 301):
            return .cancelled
        case ("kLSRErrorDomain", 102):
            return .failed("Türkçe çevrimdışı konuşma modeli yüklü değil. 'Yalnız cihazda tanı' ayarını kapatın.")
        case ("kLSRErrorDomain", 201):
            return .failed("Siri ve Dikte kapalı. Ayarlar > Genel > Klavye > Dikte'yi açın.")
        default:
            return .failed("Konuşma anlaşılamadı (\(domain) \(code)). Tekrar deneyin.")
        }
    }
}
```

Error-code mapping: [UNVERIFIED: codes are community-observed (e.g. https://developer.apple.com/forums/thread/703770 for 102); treat as best-effort text selection only].

**Retry policy** (in the coordinator, not shown): if outcome is `.failed` and `onDeviceOnly == false` and the failure looks like a network error while `recognizer.supportsOnDeviceRecognition` is true → retry once with `onDeviceOnly = true`.

### 1.8 `contextualStrings` (vocabulary boost)

Up to 100 items. Seed with domain terms + the user's most recent project/customer/person names from the store:
`PLC, HMI, SCADA, TIA Portal, Siemens, S7-1500, S7-1200, Profinet, Profibus, servo, sürücü, pano, devreye alma, FAT, SAT, revizyon, teklif, sipariş, satınalma, bakım, arıza, OEE, I/O listesi, elektrik projesi` + names. [VERIFIED property: SFSpeechRecognitionRequest.contextualStrings; 100-cap is our choice]

### 1.9 iOS 26 `SpeechAnalyzer` / `SpeechTranscriber` — assessment

* `SpeechTranscriber` (iOS 26.0+): `convenience init(locale: Locale, preset: SpeechTranscriber.Preset)`, `static var isAvailable: Bool` (hardware), `static var supportedLocales: [Locale]`, `static var installedLocales: [Locale]`, `static func supportedLocale(equivalentTo: Locale) async -> Locale?`. Assets via `AssetInventory.assetInstallationRequest(supporting:)`. Apple says: if not available on the device, "consider … using `DictationTranscriber` instead". [VERIFIED: https://developer.apple.com/documentation/speech/speechtranscriber]
* Turkish: third-party lists of `SpeechTranscriber.supportedLocales` include **tr_TR** (42 locales / 22 languages). [UNVERIFIED: secondary source https://loronote.com/en/blog/apple-speechanalyzer-vs-whisper — check at runtime]
* `DictationTranscriber` "uses the same on-device model as SFSpeechRecognizer"; long-form `SpeechTranscriber` has no custom vocabulary. [UNVERIFIED: secondary https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer]
* **Recommendation:** v1 = SFSpeechRecognizer only (deployment 17, short utterances, contextual strings, no asset management, far fewer async/Sendable compile risks). v2 option: a `SpeechEngine` protocol with an `@available(iOS 26, *)` SpeechTranscriber implementation for long "toplantı notu" dictation (> 1 min) when `SpeechTranscriber.isAvailable` and tr is installed.

---

## 2. Speech output (TTS)

Facts:
* `AVSpeechSynthesisVoice(language: "tr-TR")` returns the default Turkish voice or `nil`. Enhanced/premium voices must be downloaded by the user (Ayarlar > Erişilebilirlik > Seslendirilen İçerik > Sesler > Türkçe). `AVSpeechSynthesisVoiceQuality.premium` is iOS 16+.
* `usesApplicationAudioSession` (iOS 13): "If you set this value to `false`, the system creates a separate audio session to automatically manage speech, interruptions, and mixing and ducking the speech with other audio sources." [VERIFIED: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/usesapplicationaudiosession]
* "The system doesn't automatically retain the speech synthesizer" → keep a strong reference. [VERIFIED: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer]
* Delegate: `optional func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)` and `…didCancel utterance:`.
* **Hand-off rule:** never start listening until `didFinish`/`didCancel` has arrived (otherwise TTS is recorded). `SpeechListener.listen` is only called after `await speaker.speak(...)` returns.

### 2.1 Code — `Voice/Speaker.swift` (app target)

```swift
import AVFoundation

@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()          // güçlü referans şart
    private var continuation: CheckedContinuation<Void, Never>?
    private var currentID: ObjectIdentifier?

    // Bilerek `override init()` YOK: @MainActor sınıfta NSObject.init'i ezmek
    // Swift 6 derleyicisinde izolasyon uyarısı/hatası üretebilir. Kurulum ilk speak()'te yapılır.
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

    /// Konuşma bitene (veya iptal edilene) kadar bekler.
    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configureIfNeeded()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Speaker.bestTurkishVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.1
        isSpeaking = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation?.resume()                        // önceki bekleyeni serbest bırak
            self.continuation = continuation
            self.currentID = ObjectIdentifier(utterance)
            self.synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.complete(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.complete(id) }
    }

    private func complete(_ id: ObjectIdentifier) {
        guard id == currentID else { return }                // eski (iptal edilmiş) cümlenin geri çağrısı
        currentID = nil
        isSpeaking = false
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
```

Confirmation sentences are short and scannable, e.g. `"Tamam. Salı 15.00'te: teklif."`, `"Not olarak kaydettim; tarihi anlayamadım."`. Speaking is a Settings toggle ("Sesli onay", default on). [UNVERIFIED: device test that `usesApplicationAudioSession = false` ducks Spotify/Music correctly on iOS 26]

---

## 3. Volume-down ×2 trigger (foreground only)

### 3.1 What is and is not possible

* **Not possible:** detecting volume buttons while the app is in the background, suspended, killed, or on the Lock Screen. The only "workaround" (a background-audio silent loop keeping a session active) is (a) against App Review 2.5.4/2.5.9, (b) battery-draining, (c) broken by any non-mixable audio app, and (d) **useless anyway** because an app cannot *start* microphone recording from the background. → Rejected. System-wide triggers are covered in §4 and §5. [VERIFIED 2.5.9: https://developer.apple.com/app-store/review/guidelines/ ; (d) UNVERIFIED-strong]
* **Possible (foreground):** KVO on `AVAudioSession.sharedInstance().outputVolume` (`var outputVolume: Float { get }`, iOS 6+, "Monitor changes … using key-value observing"). Requires an **active** session. [VERIFIED: https://developer.apple.com/documentation/avfaudio/avaudiosession/outputvolume]
* Category: `.playback` + `.mixWithOthers` (what JPSVolumeButtonHandler uses; does not interrupt the user's music). `.ambient` may leave the buttons controlling the *ringer* instead of media volume → not chosen. [VERIFIED impl.: https://raw.githubusercontent.com/jpsim/JPSVolumeButtonHandler/master/JPSVolumeButtonHandler/JPSVolumeButtonHandler.m ; ringer behaviour UNVERIFIED]

### 3.2 Limits and mitigations

| Problem | Behaviour | Mitigation |
|---------|-----------|-----------|
| Volume already 0 | no KVO event at all | show banner "Ses çok kısık — çift basış algılanamaz" + button "Sesi 4 kademeye çıkar" (`setSystemVolume(0.25)`) |
| Volume = 1 step (0.0625) | only 1st press produces an event | same banner when `volume < 0.12` |
| User **holds** the button | repeated events | confirm only if no 3rd event within 300 ms; then 0.8 s cooldown |
| Each trigger lowers volume 2 steps | annoying | restore previous volume via hidden `MPVolumeView` slider after firing (default on) |
| iOS 18 regression: `outputVolume` stale after re-activation | reads can be wrong, **events still fire** | use `change.oldValue/newValue` from KVO; read current value from the `MPVolumeView` slider |
| System volume HUD | shows on each press | an `MPVolumeView` in the hierarchy (not hidden, alpha > 0) suppresses it; our 1-pt anchor with alpha 0.01 is expected to suppress it |
| App Review 2.5.9 | altering volume-button behaviour is rejectable | irrelevant for sideloading; if ever submitted, drop HUD-suppression + volume-restore |
| During listening/TTS | category changes | `disarm()` before listening, `arm()` after |

Sources: [VERIFIED: iOS 18 stale value — https://developer.apple.com/forums/thread/799104 ("KVO events still fire"), https://developer.apple.com/forums/thread/813242 (MPVolumeView must be in hierarchy)]; [UNVERIFIED on iOS 26: setting `UISlider.value` of `MPVolumeView` changes system volume; HUD suppression with alpha 0.01 — device test].

### 3.3 Code — `Voice/VolumeButtonTrigger.swift` (app target, full)

```swift
import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class VolumeButtonTrigger: ObservableObject {
    @Published private(set) var isArmed = false
    /// true → iki "kısma" olayı algılanamayacak kadar düşük ses.
    @Published private(set) var volumeTooLow = false

    var onDoublePress: (() -> Void)?
    var pressWindow: TimeInterval = 1.0          // kullanıcı şartı: max 1 sn
    var confirmDelay: TimeInterval = 0.3         // basılı tutmayı ayırt etmek için
    var cooldown: TimeInterval = 1.5
    var restoreVolumeAfterTrigger = true

    private var observation: NSKeyValueObservation?
    private var interruptionToken: NSObjectProtocol?
    private var firstDownAt: Date?
    private var volumeBeforeGesture: Float?
    private var pendingConfirm: Task<Void, Never>?
    private var cooldownUntil = Date.distantPast
    private var ignoreUntil = Date.distantPast
    private weak var volumeView: MPVolumeView?

    func attach(_ view: MPVolumeView) {
        volumeView = view
    }

    func arm() {
        guard !isArmed else { return }
        do {
            try AudioSessionConfigurator.activateForVolumeTrigger()
        } catch {
            return
        }
        observation = VolumeButtonTrigger.observeOutputVolume(owner: self)
        observeInterruptions()
        isArmed = true
        updateLowVolumeFlag(currentVolume())
    }

    func disarm() {
        observation?.invalidate()
        observation = nil
        if let token = interruptionToken {
            NotificationCenter.default.removeObserver(token)
            interruptionToken = nil
        }
        resetGesture()
        isArmed = false
    }

    func currentVolume() -> Float {
        if let slider = volumeSlider() { return slider.value }
        return AVAudioSession.sharedInstance().outputVolume
    }

    /// Gizli MPVolumeView kaydırıcısı ile sistem sesini ayarlar (resmî API değildir).
    func setSystemVolume(_ value: Float) {
        guard let slider = volumeSlider() else { return }
        ignoreUntil = Date().addingTimeInterval(0.6)          // kendi değişikliğimizi yok say
        slider.setValue(min(max(value, 0), 1), animated: false)
        slider.sendActions(for: .valueChanged)
    }

    func raiseVolumeForDetection() {
        setSystemVolume(0.25)
    }

    // MARK: Private

    private func volumeSlider() -> UISlider? {
        volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    nonisolated private static func observeOutputVolume(owner: VolumeButtonTrigger) -> NSKeyValueObservation {
        AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.old, .new]) { [weak owner] _, change in
            guard let old = change.oldValue, let new = change.newValue else { return }
            Task { @MainActor [weak owner] in
                owner?.volumeChanged(from: old, to: new)
            }
        }
    }

    private func observeInterruptions() {
        interruptionToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self = self, self.isArmed, let raw = raw,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                try? AudioSessionConfigurator.activateForVolumeTrigger()   // arama/alarm sonrası yeniden etkinleştir
            }
        }
    }

    private func volumeChanged(from old: Float, to new: Float) {
        updateLowVolumeFlag(new)
        let now = Date()
        guard now >= ignoreUntil else { return }
        guard new < old else {                                  // "açma" tuşu hareketi iptal eder
            resetGesture()
            return
        }
        guard now >= cooldownUntil else { return }

        if let first = firstDownAt, now.timeIntervalSince(first) <= pressWindow {
            if pendingConfirm != nil {                          // 3. olay → basılı tutuluyor
                resetGesture()
                cooldownUntil = now.addingTimeInterval(0.8)
                return
            }
            let delay = UInt64(confirmDelay * 1_000_000_000)
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
        if restoreVolumeAfterTrigger, let value = restoreTo {
            setSystemVolume(value)
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
        volumeTooLow = volume < 0.12                            // < 2 kademe (1/16 = 0.0625)
    }
}

/// Kök görünümün arkasına 1 pt olarak eklenir: HUD'u bastırır ve kaydırıcıya erişim sağlar.
struct SystemVolumeAnchor: UIViewRepresentable {
    let trigger: VolumeButtonTrigger

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.01                                       // 0 veya isHidden → HUD bastırılmaz
        view.isUserInteractionEnabled = false
        trigger.attach(view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
```

### 3.4 Code — `Voice/VoiceCaptureCoordinator.swift` (app target, glue)

```swift
import Foundation
import UIKit

@MainActor
final class VoiceCaptureCoordinator: ObservableObject {
    let listener = SpeechListener()
    let speaker = Speaker()
    let trigger = VolumeButtonTrigger()

    @Published private(set) var isBusy = false
    @Published private(set) var lastMessage: String?

    var listenConfig = ListenConfig()
    var volumeTriggerEnabled = true
    var speakConfirmations = true
    /// App tarafından atanır: ayrıştır + kaydet + bildirim planla → Türkçe onay cümlesi.
    var handleTranscript: @MainActor (String) async -> String = { _ in "" }

    init() {
        trigger.onDoublePress = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.startListening()
            }
        }
    }

    func sceneDidBecomeActive() {
        if volumeTriggerEnabled && !isBusy {
            trigger.disarm()                                    // oturumu tazele
            trigger.arm()
        }
        consumePendingRoute()
    }

    func sceneDidEnterBackground() {
        trigger.disarm()
        listener.cancel()
        speaker.stop()
        AudioSessionConfigurator.deactivate()
    }

    func consumePendingRoute() {
        guard LaunchRouter.shared.pending == .listen else { return }
        _ = LaunchRouter.shared.take()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)      // sahnenin tam aktif olmasını bekle
            await self?.startListening()
        }
    }

    func startListening() async {
        guard !isBusy else { return }
        isBusy = true
        trigger.disarm()
        speaker.stop()
        lastMessage = nil
        let outcome = await listener.listen(config: listenConfig)
        switch outcome {
        case .text(let transcript):
            let confirmation = await handleTranscript(transcript)
            lastMessage = confirmation
            if speakConfirmations && !confirmation.isEmpty {
                await speaker.speak(confirmation)
            }
        case .noSpeech:
            lastMessage = "Sizi duyamadım. Tekrar deneyin."
        case .failed(let message):
            lastMessage = message
        case .cancelled:
            break
        }
        isBusy = false
        if volumeTriggerEnabled && UIApplication.shared.applicationState == .active {
            trigger.arm()
        }
    }
}
```

---

## 4. App Intents, Siri, Shortcuts, Back Tap

### 4.1 Exact API facts

```swift
// protocol AppIntent (iOS 16)
static var title: LocalizedStringResource { get }
static var description: IntentDescription? { get }
func perform() async throws -> Self.PerformResult          // PerformResult: IntentResult
static var parameterSummary: Self.SummaryContent { get }
static var authenticationPolicy: IntentAuthenticationPolicy { get }   // .alwaysAllowed / .requiresAuthentication / .requiresLocalDeviceAuthentication
static var isDiscoverable: Bool { get }
static var openAppWhenRun: Bool { get }                    // DEPRECATED 26.0 "Please provide 'supportedModes' instead"
static var supportedModes: IntentModes { get }             // iOS 26.0+ only
init()                                                      // required

// results
static func result() -> Self
static func result(dialog: IntentDialog) -> Self
static func result(opensIntent: some AppIntent) -> Self
// IntentDialog: init(_: LocalizedStringResource), ExpressibleByStringLiteral, ExpressibleByStringInterpolation

// AppShortcutsProvider
static var appShortcuts: [AppShortcut] { get }             // use @AppShortcutsBuilder
static func updateAppShortcutParameters()
// AppShortcut
init<Intent>(intent: Intent, phrases: [AppShortcutPhrase<Intent>],
             shortTitle: LocalizedStringResource, systemImageName: String)

// LiveActivityIntent (iOS 17.0): protocol LiveActivityIntent : SystemIntent
// OpenURLIntent (iOS 18.0): init(_ url: URL) — universal links only
// SiriTipView (iOS 16): init<Intent>(intent: Intent, isVisible: Binding<Bool>?)
// ShortcutsLink (iOS 16): init(action: () -> Void)
```
[VERIFIED: https://developer.apple.com/documentation/appintents/appintent , …/appintent/openappwhenrun , …/appintent/supportedmodes , …/intentmodes , …/intentresult , …/intentdialog , …/appshortcut , …/appshortcutsprovider , …/liveactivityintent , …/openurlintent , …/siritipview , …/shortcutslink , …/intentauthenticationpolicy]

Key rules:
1. **`openAppWhenRun` back-compat pattern** (Apple doc, verbatim shape): `@available(*, deprecated) extension X { static var openAppWhenRun: Bool { true } }`. Works on iOS 17–26+, no warning. [VERIFIED]
2. **Phrase rules:** every phrase must contain `\(.applicationName)` **exactly once**; missing it silently kills the phrase (or fails the build). Phrase parameters may only be `AppEntity`/`AppEnum` — **a free-form `String` cannot be in a phrase** ("Parameters are not meant for open-ended values"). So Siri asks for the text via `requestValueDialog`. [VERIFIED: WWDC22 10170 https://developer.apple.com/videos/play/wwdc2022/10170/ ; PR notes https://github.com/cli-pulse/cli-pulse-private/pull/567]
3. Intents backing App Shortcuts **must be declared in the main app target** (not in the `AsistCore` SwiftPM package). [VERIFIED: DTS reply https://developer.apple.com/forums/thread/768900]
4. Put `@AppShortcutsBuilder` explicitly on `appShortcuts` (reported: without it Siri only saw the first shortcut). [VERIFIED: https://developer.apple.com/forums/thread/757370]
5. Only **one** `AppShortcutsProvider`, app target only. Max **10** App Shortcuts. [UNVERIFIED: limits from memory of Apple docs; we use 3]
6. Flexible matching (iOS 17+) needs build setting `APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING = YES` and iOS 17 deployment. [VERIFIED: WWDC23 10102, https://developer.apple.com/forums/thread/731851]. Whether flexible matching works for **Turkish**: [UNVERIFIED].
7. Where intents run:
   * Intent in the app target run by Siri/Shortcuts/Spotlight → **app process** (launched in background if needed; no UI). Same container, same singletons → direct store access.
   * `Button(intent:)` in a widget → **widget extension process**, unless the intent adopts `LiveActivityIntent`/`AudioPlaybackIntent` → then **app process**. [VERIFIED: https://developer.apple.com/documentation/appintents/liveactivityintent ("the system launches your app process without opening the app, performs the intent"), https://zachwaugh.com/posts/forcing-appintent-to-run-in-main-app-process]
   * ControlWidget button with an intent that opens the app → the intent file must be a member of **both** app and widget targets. [VERIFIED: Apple article "Creating controls to perform actions across the system" https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system]
   * `OpenURLIntent` from a control only supports **universal links**, not custom schemes → unusable for us (no Associated Domains). [VERIFIED: https://developer.apple.com/forums/thread/762586 summary, https://onmyway133.com/posts/how-to-open-app-with-control-widget-on-ios-18/]
8. Locked device: background intents run while locked under the default policy (`.alwaysAllowed` semantics); intents that open the app require unlock. Therefore the **store file must not use `.complete` file protection** — use the default `completeUntilFirstUserAuthentication`, or Siri-from-Lock-Screen saves will fail. [VERIFIED policy cases: IntentAuthenticationPolicy doc; file-protection consequence = design inference]

### 4.2 Shared compile flag

App target only: `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) ASIST_APP`. Intent files that are also compiled into the widget extension wrap app-only calls in `#if ASIST_APP`. In the widget build those bodies become no-ops (they never execute there: `openAppWhenRun` / `LiveActivityIntent` route execution to the app).

### 4.3 Code — `App/LaunchRouter.swift` (app target)

Deliberately **not** `@MainActor` (avoids isolation errors in property initialisers); contract: touch only on the main thread (intents' `perform` are `@MainActor`, `onOpenURL` is main).

```swift
import Foundation

final class LaunchRouter: ObservableObject {
    static let shared = LaunchRouter()

    enum Action: Equatable {
        case listen
        case today
        case reminder(String)
    }

    @Published var pending: Action?

    private init() {}

    func request(_ action: Action) {
        pending = action
    }

    func take() -> Action? {
        let action = pending
        pending = nil
        return action
    }

    /// asist://dinle · asist://bugun · asist://kayit/<id>
    func handle(url: URL) {
        guard url.scheme == AsistDeepLink.scheme else { return }
        switch url.host {
        case "dinle":
            request(.listen)
        case "bugun":
            request(.today)
        case "kayit":
            let id = url.lastPathComponent
            if !id.isEmpty && id != "/" { request(.reminder(id)) }
        default:
            break
        }
    }
}
```

### 4.4 Code — `Shared/AsistDeepLink.swift` (app + widget)

```swift
import Foundation

enum AsistDeepLink {
    static let scheme = "asist"
    static let listen = URL(string: "asist://dinle")!
    static let today = URL(string: "asist://bugun")!

    static func reminder(_ id: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "kayit"
        components.path = "/" + id
        return components.url ?? today
    }
}
```

### 4.5 Code — `App/AppServices.swift` (app target) — contract for other modules

The intents need one lazily self-constructing entry point (the app may be launched in the background purely to run an intent — do not depend on UI having been built). Internals belong to the data/notification/parser docs.

```swift
import Foundation

enum CaptureSource: String, Codable {
    case app, siri, shortcut, widget
}

@MainActor
final class AppServices {
    static let shared = AppServices()

    private init() {
        // Store (app's own Application Support), NotificationScheduler, AsistCore parser — lazily.
    }

    /// Ayrıştır → kaydet → nag bildirimlerini planla → widget snapshot yaz → WidgetCenter reload.
    /// Düşük güvenli ayrıştırmada yine de "Gelen Kutusu" notu olarak kaydeder.
    /// Dönen değer: Siri/TTS için kısa Türkçe onay cümlesi.
    func capture(text: String, source: CaptureSource) async -> String {
        // implemented in data/parser layer
        return "Kaydettim: \(text)"
    }

    /// Tamamlandı: bekleyen/tekrarlayan bildirimleri iptal et, snapshot + widget yenile.
    func markDone(id: String) async {
        // implemented in data/notification layer
    }

    /// "Bugün 3 işiniz var; 1 tanesi gecikmiş: ..." gibi kısa sözlü özet.
    func todayBriefing() async -> String {
        // implemented in data layer
        return "Bugün için kayıtlı iş yok."
    }
}
```

Siri runs the intent under a time budget; **do not call the optional Claude API ("Akıllı Mod") synchronously inside `perform()`** — save the rule-based result immediately, mark it `needsRefinement`, refine next time the app is foreground. [UNVERIFIED: exact Siri timeout; design precaution]

### 4.6 Code — `Shared/Intents/DinleIntent.swift` (app + widget targets)

```swift
import AppIntents

struct DinleIntent: AppIntent {
    static let title: LocalizedStringResource = "Asist'i Dinlet"
    static let description = IntentDescription("Asist'i açar ve sesli komut dinlemeye başlar.")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if ASIST_APP
        LaunchRouter.shared.request(.listen)       // UI: scenePhase .active olunca dinlemeye başlar
        #endif
        return .result()
    }
}

@available(*, deprecated)
extension DinleIntent {
    static var openAppWhenRun: Bool { true }
}
```

How the UI starts listening: `perform()` runs in the app process after the system brings the app forward; it only sets `LaunchRouter.shared.pending = .listen`. `@Published` replays its current value to new subscribers, so a cold launch also works: `RootView` consumes it on `scenePhase == .active` (§4.11). Same path for `asist://dinle` via `.onOpenURL`.

### 4.7 Code — `App/Intents/KaydetIntent.swift` (app target only)

```swift
import AppIntents

struct KaydetIntent: AppIntent {
    static let title: LocalizedStringResource = "Asist'e Kaydet"
    static let description = IntentDescription("Söylediğinizi hatırlatıcı, görev veya not olarak kaydeder. Uygulama açılmaz.")

    @Parameter(title: "Metin", requestValueDialog: IntentDialog("Ne kaydedeyim?"))
    var metin: String

    static var parameterSummary: some ParameterSummary {
        Summary("Kaydet: \(\.$metin)")
    }

    init() {}

    init(metin: String) {
        self.metin = metin
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: "Boş bir şey kaydedemedim. Tekrar söyler misiniz?")
        }
        let confirmation = await AppServices.shared.capture(text: text, source: .siri)
        return .result(dialog: "\(confirmation)")
    }
}
```
Siri flow: "Hey Siri, Asist'e kaydet" → Siri: "Ne kaydedeyim?" → user: "Salı günü teklif konusunu bana saat 3'te hatırlat" → Siri transcribes (its own Turkish STT) → `perform()` in background → Siri says the confirmation. Runs on the Lock Screen, AirPods and CarPlay. [VERIFIED pattern: `@Parameter(title:requestValueDialog:)` — https://developer.apple.com/forums/thread/731809 ; Turkish end-to-end UNVERIFIED — device test]

### 4.8 Code — `App/Intents/BugunIntent.swift` (app target only)

```swift
import AppIntents

struct BugunIntent: AppIntent {
    static let title: LocalizedStringResource = "Bugün Neler Var?"
    static let description = IntentDescription("Bugünkü ve geciken hatırlatmaları sesli özetler.")
    /// İş verisini kilitli ekranda sesli okumasın.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let briefing = await AppServices.shared.todayBriefing()
        return .result(dialog: "\(briefing)")
    }
}
```

### 4.9 Code — `Shared/Intents/TamamlaIntent.swift` (app + widget targets)

```swift
import AppIntents
#if ASIST_APP
import WidgetKit
#endif

/// Widget'taki "Tamam" düğmesi. LiveActivityIntent → uygulama sürecinde çalışır:
/// asıl depo + UNUserNotificationCenter doğrudan erişilebilir (App Group gerekmez).
struct TamamlaIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Hatırlatmayı Tamamla"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Kayıt")
    var kayitID: String

    init() {}

    init(kayitID: String) {
        self.kayitID = kayitID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if ASIST_APP
        await AppServices.shared.markDone(id: kayitID)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return .result()
    }
}
```
[UNVERIFIED: device test that on iOS 26 the widget button executes in the app process when the app is not running; fallback if not: make it a no-UI `DinleIntent`-style opener to `asist://kayit/<id>`.]

### 4.10 Code — `App/Intents/AsistShortcuts.swift` (app target only)

```swift
import AppIntents

struct AsistShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: KaydetIntent(),
            phrases: [
                "\(.applicationName)'e kaydet",
                "\(.applicationName) kaydet",
                "\(.applicationName)'e not al",
                "\(.applicationName) ile hatırlatıcı kur",
                "\(.applicationName) hatırlat"
            ],
            shortTitle: "Kaydet",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: DinleIntent(),
            phrases: [
                "\(.applicationName) dinle",
                "\(.applicationName) beni dinle",
                "\(.applicationName) ile konuş"
            ],
            shortTitle: "Dinle",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: BugunIntent(),
            phrases: [
                "\(.applicationName) bugün neler var",
                "\(.applicationName)'te bugün ne var",
                "\(.applicationName) günümü özetle"
            ],
            shortTitle: "Bugün",
            systemImageName: "calendar"
        )
    }
}
```
Avoid phrases like "Asist'i aç" — Siri's built-in "open app" wins and our intent never runs. Call `AsistShortcuts.updateAppShortcutParameters()` once in `App.init()` (harmless; strictly needed only for entity parameters).

### 4.11 Code — root wiring (app target)

```swift
import SwiftUI

@main
struct AsistApp: App {
    init() {
        AsistShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var voice = VoiceCaptureCoordinator()
    @ObservedObject private var router = LaunchRouter.shared
    @AppStorage("volumeTriggerEnabled") private var volumeTriggerEnabled = true

    var body: some View {
        MainScreen(voice: voice)                               // defined by UI doc
            .background {
                if volumeTriggerEnabled {
                    SystemVolumeAnchor(trigger: voice.trigger)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    voice.volumeTriggerEnabled = volumeTriggerEnabled
                    voice.sceneDidBecomeActive()
                case .background:
                    voice.sceneDidEnterBackground()
                default:
                    break                                      // .inactive: Denetim Merkezi vb.; dinlemeyi kesme
                }
            }
            .onChange(of: router.pending) { _, newValue in
                if newValue == .listen && scenePhase == .active {
                    voice.consumePendingRoute()
                }
            }
            .onOpenURL { url in
                router.handle(url: url)
            }
    }
}
```

Discovery UI (Settings screen): `SiriTipView(intent: KaydetIntent(), isVisible: $showSiriTip)` and `ShortcutsLink(action: {})`. SiriTipView shows empty if the intent is not part of an `AppShortcut`. [VERIFIED: SiriTipView doc]

### 4.12 Making phrases work in **Turkish Siri**

Facts: Siri and the Shortcuts app use the **system/Siri language**, not an in-app language switch. Phrases are **extracted at build time** by the App Intents metadata processor; localized phrases come from `AppShortcuts.strings` (legacy, per-`.lproj`) or the `AppShortcuts` **String Catalog** (`AppShortcuts.xcstrings`, iOS 17+). "Simply create a new String Catalog called 'AppShortcuts'. After rebuilding your app, you will see the phrases … populated automatically." [VERIFIED: WWDC23 10102 https://developer.apple.com/videos/play/wwdc2023/10102/ , DTS https://www.developer.apple.com/forums/thread/803490 , https://phrase.com/blog/posts/siri-shortcuts-localization-tutorial/]

Recipe (CI-deterministic, no Xcode IDE needed):
1. XcodeGen `options.developmentLanguage: tr`; Info.plist `CFBundleDevelopmentRegion = $(DEVELOPMENT_LANGUAGE)` (→ `tr`), `CFBundleDisplayName = Asist`. Phrases are written in Turkish in code (§4.10).
2. Add **`App/Resources/tr.lproj/AppShortcuts.strings`** (UTF-8) with an identity mapping. Keys = code phrase with `\(.applicationName)` → `${applicationName}`; **straight ASCII apostrophe `'`** in both code and file (a typographic `’` makes the key not match → build error "This AppShortcut does not map to a known action"):
   ```
   "${applicationName}'e kaydet" = "${applicationName}'e kaydet";
   "${applicationName} kaydet" = "${applicationName} kaydet";
   "${applicationName}'e not al" = "${applicationName}'e not al";
   "${applicationName} ile hatırlatıcı kur" = "${applicationName} ile hatırlatıcı kur";
   "${applicationName} hatırlat" = "${applicationName} hatırlat";
   "${applicationName} dinle" = "${applicationName} dinle";
   "${applicationName} beni dinle" = "${applicationName} beni dinle";
   "${applicationName} ile konuş" = "${applicationName} ile konuş";
   "${applicationName} bugün neler var" = "${applicationName} bugün neler var";
   "${applicationName}'te bugün ne var" = "${applicationName}'te bugün ne var";
   "${applicationName} günümü özetle" = "${applicationName} günümü özetle";
   ```
   Do **not** also add `AppShortcuts.xcstrings` (two tables with the same name). If a CI build error appears for this file, delete it — step 1 alone is expected to suffice. [UNVERIFIED: whether the processor treats in-code phrases as the development-language (tr) locale without the file — hence belt-and-braces]
3. Intent titles/`shortTitle`/dialogs are `LocalizedStringResource` literals → resolved from `tr` `Localizable` (falls back to the Turkish literal).
4. App-name synonyms: `.applicationName` also matches configured synonyms. Add to Info.plist:
   ```xml
   <key>INAlternativeAppNames</key>
   <array>
     <dict>
       <key>INAlternativeAppName</key><string>Asistan</string>
       <key>INAlternativeAppNamePronunciationHint</key><string>asistan</string>
     </dict>
   </array>
   ```
   [VERIFIED synonyms supported: WWDC22 10170 transcript; effect in Turkish UNVERIFIED]
5. Siri entitlement: Apple documents `com.apple.developer.siri` as required only for SiriKit Intents extensions "other than shortcut requests"; one developer reports Siri voice invocation of App Intents failing without it. Plan: **ship without it first**; if Shortcuts-app runs work but voice doesn't, add `com.apple.developer.siri = true` to the app entitlements (Apple's capability table lists Siri as available for the free "Apple Developer" membership). [VERIFIED doc text: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.siri ; counter-report UNVERIFIED: https://github.com/Redth/Maui.Apple.PlatformFeature.Samples/issues/1 ; table: https://developer.apple.com/help/account/reference/supported-capabilities-ios]
6. **Guaranteed fallback** if Turkish App Shortcut phrases don't match: a *user* Shortcut is invocable by its **name** in any Siri language — create shortcut "Asist Kaydet" containing the "Asist'e Kaydet" action → "Hey Siri, Asist Kaydet". [UNVERIFIED: standard Shortcuts behaviour, not re-checked for iOS 26 Turkish]

### 4.13 Shortcuts app, Back Tap (Arkaya Dokun) — user steps (Turkish)

App Shortcuts appear automatically (no setup) in Kestirmeler, Spotlight and Siri as soon as the app is installed. Back Tap's settings list offers "Kestirmeler" = shortcuts in the user's own library; Apple docs only say "choose a shortcut", and do not state that apps' App Shortcuts appear there directly. → **Always create a one-action user shortcut first.** [VERIFIED path: https://support.apple.com/tr-tr/111772 , https://support.apple.com/guide/shortcuts/run-shortcuts-tapping-iphone-apd897693606/ios ; direct App Shortcut listing UNVERIFIED]

**A) Uygulama açılmadan sesli kayıt (önerilen)** — iOS 17/18/26:
1. **Kestirmeler** uygulamasını açın → sağ üstte **+** → **Eylem Ekle**.
2. Aramaya **"Dikte"** yazın → **Metni Dikte Et** eylemini ekleyin. Eylemin ayrıntısında **Dil: Türkçe**, **Dinlemeyi Durdur: Duraklamadan Sonra** seçin.
3. Tekrar aramaya **"Asist"** yazın → **Asist'e Kaydet** eylemini ekleyin; **Metin** alanına dokunup **Dikte Edilen Metin** değişkenini seçin.
4. Kestirmenin adını **"Asist Hızlı Kayıt"** yapın → **Bitti**.
5. **Ayarlar > Erişilebilirlik > Dokunma > Arkaya Dokun > Çift Dokunma** → aşağıdaki **Kestirmeler** bölümünden **Asist Hızlı Kayıt**'ı seçin.
6. Kullanım: telefonun arkasına 2 kez vurun → konuşun → susunca Asist kaydeder ve üstte onay gösterir.

**B) Asist'i açıp dinlet (sesli onaylı tam akış):** 1–4. adımlarda yalnız **Asist'i Dinlet** eylemini ekleyip adını "Asist Dinle" yapın; 5. adımda **Üç Kez Dokunma**'ya atayın.

**C) Siri:** Ayarlar > Siri: dil **Türkçe**, "Hey Siri" açık. "Hey Siri, **Asist'e kaydet**" → Siri "Ne kaydedeyim?" diye sorar.

**D) iOS 18+ Denetim Merkezi / Kilit Ekranı düğmesi:** Denetim Merkezi'ni aşağı çekin → boş alana basılı tutun → **Denetim Ekle** → "Asist" arayın → **Asist'i Dinlet**. Kilit ekranı için: kilit ekranına basılı tutun → **Özelleştir** → **Kilitli Ekran** → alttaki fener/kamera düğmesini **−** ile kaldırın → **+** → **Asist'i Dinlet**.

[UNVERIFIED: exact Turkish labels "Eylem Ekle", "Metni Dikte Et", "Dikte Edilen Metin", "Denetim Ekle" on iOS 26 — verify on device and adjust the in-app help text]

---

## 5. WidgetKit and Controls

### 5.1 Facts

| Item | Signature / fact | Tag |
|------|------------------|-----|
| Container background (iOS 17, required or the widget shows an "adopt containerBackground" placeholder) | `func containerBackground<V: View>(for container: ContainerBackgroundPlacement, alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View`; also `containerBackground(_ style: some ShapeStyle, for:)` | [VERIFIED: https://developer.apple.com/documentation/swiftui/view/containerbackground(for:alignment:content:)] |
| Interactive button (iOS 17) | `init<I: AppIntent>(intent: I, @ViewBuilder label: () -> Label)` — file must `import AppIntents` | [VERIFIED: https://developer.apple.com/documentation/swiftui/button/init(intent:label:)] |
| `Link` in `systemSmall` | not supported — use `widgetURL` (small = one tap target) | [UNVERIFIED: long-standing WidgetKit rule] |
| Custom URL scheme via `widgetURL`/`Link` | works (only `OpenURLIntent` needs universal links) | [VERIFIED: Apple DTS "widgetURL works just fine" https://developer.apple.com/forums/thread/764706] |
| `ControlWidget` (iOS 18) | `@MainActor @preconcurrency protocol ControlWidget { associatedtype Body: ControlWidgetConfiguration; var body: Body }` | [VERIFIED: https://developer.apple.com/documentation/swiftui/controlwidget] |
| `StaticControlConfiguration` (iOS 18) | `init(kind: String, content: () -> Content)` | [VERIFIED: https://developer.apple.com/documentation/widgetkit/staticcontrolconfiguration] |
| Control modifiers (iOS 18) | `.displayName(_: LocalizedStringResource)`, `.description(_: LocalizedStringResource)` | [VERIFIED: https://developer.apple.com/documentation/swiftui/controlwidgetconfiguration] |
| `ControlWidgetButton` | `init(action: Action, label: () -> Label)`; "stateless, fire-and-forget … launching an app" | [VERIFIED: https://developer.apple.com/documentation/widgetkit/controlwidgetbutton] |
| iOS 17 + 18 in one WidgetBundle | use `if #available` inside a **non-builder** helper with SE-0360 (opaque types with availability, Swift 5.7). A plain `if #available` inside the builder crashed on iOS 17 before Xcode 16.1 b3 | [VERIFIED: https://developer.apple.com/forums/thread/759670 , https://developer.apple.com/forums/thread/762688 , https://github.com/swiftlang/swift-evolution/blob/main/proposals/0360-opaque-result-types-with-availability.md] |
| App Group read | `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` → `nil` if not entitled | [VERIFIED API; nil-when-not-entitled UNVERIFIED] |
| Reload | `WidgetCenter.shared.reloadAllTimelines()` (iOS 14) — after every data change in the app and at the end of intents | standard |
| iOS 26 look | widgets may render "clear/accented"; mark key text `.widgetAccentable()`; background may be removed by the system | [UNVERIFIED detail: https://blakecrosley.com/blog/ios-26-widget-and-control-surface] |

### 5.2 Data sharing design (important for data safety)

* **Primary store: app's own Application Support** (survives Sideloadly re-signs with the same bundle id). Never place it in the App Group: if the group entitlement is missing or rewritten after a re-sign, the data would "disappear".
* **App Group: only `widget_snapshot.json`** (≤ ~10 upcoming items), rewritten by the app after each change. Disposable; widget shows "Asist'i açın" if unavailable.
* Widget "Tamam" uses `TamamlaIntent` (runs in the **app** process) → no writes from the extension, no cross-process DB locking.
* Free-account signing: every extension is an extra App ID (10 new App IDs / 7 days) and possibly counts against the 3-active-app limit; the unsigned CI IPA carries **no entitlements** unless the build ad-hoc-signs with the entitlements file — the App Group may therefore be absent. Code must handle `nil` everywhere. [VERIFIED limits/behaviour reported: https://github.com/subarude15/storyteller-personal-reader/pull/5 ; Apple capability table lists App Groups for free membership: https://developer.apple.com/help/account/reference/supported-capabilities-ios ; Sideloadly specifics UNVERIFIED → orchestrator/CI doc must decide ad-hoc signing with entitlements]

### 5.3 Code — `Shared/AppGroupLocator.swift` (app + widget)

```swift
import Foundation

enum AppGroupLocator {
    static let configuredGroupID = "group.com.gokhanbudak.asist"

    /// App Group kapsayıcısı. Yetki yoksa nil.
    static func containerURL() -> URL? {
        let manager = FileManager.default
        if let url = manager.containerURL(forSecurityApplicationGroupIdentifier: configuredGroupID) {
            return url
        }
        // Yeniden imzalama grup kimliğini değiştirdiyse gömülü profildeki gruba dene.
        for groupID in groupIDsFromEmbeddedProfile() where groupID != configuredGroupID {
            if let url = manager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
                return url
            }
        }
        return nil
    }

    static func groupIDsFromEmbeddedProfile() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return [] }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
    }
}
```
[UNVERIFIED: embedded-profile fallback is a heuristic; harmless if it finds nothing]

### 5.4 Code — `Shared/WidgetSnapshot.swift` (app + widget)

```swift
import Foundation

struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var due: Date?
    }

    var generatedAt: Date
    var items: [Item]          // açık kayıtlar, vadeye göre sıralı, en fazla ~10
    var openCount: Int

    static let empty = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 0), items: [], openCount: 0)

    static let placeholder = WidgetSnapshot(
        generatedAt: Date(),
        items: [
            Item(id: "p1", title: "Teklif revizyonunu gönder", due: Date().addingTimeInterval(3600)),
            Item(id: "p2", title: "Pano FAT tarihini netleştir", due: nil)
        ],
        openCount: 2
    )
}

enum SnapshotStore {
    static let fileName = "widget_snapshot.json"

    static func fileURL() -> URL? {
        AppGroupLocator.containerURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Uygulama her değişiklikten sonra çağırır; ardından WidgetCenter.shared.reloadAllTimelines().
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL() else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
```

### 5.5 Code — `Widgets/AsistWidgets.swift` (widget extension target)

```swift
import AppIntents
import SwiftUI
import WidgetKit

// MARK: Timeline

struct AsistEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let hasSharedData: Bool
}

struct AsistProvider: TimelineProvider {
    func placeholder(in context: Context) -> AsistEntry {
        AsistEntry(date: Date(), snapshot: .placeholder, hasSharedData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AsistEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AsistEntry>) -> Void) {
        let now = Date()
        let first = currentEntry(at: now)
        var entries = [first]
        // Her vade anında bir giriş: "gecikti" rengi yeniden yükleme olmadan değişsin.
        let upcoming = Set(first.snapshot.items.compactMap { $0.due }.filter { $0 > now })
        for due in upcoming.sorted().prefix(12) {
            entries.append(AsistEntry(date: due, snapshot: first.snapshot, hasSharedData: first.hasSharedData))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func currentEntry(at date: Date) -> AsistEntry {
        let hasGroup = AppGroupLocator.containerURL() != nil
        return AsistEntry(date: date, snapshot: SnapshotStore.read() ?? .empty, hasSharedData: hasGroup)
    }
}

// MARK: Views

struct AsistListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AsistEntry

    var body: some View {
        if !entry.hasSharedData {
            VStack(spacing: 4) {
                Image(systemName: "mic.circle.fill").font(.title)
                Text("Asist'i açın").font(.caption)
            }
            .widgetURL(AsistDeepLink.listen)
        } else {
            switch family {
            case .accessoryInline:
                inline
            case .accessoryRectangular:
                rectangular
            case .systemMedium:
                medium
            default:
                small
            }
        }
    }

    private var items: [WidgetSnapshot.Item] { entry.snapshot.items }

    private func isOverdue(_ item: WidgetSnapshot.Item) -> Bool {
        guard let due = item.due else { return false }
        return due <= entry.date
    }

    @ViewBuilder
    private var inline: some View {
        if let first = items.first {
            Text("Sıradaki: \(first.title)")
        } else {
            Text("Asist: bekleyen iş yok")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Asist").font(.caption2).widgetAccentable()
            if let item = items.first {
                Text(item.title).font(.headline).lineLimit(2)
                if let due = item.due {
                    Text(due, style: .time).font(.caption)
                }
            } else {
                Text("Bekleyen iş yok").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(AsistDeepLink.today)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "mic.fill")
                Text("Asist").font(.headline)
                Spacer(minLength: 0)
                Text("\(entry.snapshot.openCount)").font(.caption).bold()
            }
            if let item = items.first {
                Text(item.title).font(.subheadline).lineLimit(3)
                if let due = item.due {
                    Text(due, style: .time)
                        .font(.caption)
                        .foregroundStyle(isOverdue(item) ? Color.red : Color.secondary)
                }
                Spacer(minLength: 0)
                Button(intent: TamamlaIntent(kayitID: item.id)) {
                    Label("Tamam", systemImage: "checkmark.circle.fill")
                }
                .font(.caption)
            } else {
                Spacer(minLength: 0)
                Text("Konuşmak için dokunun").font(.caption).foregroundStyle(.secondary)
            }
        }
        .widgetURL(AsistDeepLink.listen)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Asist").font(.headline)
                Spacer()
                Link(destination: AsistDeepLink.listen) {
                    Label("Konuş", systemImage: "mic.fill").font(.caption.bold())
                }
            }
            if items.isEmpty {
                Text("Bekleyen hatırlatma yok").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(items.prefix(3))) { item in
                HStack(spacing: 8) {
                    Button(intent: TamamlaIntent(kayitID: item.id)) {
                        Image(systemName: "circle")
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title).font(.subheadline).lineLimit(1)
                        if let due = item.due {
                            Text(due, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(isOverdue(item) ? Color.red : Color.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct AsistMicWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AsistEntry

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "mic.fill").font(.title2)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "mic.circle.fill").font(.system(size: 44))
                    Text("Konuş").font(.headline)
                }
            }
        }
        .widgetURL(AsistDeepLink.listen)
    }
}

// MARK: Widgets

struct AsistListWidget: Widget {
    let kind = "AsistListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AsistProvider()) { entry in
            AsistListWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Asist – Sıradakiler")
        .description("Yaklaşan hatırlatmalar; tek dokunuşla tamamla.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct AsistMicWidget: Widget {
    let kind = "AsistMicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AsistProvider()) { entry in
            AsistMicWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Asist – Konuş")
        .description("Dokun, Asist açılsın ve dinlesin.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

// MARK: Control (iOS 18+)

@available(iOS 18.0, *)
struct AsistDinleControl: ControlWidget {
    static let kind = "com.gokhanbudak.asist.control.dinle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: DinleIntent()) {
                Label("Asist Dinle", systemImage: "mic.fill")
            }
        }
        .displayName("Asist'i Dinlet")
        .description("Asist'i açar ve hemen dinlemeye başlar.")
    }
}

// MARK: Bundle (iOS 17 + 18, deployment target 17.0)

@main
struct AsistWidgetBundle: WidgetBundle {
    var body: some Widget {
        makeWidgets()
    }

    /// Sonuç oluşturucu (result builder) DIŞINDA #available → SE-0360 ile farklı opak tipler.
    private func makeWidgets() -> some Widget {
        if #available(iOS 18.0, *) {
            return widgetsWithControls
        }
        return baseWidgets
    }

    @WidgetBundleBuilder
    private var baseWidgets: some Widget {
        AsistListWidget()
        AsistMicWidget()
    }

    @available(iOS 18.0, *)
    @WidgetBundleBuilder
    private var widgetsWithControls: some Widget {
        AsistListWidget()
        AsistMicWidget()
        AsistDinleControl()
    }
}
```
If the CI compiler rejects `makeWidgets()` (unexpected), fallback is the exact accepted forum answer (`if #available(iOSApplicationExtension 18.0, *) { return iOS18Widgets } else { return iOS17Widgets }` directly in `body`). Both rely on Xcode ≥ 16.1. [VERIFIED: https://developer.apple.com/forums/thread/759670]

Control behaviour: tapping runs `DinleIntent` → system opens Asist (Face ID if locked) → `LaunchRouter.pending = .listen` → listening starts. `DinleIntent.swift`, `AsistDeepLink.swift`, `TamamlaIntent.swift`, `AppGroupLocator.swift`, `WidgetSnapshot.swift` are members of **both** targets; `LaunchRouter`, `AppServices`, `KaydetIntent`, `BugunIntent`, `AsistShortcuts` are **app only**.

---

## 6. Live Activities (brief)

* `Activity.request(attributes:content:pushType:)` (iOS 16.2) "requires the app to be in the foreground … unless you adopt App Intents and implement a `LiveActivityIntent`" — whose `perform()` runs with the app process launched in the background. [VERIFIED: https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:) , https://developer.apple.com/documentation/appintents/liveactivityintent]
* **Cannot** be started when a scheduled reminder fires (local notifications run no app code); remote push-to-start (iOS 17.2+) needs APNs + a server → unavailable with free signing. [VERIFIED push-to-start exists; availability for us = design inference]
* Implication: Live Activities cannot replace the nagging notification chain. Optional v1.1: from inside the app (or from `KaydetIntent` made a `LiveActivityIntent`) show "Sıradaki: 15:00 Teklif" in the Dynamic Island with `Text(timerInterval:)` countdown (no updates needed), `staleDate` = due + 1 h. Requires `NSSupportsLiveActivities = YES` (app Info.plist) and an `ActivityConfiguration` in the widget bundle. Not in v1.

---

## 7. Configuration fragments for this topic (orchestrator merges into project.yml / plists)

```yaml
options:
  developmentLanguage: tr
targets:
  Asist:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources: [App, Shared]
    settings:
      base:
        SWIFT_VERSION: "5.0"
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) ASIST_APP"
        APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING: YES
        CODE_SIGN_ENTITLEMENTS: App/Asist.entitlements
    dependencies:
      - target: AsistWidgets
      - package: AsistCore
  AsistWidgets:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.0"
    sources: [Widgets, Shared]
    settings:
      base:
        SWIFT_VERSION: "5.0"
        PRODUCT_BUNDLE_IDENTIFIER: com.gokhanbudak.asist.widgets
        CODE_SIGN_ENTITLEMENTS: Widgets/AsistWidgets.entitlements
```

App `Info.plist` additions: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (§1.2), `CFBundleDisplayName = Asist`, `CFBundleDevelopmentRegion = $(DEVELOPMENT_LANGUAGE)`, `INAlternativeAppNames` (§4.12), URL type:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key><string>com.gokhanbudak.asist</string>
    <key>CFBundleURLSchemes</key><array><string>asist</string></array>
  </dict>
</array>
```
**No** `UIBackgroundModes` audio (not needed; would be abuse).

Widget `Info.plist`: `NSExtension` → `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.

Entitlements (both targets): `com.apple.security.application-groups = [group.com.gokhanbudak.asist]`. Optional (app): `com.apple.developer.siri = true` (§4.12 step 5).

---

## 8. Compile-error / crash pitfall checklist (engineers without a compiler: read before pushing)

1. Missing `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` → crash, not compile error.
2. `SFSpeechRecognizer(locale:)` is failable **and** may silently return another language → check `locale.identifier.hasPrefix("tr")`.
3. `installTap` twice on bus 0 → crash; always `removeTap(onBus: 0)` first. Format with `sampleRate == 0` → crash; guard.
4. Audio callbacks (tap, KVO, recognition handler) must be created in `nonisolated` functions or they become `@MainActor`-inferred closures called off-main (Swift 6 runtime trap).
5. Nested closures: use an explicit capture list in the inner `Task { @MainActor [weak self] in … }` — referencing an outer captured `weak var` inside a `@Sendable` closure can be an error.
6. `CheckedContinuation` must be resumed exactly once — funnel through one `finish(_:)` that nils it first.
7. `AVSpeechSynthesizer` must be a stored property. Delegate methods on a `@MainActor` class must be `nonisolated`.
8. Ternary with mixed styles fails to type-check: `isOverdue ? .red : .secondary` ✗ → `isOverdue ? Color.red : Color.secondary` ✓.
9. `onChange(of:perform:)` is deprecated in iOS 17 → use `onChange(of:initial:_:)` with `{ old, new in }`.
10. Structs with `@Parameter` and a custom `init(...)` must also declare `init() {}`.
11. Intents used by widget/control code must be in the **widget target** too; they must not reference app-only types outside `#if ASIST_APP`.
12. `AppShortcutsProvider`: app target only, one per app, `@AppShortcutsBuilder`, each phrase exactly one `\(.applicationName)`, **no `String` parameters in phrases**, no intents from the SwiftPM package.
13. `AppShortcuts.strings` keys must match code phrases byte-for-byte (ASCII `'`).
14. Do not use `supportedModes`, `IntentModes`, `.allowBluetoothHFP` unless Xcode ≥ 26 is pinned; never without `@available(iOS 26, *)` for the runtime types.
15. `ControlWidget` needs `@available(iOS 18.0, *)` and the non-builder `#available` helper in the bundle; Xcode ≥ 16.1.
16. Widgets: missing `containerBackground` → runtime placeholder; `Link` does nothing in `systemSmall`; `Button(intent:)` needs `import AppIntents`.
17. `OpenURLIntent` + custom scheme does not open the app (universal links only).
18. Store file protection must allow access while locked after first unlock (Siri from Lock Screen).
19. Starting the mic immediately on cold launch/intent may fail → start after `scenePhase == .active` + ~350 ms.
20. Haptics are muted during recording unless `setAllowHapticsAndSystemSoundsDuringRecording(true)`.

---

## 9. Device test list (cannot be proven in CI)

1. Turkish recognition quality server vs on-device; `supportsOnDeviceRecognition` value on the 14 Pro Max; offline behaviour.
2. Auto-stop at 1.8 s with natural pauses ("Salı günü … teklif konusunu … 3'te hatırlat").
3. Volume ×2: events with music playing / silent; HUD suppression; volume restore; hold rejection; volume at 0 banner.
4. `usesApplicationAudioSession = false` ducking; TTS not recorded; music resumes after listening.
5. "Hey Siri, Asist'e kaydet" in Turkish (unlocked, locked, AirPods); "Ne kaydedeyim?" prompt; confirmation spoken.
6. Whether phrases need `tr.lproj/AppShortcuts.strings`; whether `com.apple.developer.siri` is needed.
7. Back Tap recipe A (Dikte → Asist'e Kaydet) end-to-end without opening the app; whether App Shortcuts appear directly in the Back Tap list.
8. Control Center + Lock Screen control opens app and starts listening.
9. Widget "Tamam" button when the app is killed: executes in app process, notifications cancelled, widget refreshes. If iOS refuses to run a `LiveActivityIntent` for an app without Live Activity support, add `NSSupportsLiveActivities = YES` to the app Info.plist and retest.
10. App Group availability after Sideloadly install and after a 7-day re-sign; widget fallback text.

---

## 10. Sources

* Speech: https://developer.apple.com/documentation/speech/sfspeechrecognizer · https://developer.apple.com/documentation/speech/sfspeechrecognizer/init(locale:) · https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition · https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition · https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/addspunctuation · https://developer.apple.com/documentation/speech/speechtranscriber · https://developer.apple.com/forums/thread/703770 · https://developer.apple.com/forums/thread/764809 · https://www.apple.com/ios/feature-availability/ · https://loronote.com/en/blog/apple-speechanalyzer-vs-whisper · https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer · https://dev.to/tbds_2dadf2b626f315902eae/on-device-speech-recognition-on-ios-the-honest-boundaries-1ndn
* Audio: https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:) · https://developer.apple.com/documentation/avfaudio/avaudioapplication · https://developer.apple.com/documentation/avfaudio/avaudiosession/setcategory(_:mode:options:) · https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct · https://developer.apple.com/documentation/avfaudio/avaudiosession/outputvolume · https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:) · https://developer.apple.com/documentation/avfaudio/avaudiosession/setallowhapticsandsystemsoundsduringrecording(_:) · https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer · https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/usesapplicationaudiosession
* Volume: https://raw.githubusercontent.com/jpsim/JPSVolumeButtonHandler/master/JPSVolumeButtonHandler/JPSVolumeButtonHandler.m · https://developer.apple.com/forums/thread/799104 · https://developer.apple.com/forums/thread/813242 · https://developer.apple.com/app-store/review/guidelines/
* App Intents: https://developer.apple.com/documentation/appintents/appintent · https://developer.apple.com/documentation/appintents/appintent/openappwhenrun · https://developer.apple.com/documentation/appintents/appintent/supportedmodes · https://developer.apple.com/documentation/appintents/intentmodes · https://developer.apple.com/documentation/appintents/foregroundcontinuableintent · https://developer.apple.com/documentation/appintents/liveactivityintent · https://developer.apple.com/documentation/appintents/openintent · https://developer.apple.com/documentation/appintents/openurlintent · https://developer.apple.com/documentation/appintents/intentresult · https://developer.apple.com/documentation/appintents/intentdialog · https://developer.apple.com/documentation/appintents/intentparameter · https://developer.apple.com/documentation/appintents/intentauthenticationpolicy · https://developer.apple.com/documentation/appintents/appshortcut · https://developer.apple.com/documentation/appintents/appshortcutsprovider · https://developer.apple.com/documentation/appintents/app-shortcuts · https://developer.apple.com/documentation/appintents/siritipview · https://developer.apple.com/documentation/appintents/shortcutslink · https://developer.apple.com/videos/play/wwdc2022/10170/ · https://developer.apple.com/videos/play/wwdc2023/10102/ · https://www.developer.apple.com/forums/thread/803490 · https://developer.apple.com/forums/thread/768900 · https://developer.apple.com/forums/thread/757370 · https://developer.apple.com/forums/thread/731809 · https://developer.apple.com/forums/thread/731851 · https://developer.apple.com/forums/thread/711693 · https://sowenjub.me/writes/localizing-app-shortcuts-with-app-intents/ · https://phrase.com/blog/posts/siri-shortcuts-localization-tutorial/ · https://github.com/cli-pulse/cli-pulse-private/pull/567 · https://zachwaugh.com/posts/forcing-appintent-to-run-in-main-app-process · https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.siri · https://github.com/Redth/Maui.Apple.PlatformFeature.Samples/issues/1
* Widgets/Controls: https://developer.apple.com/documentation/swiftui/view/containerbackground(for:alignment:content:) · https://developer.apple.com/documentation/swiftui/button/init(intent:label:) · https://developer.apple.com/documentation/swiftui/controlwidget · https://developer.apple.com/documentation/swiftui/controlwidgetconfiguration · https://developer.apple.com/documentation/widgetkit/staticcontrolconfiguration · https://developer.apple.com/documentation/widgetkit/controlwidgetbutton · https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system · https://developer.apple.com/forums/thread/759670 · https://developer.apple.com/forums/thread/762688 · https://developer.apple.com/forums/thread/762479 · https://developer.apple.com/forums/thread/764706 · https://onmyway133.com/posts/how-to-open-app-with-control-widget-on-ios-18/ · https://github.com/swiftlang/swift-evolution/blob/main/proposals/0360-opaque-result-types-with-availability.md · https://blakecrosley.com/blog/ios-26-widget-and-control-surface
* Live Activities: https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:)
* Back Tap / accounts / CI: https://support.apple.com/tr-tr/111772 · https://support.apple.com/guide/shortcuts/run-shortcuts-tapping-iphone-apd897693606/ios · https://developer.apple.com/help/account/reference/supported-capabilities-ios · https://github.com/subarude15/storyteller-personal-reader/pull/5 · https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/
