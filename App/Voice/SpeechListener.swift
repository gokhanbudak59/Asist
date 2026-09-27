// WP6 — 01b §1.7 adapted per D2 / D19 / 05b A6 (04 §3.6.7).
// Plain @MainActor class (no ObservableObject): reports through closures; VoiceCoordinator is the only observable.
// Every closure handed to AVFoundation / Speech / NotificationCenter is built in a `nonisolated static` factory
// (04 §4.1 r6, §9 r11); the continuation is resumed exactly once through `finish` (04 §9 r12).
import Foundation
import AVFoundation
import Speech

struct ListenConfig {
    var localeIdentifier: String = "tr-TR"
    /// Konuşma başladıktan sonra yeni konuşma etkinliği olmazsa bitirme süresi (sn). Ayar: 1.2 / 1.8 / 2.5 / 3.5.
    var silenceAfterSpeech: TimeInterval = 1.8
    /// Hiç konuşma (kısmi metin) algılanmazsa vazgeçme süresi (sn) — D19.
    var noSpeechTimeout: TimeInterval = 6.0
    /// Sunucu tanımasının 1 dakikalık sınırının altında kal — D19.
    var maxDuration: TimeInterval = 45.0
    /// true: yalnız cihaz üzerinde tanı (model yüklüyse). Doğruluk biraz düşer.
    var onDeviceOnly: Bool = false
    /// Normalised level (0…1, −60 dBFS → 0, 0 dBFS → 1) that speech must always reach: 0.6 ≈ −24 dBFS.
    var minimumSpeechLevel: Float = 0.6
    /// Speech must be this many dB above the noise floor measured in the first `noiseFloorWindow` (05b A6).
    var noiseMarginDecibels: Float = 8
    /// Length of the noise-floor measurement at the start (before the "listening" haptic).
    var noiseFloorWindow: TimeInterval = 0.3
    /// Audio energy alone may extend speech activity at most this long beyond the last *changed* partial.
    var maxEnergyExtension: TimeInterval = 1.5
    /// Proje/müşteri adları, PLC terimleri... İlk 100 tanesi kullanılır.
    var contextualStrings: [String] = []
}

enum ListenOutcome: Equatable {
    case text(String)
    case noSpeech
    /// Turkish message for the user (03 §7.12 listen.err.*).
    case failed(String)
    /// Audio session interrupted (call, alarm) while the user was speaking: the partial transcript so far (03 §5.3).
    case interrupted(String)
    case cancelled
}

enum ListenerError: Error {
    case noAudioInput
}

/// Tap bloğu (ses thread'i) yazar, ana aktör okur.
final class AudioLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    private var sum: Double = 0
    private var count: Int = 0

    func set(_ newValue: Float) {
        lock.lock()
        value = newValue
        sum += Double(newValue)
        count += 1
        lock.unlock()
    }

    func get() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func reset() {
        lock.lock()
        value = 0
        sum = 0
        count = 0
        lock.unlock()
    }

    /// Mean normalised level of every buffer since the last `reset()`; nil when no buffer arrived yet.
    func mean() -> Float? {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return nil }
        return Float(sum / Double(count))
    }

    /// -60 dBFS → 0, 0 dBFS → 1
    static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let channel = channels[0]
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = (decibels + 60) / 60
        guard normalized.isFinite else { return 0 }
        return max(0, min(1, normalized))
    }
}

@MainActor
final class SpeechListener {
    enum State: Equatable { case idle, starting, listening, finishing }

    private(set) var state: State = .idle
    private(set) var partialText: String = ""
    private(set) var level: Float = 0
    /// true when the last session was ended by the 45 s cap (03 listen.max_reached).
    private(set) var stoppedByMaxDuration = false

    /// Every new, different partial transcript.
    var onPartial: ((String) -> Void)?
    /// Normalised input level (0…1) every 150 ms while listening; 0 when finished.
    var onLevel: ((Float) -> Void)?
    /// The noise floor has been measured: the microphone is really ready ("listening" haptic moment, 03 §5.3).
    var onReady: (() -> Void)?

    private var engine: AVAudioEngine?
    private let levelBox = AudioLevelBox()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var monitor: Task<Void, Never>?
    private var finalizeTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<ListenOutcome, Never>?
    private var observers: [NSObjectProtocol] = []
    private var config = ListenConfig()
    private var startedAt = Date()
    private var lastSpeechActivityAt: Date?
    private var lastPartialChangeAt: Date?
    private var speechThreshold: Float = 0.6
    private var noiseFloorMeasured = false

    // MARK: Public API

    /// Tek seferlik dinleme. Sonuç gelene kadar bekler. Aynı anda ikinci çağrı `.cancelled` döner.
    func listen(config: ListenConfig) async -> ListenOutcome {
        guard state == .idle else { return .cancelled }
        guard VoicePermissions.isFullyAuthorized else {
            return .failed(VoicePermissions.missingPermissionMessage ?? "Mikrofon veya konuşma tanıma izni kapalı.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: config.localeIdentifier)),
              recognizer.locale.identifier.hasPrefix("tr") else {
            AsistLog.error("Türkçe konuşma tanıyıcı bulunamadı", .voice)
            return .failed("Türkçe konuşma tanıma bu cihazda bulunamadı. Klavyeyle yazabilirsin.")
        }
        var effective = config
        if !recognizer.isAvailable {
            // 03 §9 r7: prefer on-device recognition when the server path is unavailable.
            if recognizer.supportsOnDeviceRecognition {
                effective.onDeviceOnly = true
                AsistLog.info("Sunucu tanıma kullanılamıyor; cihaz içi tanıma deneniyor", .voice)
            } else {
                AsistLog.error("Konuşma tanıyıcı kullanılamıyor (çevrimdışı, cihaz içi model yok)", .voice)
                return .failed("İnternet yok ve cihaz içi tanıma kullanılamıyor. Klavyeyle yazabilirsin.")
            }
        }
        self.config = effective
        self.recognizer = recognizer
        partialText = ""
        level = 0
        stoppedByMaxDuration = false
        state = .starting
        return await withCheckedContinuation { (continuation: CheckedContinuation<ListenOutcome, Never>) in
            self.continuation = continuation
            do {
                try self.beginSession(recognizer: recognizer)
            } catch {
                let nsError = error as NSError
                AsistLog.error("Dinleme başlatılamadı: " + nsError.domain + " " + String(nsError.code), .voice)
                self.finish(SpeechListener.outcome(forStartErrorCode: nsError.code))
            }
        }
    }

    /// Kullanıcı "Bitti"ye bastı (veya sessizlik/süre doldu): kalan sesi işle, sonucu döndür.
    func stopAndFinalize() {
        guard state == .listening else { return }
        state = .finishing
        monitor?.cancel()
        monitor = nil
        stopAudioEngine()
        request?.endAudio()
        finalizeTask?.cancel()
        finalizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)       // wait ≤ 1.5 s for isFinal (01b §1.4)
            guard let self = self, !Task.isCancelled, self.state == .finishing else { return }
            self.finish(self.partialText.isEmpty ? .noSpeech : .text(self.partialText))
        }
    }

    /// İptal (kullanıcı vazgeçti, uygulama arka plana gitti). The pending `listen` returns `.cancelled`.
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

        // A fresh engine per session: its input format is read after the session was activated, so it matches
        // the current route (a stale format makes installTap raise an Objective-C exception).
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ListenerError.noAudioInput                  // 0 Hz formatla installTap çöker
        }
        input.removeTap(onBus: 0)                             // ikinci tap = çökme
        levelBox.reset()
        SpeechListener.installTap(on: input, format: format, request: request, levelBox: levelBox)
        engine.prepare()
        try engine.start()

        task = SpeechListener.startRecognition(recognizer: recognizer, request: request, owner: self)
        startedAt = Date()
        lastSpeechActivityAt = nil
        lastPartialChangeAt = nil
        speechThreshold = config.minimumSpeechLevel
        noiseFloorMeasured = false
        state = .listening
        observeAudioEvents(engine: engine)
        startMonitor()
        let onDevice = request.requiresOnDeviceRecognition ? "evet" : "hayır"
        AsistLog.info("Dinleme başladı (cihaz içi: " + onDevice
                      + ", sözlük: " + String(request.contextualStrings.count) + ")", .voice)
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
            let now = Date()
            lastPartialChangeAt = now
            lastSpeechActivityAt = now
            onPartial?(text)
        }
        if isFinal {
            finish(partialText.isEmpty ? .noSpeech : .text(partialText))
        } else if let domain = errorDomain, let code = errorCode {
            AsistLog.error("Konuşma tanıma hatası: " + domain + " " + String(code), .voice)
            if !partialText.isEmpty {
                finish(.text(partialText))                   // durdurma sonrası hatalar: eldekini kullan
            } else {
                finish(SpeechListener.outcome(forErrorDomain: domain, code: code))
            }
        }
    }

    // MARK: Silence monitor (01b §1.4 + 05b A6 noise floor)

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
        onLevel?(currentLevel)
        let elapsed = now.timeIntervalSince(startedAt)

        if !noiseFloorMeasured && elapsed >= config.noiseFloorWindow - 0.02 {
            measureNoiseFloor()
        }
        // Energy may refresh speech activity only while the recogniser is plausibly lagging:
        // at most `maxEnergyExtension` beyond the last changed partial (05b A6).
        if noiseFloorMeasured, let lastPartial = lastPartialChangeAt,
           currentLevel >= speechThreshold,
           now.timeIntervalSince(lastPartial) <= config.maxEnergyExtension {
            lastSpeechActivityAt = now
        }

        if elapsed >= config.maxDuration {
            stoppedByMaxDuration = true
            AsistLog.info("Dinleme en uzun süreye ulaştı", .voice)
            stopAndFinalize()
        } else if let last = lastSpeechActivityAt {
            if now.timeIntervalSince(last) >= config.silenceAfterSpeech {
                stopAndFinalize()
            }
        } else if elapsed >= config.noSpeechTimeout {
            finish(.noSpeech)
        }
    }

    private func measureNoiseFloor() {
        noiseFloorMeasured = true
        let noiseFloor: Float = levelBox.mean() ?? 0
        let margin: Float = config.noiseMarginDecibels / 60       // normalised scale: 60 dB == 1.0
        let threshold: Float = max(config.minimumSpeechLevel, noiseFloor + margin)
        speechThreshold = min(0.95, threshold)
        let floorDB = Int((noiseFloor * 60 - 60).rounded())
        let thresholdDB = Int((speechThreshold * 60 - 60).rounded())
        AsistLog.info("Gürültü tabanı " + String(floorDB) + " dBFS, konuşma eşiği " + String(thresholdDB) + " dBFS", .voice)
        onReady?()
    }

    // MARK: Interruptions / route changes

    private func observeAudioEvents(engine: AVAudioEngine) {
        removeObservers()
        observers.append(SpeechListener.makeInterruptionObserver(owner: self))
        observers.append(SpeechListener.makeRouteChangeObserver(owner: self))
        observers.append(SpeechListener.makeEngineConfigurationObserver(engine: engine, owner: self))
    }

    nonisolated private static func makeInterruptionObserver(owner: SpeechListener) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance(),
                                               queue: .main) { [weak owner] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak owner] in
                owner?.handleInterruption(rawType: raw)
            }
        }
    }

    nonisolated private static func makeRouteChangeObserver(owner: SpeechListener) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                               object: AVAudioSession.sharedInstance(),
                                               queue: .main) { [weak owner] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak owner] in
                owner?.handleRouteChange(rawReason: raw)
            }
        }
    }

    nonisolated private static func makeEngineConfigurationObserver(engine: AVAudioEngine,
                                                                    owner: SpeechListener) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: engine,
                                               queue: .main) { [weak owner] _ in
            Task { @MainActor [weak owner] in
                owner?.handleEngineConfigurationChange()
            }
        }
    }

    private func handleInterruption(rawType: UInt?) {
        guard let raw = rawType, let type = AVAudioSession.InterruptionType(rawValue: raw), type == .began else { return }
        guard state != .idle else { return }
        AsistLog.info("Dinleme ses oturumu kesintisiyle durdu", .voice)
        let text = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if state == .finishing {
            finish(text.isEmpty ? .noSpeech : .text(text))           // "Bitti" was already pressed
        } else {
            finish(text.isEmpty ? .cancelled : .interrupted(text))
        }
    }

    private func handleRouteChange(rawReason: UInt?) {
        guard state == .listening, let raw = rawReason,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // Our own category switch at start (e.g. to a Bluetooth HFP microphone) must not end the session.
        guard Date().timeIntervalSince(startedAt) > 1.0 else { return }
        if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable {
            AsistLog.info("Ses yolu değişti; dinleme sonlandırılıyor", .voice)
            stopAndFinalize()                                        // kulaklık takıldı/çıktı
        }
    }

    private func handleEngineConfigurationChange() {
        guard state == .listening, let engine = engine else { return }
        guard !engine.isRunning else { return }                      // only when the engine stopped itself
        AsistLog.info("Ses motoru yapılandırması değişti; dinleme sonlandırılıyor", .voice)
        stopAndFinalize()
    }

    private func removeObservers() {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
    }

    // MARK: Teardown

    private func stopAudioEngine() {
        guard let engine = engine else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func finish(_ outcome: ListenOutcome) {
        guard state != .idle else { return }
        state = .idle
        monitor?.cancel()
        monitor = nil
        finalizeTask?.cancel()
        finalizeTask = nil
        stopAudioEngine()
        engine = nil
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        removeObservers()
        level = 0
        onLevel?(0)
        AudioSessionConfigurator.deactivate()
        AsistLog.info("Dinleme bitti: " + SpeechListener.describe(outcome), .voice)
        let pending = continuation
        continuation = nil
        pending?.resume(returning: outcome)                   // tam olarak bir kez
    }

    /// Log text without the utterance itself (04 §4.3: MUST NOT log full utterances).
    nonisolated static func describe(_ outcome: ListenOutcome) -> String {
        switch outcome {
        case .text(let text): return "metin (" + String(text.count) + " karakter)"
        case .noSpeech: return "konuşma yok"
        case .failed: return "hata"
        case .interrupted(let text): return "kesildi (" + String(text.count) + " karakter)"
        case .cancelled: return "iptal"
        }
    }

    /// Audio-session start failures (OSStatus four-char codes of `AVAudioSession.ErrorCode`, as plain integers).
    nonisolated static func outcome(forStartErrorCode code: Int) -> ListenOutcome {
        switch code {
        case 561_017_449,     // '!pri' insufficientPriority — a call or another app owns the microphone
             561_145_187,     // '!rec' cannotStartRecording
             560_030_580,     // '!act' isBusy
             560_557_684,     // '!int' cannotInterruptOthers
             1_936_290_409:   // 'siri' siriIsRecording
            return .failed("Telefon görüşmesi sürerken dinleyemiyorum.")
        default:
            return .failed("Dinleme başlatılamadı. Klavyeyle yazabilirsin.")
        }
    }

    /// Hata kodları Apple tarafından belgelenmemiştir; yalnız mesaj seçimi için kullanılır.
    nonisolated static func outcome(forErrorDomain domain: String, code: Int) -> ListenOutcome {
        switch (domain, code) {
        case ("kAFAssistantErrorDomain", 1110):
            return .noSpeech
        case ("kAFAssistantErrorDomain", 216), ("kLSRErrorDomain", 301):
            return .cancelled
        case ("kLSRErrorDomain", 102):
            return .failed("Türkçe cihaz içi konuşma modeli yüklü değil. Ayarlar › Tetikleyiciler'de 'Yalnız cihazda tanı'yı kapat.")
        case ("kLSRErrorDomain", 201):
            return .failed("Siri ve Dikte kapalı. Ayarlar › Genel › Klavye › Dikte'yi aç.")
        default:
            if domain == NSURLErrorDomain {
                return .failed("İnternet yok ve cihaz içi tanıma kullanılamıyor. Klavyeyle yazabilirsin.")
            }
            return .failed("Dinleme başlatılamadı. Klavyeyle yazabilirsin.")
        }
    }
}
