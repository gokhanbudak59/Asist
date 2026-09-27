// API: App/SmartMode/SmartModeClient.swift
// WP13 — Akıllı Mod client (04 Appendix B.2.2 as applied by revision 3, §12.1; doc 06 facts are binding).
// Raw HTTPS POST to the Claude Messages API with URLSession (Swift has no official SDK). Off unless
// settings.smartModeEnabled && a key is in the Keychain. Never logs the key, the sentence or item/note texts —
// only purpose, model id, HTTP status / API error type, duration and result codes.
import Foundation
import AsistCore

enum SmartModeError: Error, Equatable {
    case disabled
    case noKey
    case invalidKey
    case permissionDenied
    case modelNotFound
    case badRequest
    case tooLarge
    case rateLimited
    case overloaded
    case server(Int)
    case unexpectedStatus(Int)
    case refusal
    case truncated
    case timedOut
    case offline
    case network
    case cancelled
    case decoding
    case rejectedByValidator

    /// Turkish text for the card / sheets / settings.
    var userMessage: String {
        switch self {
        case .disabled:
            return "Akıllı Mod kapalı. Ayarlar › Akıllı Mod'dan açabilirsin."
        case .noKey:
            return "Akıllı Mod için API anahtarı girilmemiş."
        case .invalidKey:
            return "API anahtarı geçersiz. Ayarlar › Akıllı Mod'dan kontrol et."
        case .permissionDenied:
            return "Bu API anahtarının bu işleme izni yok."
        case .modelNotFound:
            return "Seçili model bulunamadı. Ayarlar › Akıllı Mod'dan başka bir model seç."
        case .badRequest:
            return "Akıllı Mod isteği kabul etmedi."
        case .tooLarge:
            return "Gönderilecek metin çok uzun."
        case .rateLimited:
            return "Akıllı Mod istek sınırına ulaştı. Biraz sonra tekrar dene."
        case .overloaded, .server:
            return "Akıllı Mod şu an yanıt veremiyor. Biraz sonra tekrar dene."
        case .unexpectedStatus:
            return "Akıllı Mod'dan beklenmeyen bir yanıt geldi."
        case .refusal:
            return "Akıllı mod bu isteği işleyemedi."
        case .truncated:
            return "Akıllı Mod'un cevabı yarım kaldı."
        case .timedOut:
            return "Akıllı Mod zamanında cevap vermedi."
        case .offline:
            return "İnternet bağlantısı yok; Akıllı Mod kullanılamadı."
        case .network:
            return "Akıllı Mod'a ulaşılamadı."
        case .cancelled:
            return "Akıllı Mod isteği iptal edildi."
        case .decoding:
            return "Akıllı Mod'un cevabı okunamadı."
        case .rejectedByValidator:
            return "Akıllı Mod'un önerisi kullanılamadı."
        }
    }

    /// Content-free code for AsistLog.
    var logCode: String {
        switch self {
        case .server(let status):
            return "server-" + String(status)
        case .unexpectedStatus(let status):
            return "status-" + String(status)
        default:
            return String(describing: self)
        }
    }
}

/// Result of "Özetle": the summary plus how many of the project's notes were sent.
struct SmartSummaryOutcome: Equatable {
    let summary: SmartProjectSummary
    let usedNotes: Int
    let totalNotes: Int
}

/// Not actor-isolated; every input is a value. Callers on the main actor `await` it (the UI never blocks).
/// Constructed lazily through `shared` (no AppEnvironment access anywhere → §4.1 r13 / §9 r45 hold).
final class SmartModeClient: @unchecked Sendable {
    static let shared = SmartModeClient(keychain: KeychainStore(service: KeychainStore.defaultService))

    /// Card upgrade in the app (the on-device result is already on screen).
    static let interactiveParseTimeout: TimeInterval = 20
    /// Siri / Shortcut: the on-device item is already saved; Smart Mode may only improve it within this budget.
    static let headlessParseTimeout: TimeInterval = 8
    /// Drafts and summaries (doc 06: 60 s, effort medium, max_tokens 8000).
    static let longTimeout: TimeInterval = 60
    static let testTimeout: TimeInterval = 25
    static let parseMaxTokens = 4096
    static let longMaxTokens = 8000
    static let testMaxTokens = 256
    static let maxDraftNotesCharacters = 4000
    static let maxSummaryNotes = 60
    static let maxSummaryCharacters = 60_000

    private let keychain: KeychainStore

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    // MARK: - Key

    /// Existence check only (the key itself is not read).
    var hasKey: Bool {
        keychain.contains(account: KeychainStore.apiKeyAccount)
    }

    /// settings.smartModeEnabled && a key is stored.
    func isReady(_ settings: AppSettings) -> Bool {
        settings.smartModeEnabled && hasKey
    }

    /// Whitespace/newlines (copy-paste) are removed before saving.
    @discardableResult
    func saveKey(_ raw: String) -> Bool {
        let key = SmartModeClient.cleanedKey(raw)
        guard !key.isEmpty else { return false }
        let saved = keychain.write(key, account: KeychainStore.apiKeyAccount)
        if saved {
            AsistLog.info("Akıllı Mod: API anahtarı kaydedildi", .smart)
        }
        return saved
    }

    func deleteKey() {
        keychain.delete(account: KeychainStore.apiKeyAccount)
        AsistLog.info("Akıllı Mod: API anahtarı silindi", .smart)
    }

    static func cleanedKey(_ raw: String) -> String {
        raw.filter { !$0.isWhitespace }
    }

    // MARK: - Interpretation (low-confidence captures)

    /// 02 §14: the sentence (+ now, the user's time words, project/place names, the on-device reading) goes to the
    /// user's model with effort "low" (omitted for Haiku), max_tokens 4096 and `SmartModeSchemas.parse`; the answer
    /// is validated on-device (`SmartModeValidator`). `timeout` is the total budget including the single retry.
    func interpret(utterance: String, now: Date, settings: AppSettings, projects: [Project], places: [Place],
                   onDeviceHint: String = "", calendar: Calendar = AppTime.calendar,
                   timeout: TimeInterval = SmartModeClient.interactiveParseTimeout) async -> Result<ParseResult, SmartModeError> {
        guard settings.smartModeEnabled else { return .failure(.disabled) }
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.rejectedByValidator) }
        let parserSettings = ParserSettings(settings: settings, projects: projects, places: places)
        let user = SmartModePrompts.parseUserMessage(utterance: text, now: now, calendar: calendar,
                                                     settings: parserSettings, onDeviceHint: onDeviceHint)
        let outcome = await send(model: settings.smartModeModel, system: SmartModePrompts.parseSystem, user: user,
                                 schema: SmartModeSchemas.parse, effort: "low",
                                 maxTokens: SmartModeClient.parseMaxTokens, timeout: timeout, purpose: "yorum")
        switch outcome {
        case .failure(let error):
            return .failure(error)
        case .success(let json):
            guard let parsed = SmartResponseReader.decode(SmartParseResponse.self, fromJSONText: json) else {
                AsistLog.error("Akıllı Mod yorum: JSON şemaya uymadı", .smart)
                return .failure(.decoding)
            }
            guard let result = SmartModeValidator.parseResult(from: parsed, originalText: text, now: now,
                                                              calendar: calendar,
                                                              parserSettings: parserSettings) else {
                let kind = SmartModeSchemas.parseKinds.contains(parsed.kind) ? parsed.kind : "?"
                AsistLog.info("Akıllı Mod yorum: doğrulamadan geçmedi (tür=" + kind + ")", .smart)
                return .failure(.rejectedByValidator)
            }
            return .success(result)
        }
    }

    // MARK: - Takip message draft

    /// Sends only this item's title / person / project name / notes, how many days it has been waiting and the
    /// user's "Hitap" name. 60 s, effort "medium", max_tokens 8000, `SmartModeSchemas.draft`.
    func draftMessage(for item: Item, projectName: String?, settings: AppSettings, now: Date,
                      calendar: Calendar = AppTime.calendar) async -> Result<String, SmartModeError> {
        guard settings.smartModeEnabled else { return .failure(.disabled) }
        let startDay = calendar.startOfDay(for: item.createdAt)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
        let notes = TurkishText.truncated(item.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                          max: SmartModeClient.maxDraftNotesCharacters)
        let user = SmartModePrompts.draftUserMessage(title: item.title, person: item.person, projectName: projectName,
                                                     notes: notes, waitingDays: max(0, days),
                                                     userName: settings.userName)
        let outcome = await send(model: settings.smartModeModel, system: SmartModePrompts.draftSystem, user: user,
                                 schema: SmartModeSchemas.draft, effort: "medium",
                                 maxTokens: SmartModeClient.longMaxTokens, timeout: SmartModeClient.longTimeout,
                                 purpose: "taslak")
        switch outcome {
        case .failure(let error):
            return .failure(error)
        case .success(let json):
            guard let draft = SmartResponseReader.decode(SmartDraftResponse.self, fromJSONText: json) else {
                AsistLog.error("Akıllı Mod taslak: JSON şemaya uymadı", .smart)
                return .failure(.decoding)
            }
            let message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return .failure(.decoding) }
            return .success(message)
        }
    }

    // MARK: - Project notes summary

    /// Sends only that project's name and note texts (newest first; at most 60 notes / 60 000 characters — the
    /// outcome reports how many were used). 60 s, effort "medium", max_tokens 8000, `SmartModeSchemas.summary`.
    func summarize(notes: [String], project: String,
                   settings: AppSettings) async -> Result<SmartSummaryOutcome, SmartModeError> {
        guard settings.smartModeEnabled else { return .failure(.disabled) }
        var selected: [String] = []
        var characters = 0
        var available = 0
        for note in notes {
            let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                continue
            }
            available += 1
            if selected.count >= SmartModeClient.maxSummaryNotes
                || characters + text.count > SmartModeClient.maxSummaryCharacters {
                continue
            }
            selected.append(text)
            characters += text.count
        }
        guard !selected.isEmpty else { return .failure(.rejectedByValidator) }
        let user = SmartModePrompts.summaryUserMessage(projectName: project, notes: selected)
        let outcome = await send(model: settings.smartModeModel, system: SmartModePrompts.summarySystem, user: user,
                                 schema: SmartModeSchemas.summary, effort: "medium",
                                 maxTokens: SmartModeClient.longMaxTokens, timeout: SmartModeClient.longTimeout,
                                 purpose: "özet")
        switch outcome {
        case .failure(let error):
            return .failure(error)
        case .success(let json):
            guard let decoded = SmartResponseReader.decode(SmartProjectSummary.self, fromJSONText: json) else {
                AsistLog.error("Akıllı Mod özet: JSON şemaya uymadı", .smart)
                return .failure(.decoding)
            }
            let summary = decoded.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            var actions: [String] = []
            for raw in decoded.actionItems {
                let action = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !action.isEmpty {
                    actions.append(action)
                }
            }
            guard !summary.isEmpty || !actions.isEmpty else { return .failure(.decoding) }
            let result = SmartProjectSummary(summary: summary, actionItems: actions)
            return .success(SmartSummaryOutcome(summary: result, usedNotes: selected.count, totalNotes: available))
        }
    }

    // MARK: - Connection test

    /// "Bağlantıyı dene": a minimal request with the stored key and `model` (works before Smart Mode is switched
    /// on). Success text: "1,8 sn". A truncated / empty answer still proves that the key and the model work.
    func testConnection(model: String) async -> Result<String, SmartModeError> {
        let started = Date()
        let outcome = await send(model: model, system: SmartModePrompts.testSystem, user: SmartModePrompts.testUser,
                                 schema: nil, effort: "low", maxTokens: SmartModeClient.testMaxTokens,
                                 timeout: SmartModeClient.testTimeout, purpose: "test")
        switch outcome {
        case .success, .failure(.truncated), .failure(.decoding):
            let tenths = Int((Date().timeIntervalSince(started) * 10).rounded())
            return .success(String(tenths / 10) + "," + String(tenths % 10) + " sn")
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Transport (doc 06 retry policy)

    /// One exchange: builds the body, sends it, applies the single-retry policy (429 → retry-after ≤ 5 s; 5xx/529 →
    /// 1.5 s; URLError → once; 400/401/403/404/413 → never) within `timeout` in total, checks stop_reason before the
    /// content and returns the concatenated text blocks.
    private func send(model rawModel: String, system: String, user: String, schema: AsistCore.JSONValue?, effort: String?,
                      maxTokens: Int, timeout: TimeInterval, purpose: String) async -> Result<String, SmartModeError> {
        guard let apiKey = keychain.read(account: KeychainStore.apiKeyAccount), !apiKey.isEmpty else {
            return .failure(.noKey)
        }
        guard let url = URL(string: SmartModeRequestBuilder.endpoint) else { return .failure(.network) }
        let model = SmartModeModelID.normalized(rawModel)
        let request = SmartModeRequestBuilder.request(model: model, system: system, user: user, schema: schema,
                                                      effort: effort, maxTokens: maxTokens)
        let body: Data
        do {
            body = try SmartModeRequestBuilder.body(request)
        } catch {
            AsistLog.error("Akıllı Mod " + purpose + ": istek gövdesi oluşturulamadı", .smart)
            return .failure(.badRequest)
        }
        let headers = SmartModeRequestBuilder.headers(model: model, apiKey: apiKey)
        let started = Date()
        let deadline = started.addingTimeInterval(max(2, timeout))
        var attempt = 0

        while true {
            attempt += 1
            let remaining = deadline.timeIntervalSinceNow
            if remaining < 1 {
                logResult(purpose, model: model, result: "zaman aşımı", started: started)
                return .failure(.timedOut)
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.httpBody = body
            urlRequest.timeoutInterval = remaining
            urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
            for (field, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: field)
            }
            // Ephemeral per-attempt session: no cache/cookies on disk, and the resource timeout caps the whole
            // attempt (URLRequest.timeoutInterval alone is an idle timeout).
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = remaining
            configuration.timeoutIntervalForResource = remaining
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration)
            defer {
                session.finishTasksAndInvalidate()
            }

            let exchange: (Data, URLResponse)
            do {
                exchange = try await session.data(for: urlRequest)
            } catch let error as URLError {
                if error.code == .cancelled {
                    logResult(purpose, model: model, result: "iptal", started: started)
                    return .failure(.cancelled)
                }
                let mapped = SmartModeClient.mapped(error)
                if attempt == 1 && error.code != .timedOut && deadline.timeIntervalSinceNow > 3 {
                    AsistLog.info("Akıllı Mod " + purpose + ": ağ hatası " + String(error.code.rawValue)
                                  + ", bir kez yeniden deneniyor", .smart)
                    continue
                }
                logResult(purpose, model: model, result: mapped.logCode, started: started)
                return .failure(mapped)
            } catch {
                logResult(purpose, model: model, result: "ağ hatası", started: started)
                return .failure(.network)
            }

            let data = exchange.0
            guard let http = exchange.1 as? HTTPURLResponse else {
                logResult(purpose, model: model, result: "HTTP yanıtı yok", started: started)
                return .failure(.network)
            }
            let status = http.statusCode
            let kind = SmartHTTPStatus.kind(status)
            if kind == .success {
                return readText(data, purpose: purpose, model: model, started: started)
            }
            let errorType = TurkishText.truncated(SmartAPIErrorEnvelope.errorType(from: data) ?? "?", max: 40)
            AsistLog.error("Akıllı Mod " + purpose + ": HTTP " + String(status) + " (" + errorType + ")", .smart)
            let retryAfter = http.value(forHTTPHeaderField: "retry-after")
            if attempt == 1, let delay = SmartHTTPStatus.retryDelay(status: status, retryAfter: retryAfter),
               deadline.timeIntervalSinceNow > delay + 2 {
                try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                if Task.isCancelled {
                    return .failure(.cancelled)
                }
                continue
            }
            let error = SmartModeClient.error(for: kind, status: status)
            logResult(purpose, model: model, result: error.logCode, started: started)
            return .failure(error)
        }
    }

    /// stop_reason first ("refusal" → .refusal, "max_tokens" → .truncated), then the text blocks only.
    private func readText(_ data: Data, purpose: String, model: String, started: Date) -> Result<String, SmartModeError> {
        guard let response = try? JSONDecoder().decode(SmartMessagesResponse.self, from: data) else {
            logResult(purpose, model: model, result: "yanıt çözülemedi", started: started)
            return .failure(.decoding)
        }
        // The server-side fallback may have served another model; only its id is logged (never any content).
        let reported = response.model ?? model
        let served = (reported.hasPrefix("claude-") && reported.count <= 40) ? reported : model
        switch SmartResponseReader.outcome(of: response) {
        case .text(let text):
            logResult(purpose, model: served, result: "tamam", started: started)
            return .success(text)
        case .refusal:
            logResult(purpose, model: served, result: "refusal", started: started)
            return .failure(.refusal)
        case .truncated:
            logResult(purpose, model: served, result: "max_tokens", started: started)
            return .failure(.truncated)
        case .empty:
            logResult(purpose, model: served, result: "boş yanıt", started: started)
            return .failure(.decoding)
        }
    }

    private func logResult(_ purpose: String, model: String, result: String, started: Date) {
        let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        AsistLog.info("Akıllı Mod " + purpose + ": " + result + " (model=" + model + ", "
                      + String(milliseconds) + " ms)", .smart)
    }

    static func error(for kind: SmartHTTPStatus.Kind, status: Int) -> SmartModeError {
        switch kind {
        case .success, .unexpected:
            return .unexpectedStatus(status)
        case .badRequest:
            return .badRequest
        case .invalidKey:
            return .invalidKey
        case .permissionDenied:
            return .permissionDenied
        case .notFound:
            return .modelNotFound
        case .tooLarge:
            return .tooLarge
        case .rateLimited:
            return .rateLimited
        case .overloaded:
            return .overloaded
        case .serverError:
            return .server(status)
        }
    }

    static func mapped(_ error: URLError) -> SmartModeError {
        switch error.code {
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .cancelled:
            return .cancelled
        default:
            return .network
        }
    }
}
