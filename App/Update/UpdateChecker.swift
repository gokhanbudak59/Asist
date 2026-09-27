// API: App/Update/UpdateChecker.swift
// Revision 4 — F3 (07 §6.3, R4-D6): reads `surum.json` from the GitHub release `son-surum` and records the newest
// published build in AppMeta. GET only, no query, no cookies, no cache, no user data; logs build numbers and HTTP
// status only (§2.3). Lazy singleton whose init never touches AppEnvironment.shared (R4-D10, §4.1 r13).
import Foundation
import Observation
import AsistCore

enum UpdateFetchError: Error, Equatable {
    case offline, timeout, http(Int), invalid, tooLarge

    /// Shown after "Kontrol edilemedi: ".
    var userMessage: String {
        switch self {
        case .offline:
            return "İnternet bağlantısı yok."
        case .timeout:
            return "Sunucu yanıt vermedi."
        case .http(let status):
            return "Sunucu hatası (" + String(status) + ")."
        case .invalid:
            return "Sürüm dosyası okunamadı."
        case .tooLarge:
            return "Sürüm dosyası beklenenden büyük."
        }
    }

    /// Content-free code for AsistLog.
    var logCode: String {
        switch self {
        case .offline: return "bağlantı yok"
        case .timeout: return "zaman aşımı"
        case .http(let status): return "HTTP " + String(status)
        case .invalid: return "geçersiz dosya"
        case .tooLarge: return "dosya çok büyük"
        }
    }

    static func from(_ error: URLError) -> UpdateFetchError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timeout
        default:
            return .invalid
        }
    }
}

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case finished(Date)          // last successful check of this session
    case failed(String)          // UpdateFetchError.userMessage
}

@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    private(set) var state: UpdateCheckState = .idle
    /// Last failed attempt of this process (30-minute back-off, UpdatePolicy.retryAfterFailure). Not persisted.
    @ObservationIgnored private var lastAttemptAt: Date? = nil

    init() {}

    var isChecking: Bool {
        state == .checking
    }

    /// Background check when UpdatePolicy.isCheckDue(enabled: settings.updateCheckEnabled,
    /// lastCheck: meta.lastUpdateCheckAt, lastAttempt: in-memory, now:) — starts a Task, never blocks; no-op while
    /// !store.isLoaded or a check is running.
    func checkIfDue(store: DataStore, now: Date) {
        guard store.isLoaded, state != .checking else { return }
        let due = UpdatePolicy.isCheckDue(enabled: store.settings.updateCheckEnabled,
                                          lastCheck: store.meta.lastUpdateCheckAt,
                                          lastAttempt: lastAttemptAt,
                                          now: now)
        guard due else { return }
        state = .checking
        Task { @MainActor [weak self] in
            await self?.runCheck(store: store)
        }
    }

    /// "Şimdi kontrol et": ignores the 12 h rule (not a running check). Awaitable.
    func checkNow(store: DataStore) async {
        guard state != .checking else { return }
        guard store.isLoaded else {
            state = .failed("Kayıtlar henüz okunamadı; biraz sonra tekrar dene.")
            return
        }
        state = .checking
        await runCheck(store: store)
    }

    /// Caller has set `state = .checking`.
    private func runCheck(store: DataStore) async {
        let result = await UpdateChecker.fetchManifest()
        let now = Date()
        switch result {
        case .success(let manifest):
            lastAttemptAt = nil
            store.updateMeta { m in
                m.lastUpdateCheckAt = now
                m.latestBuildSeen = manifest.build
                m.latestBuildDate = manifest.date
                m.latestBuildNotes = manifest.notes.isEmpty ? nil : manifest.notes
            }
            state = .finished(now)
            AsistLog.info("Güncelleme kontrolü: yayınlanan " + String(manifest.build) + ", yüklü "
                          + String(SettingsFormat.buildNumber), .app)
        case .failure(let error):
            lastAttemptAt = now
            state = .failed(error.userMessage)
            AsistLog.info("Güncelleme kontrolü yapılamadı: " + error.logCode, .app)
        }
    }

    /// Ephemeral URLSession (timeoutIntervalForRequest 10, timeoutIntervalForResource 15,
    /// requestCachePolicy .reloadIgnoringLocalCacheData, no cookies, waitsForConnectivity false,
    /// httpAdditionalHeaders ["User-Agent": "Asist"]), GET manifestURLString (redirect followed), status 200,
    /// ≤ 65 536 bytes, UpdateManifest.decode. The session is invalidated after use.
    nonisolated static func fetchManifest() async -> Result<UpdateManifest, UpdateFetchError> {
        guard let url = URL(string: UpdateManifest.manifestURLString) else {
            return .failure(.invalid)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Asist"]
        let session = URLSession(configuration: configuration)
        defer {
            session.finishTasksAndInvalidate()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        let exchange: (Data, URLResponse)
        do {
            exchange = try await session.data(for: request)
        } catch let error as URLError {
            return .failure(UpdateFetchError.from(error))
        } catch {
            return .failure(.invalid)
        }
        guard let http = exchange.1 as? HTTPURLResponse else {
            return .failure(.invalid)
        }
        guard http.statusCode == 200 else {
            return .failure(.http(http.statusCode))
        }
        let data = exchange.0
        guard data.count <= UpdateManifest.maxBytes else {
            return .failure(.tooLarge)
        }
        guard let manifest = UpdateManifest.decode(from: data) else {
            return .failure(.invalid)
        }
        return .success(manifest)
    }
}
