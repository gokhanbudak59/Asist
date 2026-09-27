// API: App/Services/CaptureService.swift
// WP7 (04 §3.6.8; 03 §4.5, §4.6, §5.3, §5.5, §5.11; D10/D18/D20/D22/D33/D34): parse → card / save,
// headless capture for App Intents, "Sesle ertele", contextual strings for the speech recognizer.
import Foundation
import UIKit
import AsistCore

/// Outcome of `CaptureService.saveUnmatchedCommand` (a command sentence that matched no open item).
enum UnmatchedCommandSave {
    /// Persisted as a task marked "Emin değilim"; the toast offers "Geri Al" with this token.
    case saved(UndoToken)
    /// The write failed; the store keeps the item in memory and retries it (05a #3).
    case keptInMemory
    /// Nothing stored (data file unreadable).
    case failed
}

struct CapturePreview: Equatable {
    let understood: String           // parser `understood`
    let level: ConfirmationLevel
    let kind: ItemKind?
}

@MainActor
final class CaptureService {
    private(set) var activeDraft: CaptureDraft? = nil

    private let store: DataStore
    private let router: AppRouter
    private let toasts: ToastCenter

    private var cachedParser: TurkishParser? = nil
    private var cachedParserTimeZoneID: String = ""
    /// Last card closed with "Vazgeç": its "Geri Al" (undoTranscript) brings back this very draft, edits included.
    private var recentlyDiscarded: CaptureDraft? = nil
    private var recentlyDiscardedAt: Date = Date.distantPast
    /// "Tekrar söyle": the card a retry is about to replace. Neither saved nor dropped until the retry produced a
    /// transcript (then the new result replaces it); a retry without one brings the same card back (03 §4.5,
    /// principle 3).
    private var redoDraft: CaptureDraft? = nil

    /// 01b §1.8 domain vocabulary (the speech recognizer's contextual strings start with these).
    static let jargon: [String] = [
        "PLC", "HMI", "SCADA", "TIA Portal", "Siemens", "S7-1500", "S7-1200", "Profinet", "Profibus",
        "servo", "sürücü", "pano", "devreye alma", "FAT", "SAT", "revizyon", "teklif", "sipariş",
        "satınalma", "bakım", "arıza", "OEE", "I/O listesi", "elektrik projesi"
    ]
    /// §3.4.6 gate rule 3: at most 100 contextual strings.
    static let maxContextualStrings = 100

    /// Stores references only (never touches AppEnvironment.shared, §4.1 r13).
    init(store: DataStore, router: AppRouter, toasts: ToastCenter) {
        self.store = store
        self.router = router
        self.toasts = toasts
    }

    // MARK: - Parser and vocabulary

    /// Parser for current settings/projects/places + `ParserSettings.frequentPeople(in: store.items)` +
    /// AppTime.calendar (cached; see invalidateParser). A time-zone change also rebuilds it.
    func parser() -> TurkishParser {
        let zoneID = TimeZone.current.identifier
        if let cached = cachedParser, cachedParserTimeZoneID == zoneID {
            return cached
        }
        let people = ParserSettings.frequentPeople(in: store.items)
        let settings = ParserSettings(settings: store.settings, projects: store.projects, places: store.places,
                                      people: people)
        let fresh = TurkishParser(settings: settings, calendar: AppTime.calendar)
        cachedParser = fresh
        cachedParserTimeZoneID = zoneID
        return fresh
    }

    func invalidateParser() {
        cachedParser = nil
    }

    /// Speech-recognizer vocabulary: project names/aliases + frequent people + 01b §1.8 jargon, unique (folded),
    /// ≤ 100 (§3.4.6).
    func contextualStrings() -> [String] {
        var candidates: [String] = []
        for project in store.projects where !project.archived {
            candidates.append(contentsOf: project.allNames)
        }
        candidates.append(contentsOf: ParserSettings.frequentPeople(in: store.items))
        candidates.append(contentsOf: CaptureService.jargon)

        var result: [String] = []
        var seen = Set<String>()
        for raw in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.count > 60 {
                continue
            }
            let key = TurkishText.fold(trimmed)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            result.append(trimmed)
            if result.count >= CaptureService.maxContextualStrings {
                break
            }
        }
        return result
    }

    // MARK: - Interactive capture

    /// Voice/keyboard entry in the app.
    /// request.snoozeItemID != nil ("Sesle ertele", 05b D5): the text is only a new time for that item.
    /// Otherwise: command → CommandExecutor; item → CaptureDraft → router.present(.confirm(draft)).
    func handleTranscript(_ text: String, source: CaptureSource, request: ListenRequest) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AsistLog.info("Boş döküm yok sayıldı", .voice)
            return
        }
        guard ensureLoaded() else {
            reportDataUnavailable()
            return
        }
        // A "Tekrar söyle" retry produced a transcript: its result replaces the old card (03 §4.5).
        redoDraft = nil
        if let snoozeID = request.snoozeItemID {
            snoozeByVoice(trimmed, itemID: snoozeID, source: source)
            return
        }
        // "Vazgeçildi · Geri Al" of a card: bring the same card back (chip edits kept).
        if request == ListenRequest(), let restored = takeRecentlyDiscarded(matching: trimmed) {
            restored.isResolved = false
            restored.autoSaveActive = false
            presentDraft(restored)
            return
        }
        let now = Date()
        let result = parser().parse(trimmed, now: now)
        if result.kind == .command, request.kind == nil, let command = result.command {
            let timeIsDefault = result.flags.contains(.defaultTimeApplied)
            await AppEnvironment.shared.commands.run(command, originalText: trimmed, source: source,
                                                     timeIsDefault: timeIsDefault)
            return
        }
        let itemResult = captureResult(from: result, text: trimmed, forcedKind: request.kind)
        let proposal = makeProposal(itemResult, text: trimmed, source: source, request: request,
                                    interactive: true, now: now)
        let draft = CaptureDraft(heardText: trimmed, source: source, parse: itemResult, proposal: proposal,
                                 autoSaveSeconds: store.settings.autoSaveSeconds)
        draft.request = request
        presentDraft(draft)
        requestSmartInterpretation(for: draft, text: trimmed, request: request, now: now)
    }

    /// ComposeSheet "Ekle": level .autoSave → save directly + undo toast; otherwise opens the card.
    func addFromKeyboard(_ text: String, request: ListenRequest) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard ensureLoaded() else {
            reportDataUnavailable()
            return
        }
        if let snoozeID = request.snoozeItemID {
            snoozeByVoice(trimmed, itemID: snoozeID, source: .keyboard)
            return
        }
        let now = Date()
        let result = parser().parse(trimmed, now: now)
        if result.kind == .command, request.kind == nil, let command = result.command {
            let timeIsDefault = result.flags.contains(.defaultTimeApplied)
            await AppEnvironment.shared.commands.run(command, originalText: trimmed, source: .keyboard,
                                                     timeIsDefault: timeIsDefault)
            return
        }
        let itemResult = captureResult(from: result, text: trimmed, forcedKind: request.kind)
        let proposal = makeProposal(itemResult, text: trimmed, source: .keyboard, request: request,
                                    interactive: true, now: now)
        let draft = CaptureDraft(heardText: trimmed, source: .keyboard, parse: itemResult, proposal: proposal,
                                 autoSaveSeconds: store.settings.autoSaveSeconds)
        draft.request = request
        if proposal.level == .autoSave && !proposal.needsTime {
            finalize(draft, implicit: false)
        } else {
            presentDraft(draft)
            requestSmartInterpretation(for: draft, text: trimmed, request: request, now: now)
        }
    }

    /// Live preview (debounced by the view, 300 ms). Pure: nothing is stored.
    func preview(_ text: String, request: ListenRequest) -> CapturePreview? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = Date()
        let result = parser().parse(trimmed, now: now)
        if request.snoozeItemID != nil {
            return CapturePreview(understood: result.understood, level: ItemFactory.level(for: result), kind: nil)
        }
        if result.kind == .command, request.kind == nil, result.command != nil {
            return CapturePreview(understood: result.understood, level: ItemFactory.level(for: result), kind: nil)
        }
        let itemResult = captureResult(from: result, text: trimmed, forcedKind: request.kind)
        let proposal = makeProposal(itemResult, text: trimmed, source: .keyboard, request: request,
                                    interactive: true, now: now)
        let understood = itemResult.understood.isEmpty ? proposal.item.title : itemResult.understood
        return CapturePreview(understood: understood, level: proposal.level, kind: proposal.item.kind)
    }

    /// Save: `store.add`; nil or `!store.canPersist` → toast "Kaydedilemedi. Tekrar dene." and Haptics.error
    /// (05a #3); else toast "Kaydedildi · <Salı 15:00>" with undo, Haptics.success, and the TTS confirmation when
    /// `voice.shouldSpeakConfirmation(settings:)` (D18).
    func commit(_ draft: CaptureDraft) {
        finalize(draft, implicit: false)
    }

    /// Explicit "Vazgeç" on the card: nothing saved; toast "Vazgeçildi" whose "Geri Al" brings the card back.
    func discard(_ draft: CaptureDraft) {
        guard !draft.isResolved else { return }
        draft.isResolved = true
        if activeDraft?.id == draft.id {
            activeDraft = nil
        }
        let text = draft.heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            recentlyDiscarded = nil
            toasts.show("Vazgeçildi")
        } else {
            // DEVIATION(04 §3.6.8): ToastCenter (WP0 exact) has no "commit this draft" undo; its undoTranscript
            // path calls handleTranscript, which re-presents this same draft (edits kept) — one tap then saves it.
            recentlyDiscarded = draft
            recentlyDiscardedAt = Date()
            toasts.show("Vazgeçildi", undoTranscript: text)
        }
        Haptics.light()
        AsistLog.info("Onay kartı: vazgeçildi", .app)
    }

    /// Sheet swiped away / app backgrounded / call → commit unresolved active draft (03 principle 3).
    /// A late `onDismiss` of an earlier sheet while this draft's card is on screen (app active) is ignored.
    /// When the card on screen is committed (app backgrounded), the card is closed too: its draft is saved, so a
    /// stale card must not stay up with buttons that no longer do anything (its onDismiss finds no active draft).
    func commitActiveDraftIfNeeded() {
        // Leaving the app during a "Tekrar söyle" retry saves the card being retried (leaving = save).
        if redoDraft != nil && UIApplication.shared.applicationState != .active {
            commitRedoDraftIfNeeded()
        }
        guard let draft = activeDraft else { return }
        if draft.isResolved {
            activeDraft = nil
            return
        }
        var isShown = false
        if case .confirm(let shown)? = router.sheet, shown.id == draft.id {
            isShown = true
        }
        if isShown && UIApplication.shared.applicationState == .active {
            return
        }
        finalize(draft, implicit: true)
        if isShown {
            router.dismissSheet()
        }
    }

    /// True while a "Tekrar söyle" retry is pending (ListeningOverlay "Klavye" decides with it).
    var hasPendingRedo: Bool { redoDraft != nil }

    /// "Tekrar söyle" on the card: the draft is set aside (resolved, so the sheet's onDismiss does not save it)
    /// until the retry ends — a transcript replaces it, anything else brings it back (`restoreRedoDraftIfNeeded`).
    func beginRedo(_ draft: CaptureDraft) {
        guard !draft.isResolved else { return }
        if redoDraft?.id != draft.id {
            commitRedoDraftIfNeeded()                 // an older set-aside card is saved, never dropped
        }
        draft.isResolved = true
        draft.autoSaveActive = false
        if activeDraft?.id == draft.id {
            activeDraft = nil
        }
        redoDraft = draft
    }

    /// The retry ended without a transcript (silence, Vazgeç, recognizer/permission failure, busy voice): the same
    /// card comes back, edits kept, no countdown. It replaces a voice-failure "Yaz" fallback sheet if one opened.
    func restoreRedoDraftIfNeeded() {
        guard let draft = redoDraft else { return }
        redoDraft = nil
        draft.isResolved = false
        draft.autoSaveActive = false
        if draft.smartState == .working {
            draft.smartState = .idle                 // an answer that arrived while it was set aside was dropped
        }
        presentDraft(draft)
    }

    /// The retry continues in "Yaz" with new text (ListeningOverlay "Klavye"): that text replaces the old card.
    func abandonRedoDraft() {
        guard redoDraft != nil else { return }
        redoDraft = nil
        AsistLog.info("Tekrar söyle: eski kart yeni yazılan metinle değiştiriliyor", .app)
    }

    /// App left during the retry → the card is saved like any card left unconfirmed (implicit).
    private func commitRedoDraftIfNeeded() {
        guard let draft = redoDraft else { return }
        redoDraft = nil
        draft.isResolved = false
        finalize(draft, implicit: true)
    }

    /// Overlay interrupted with partial text → item with needsReview = true (03 §5.3), keeping the request's kind
    /// and project. A "Sesle ertele" utterance (request.snoozeItemID != nil) is never turned into an item and is not
    /// applied either (cut-off text may name the wrong time): the user is asked to try again.
    /// Returns true only when the item was saved (its own toast is shown here).
    @discardableResult
    func saveInterruptedTranscript(_ text: String, request: ListenRequest = ListenRequest()) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if request.snoozeItemID != nil {
            AsistLog.info("Sesle erteleme yarıda kaldı; kayıt oluşturulmadı", .voice)
            toasts.show("Erteleme yarıda kaldı. Tekrar dener misin?", seconds: 6)
            return false
        }
        guard ensureLoaded() else {
            AsistLog.error("Yarım döküm kaydedilemedi: veri dosyası okunamıyor", .store)
            toasts.show(TurkishSpeech.dataUnavailable, seconds: 6)
            return false
        }
        let now = Date()
        let result = parser().parse(trimmed, now: now)
        let itemResult = captureResult(from: result, text: trimmed, forcedKind: request.kind)
        let proposal = makeProposal(itemResult, text: trimmed, source: .voice, request: request,
                                    interactive: false, now: now)
        var item = proposal.item
        item.needsReview = true
        guard store.add(item) != nil, store.canPersist else {
            // The store keeps a change whose write failed in memory and retries it (05a #3).
            let inMemory = store.item(item.id) != nil
            AsistLog.error("Yarım döküm kaydedilemedi (bellekte: " + (inMemory ? "evet" : "hayır") + ")", .store)
            toasts.show(inMemory ? CaptureCopy.keptInMemory : CaptureCopy.saveFailed, seconds: 6)
            return false
        }
        AsistLog.info("Yarım döküm taslak olarak kaydedildi (tür=" + item.kind.rawValue + ")", .voice)
        toasts.show("Dinleme yarıda kaldı; söylediklerini taslak olarak sakladım.", seconds: 6)
        return true
    }

    /// A complete / cancel / snooze command that matched no open item ("Tedarikçideki siparişi iptal et" meant as a
    /// new task): the sentence is kept as a task marked "Emin değilim" instead of being dropped (03 §5.10).
    func saveUnmatchedCommand(text: String, source: CaptureSource) -> UnmatchedCommandSave {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed }
        guard ensureLoaded() else {
            AsistLog.error("Eşleşmeyen komut saklanamadı: veri dosyası okunamıyor", .store)
            return .failed
        }
        let now = Date()
        let result = parser().parse(trimmed, now: now)
        let itemResult = captureResult(from: result, text: trimmed, forcedKind: .task)
        let proposal = makeProposal(itemResult, text: trimmed, source: source, request: ListenRequest(),
                                    interactive: false, now: now)
        var item = proposal.item
        item.needsReview = true
        let token = store.add(item)
        if let undoToken = token, store.canPersist {
            AsistLog.info("Eşleşmeyen komut incelenecek görev olarak kaydedildi", .app)
            return .saved(undoToken)
        }
        if store.item(item.id) != nil {
            AsistLog.error("Eşleşmeyen komut diske yazılamadı (bellekte: evet)", .store)
            return .keptInMemory
        }
        AsistLog.error("Eşleşmeyen komut saklanamadı (bellekte: hayır)", .store)
        return .failed
    }

    // MARK: - Headless (Siri / Shortcut)

    /// Siri / Shortcut. Never opens UI. Exact order (D34, 05a #1/#3): load → parse → (query answer | D22 answer)
    /// or save → `await engine.reconcile(reason: "intent")` → spoken confirmation.
    func captureHeadless(text: String, source: CaptureSource) async -> String {
        // 1
        if !store.isLoaded {
            store.load()
        }
        guard store.isLoaded else {
            AsistLog.error("Siri kaydı alınamadı: veri dosyası okunamıyor", .intents)
            return TurkishSpeech.dataUnavailable
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Boş bir şey kaydedemedim. Tekrar söyler misin?"
        }
        // 2
        let now = Date()
        let calendar = AppTime.calendar
        let result = parser().parse(trimmed, now: now)
        if result.kind == .command, let command = result.command {
            return await headlessCommand(command, text: trimmed, source: source, now: now, calendar: calendar)
        }
        // 3
        let itemResult = captureResult(from: result, text: trimmed, forcedKind: nil)
        let proposal = makeProposal(itemResult, text: trimmed, source: source, request: ListenRequest(),
                                    interactive: false, now: now)
        let item = proposal.item
        guard store.add(item) != nil, store.canPersist else {
            // Spoken answer stays TurkishSpeech.saveFailed (04 §3.6.8): the intent process may be killed before the
            // in-memory copy is retried, so persistence is never promised here.
            let inMemory = store.item(item.id) != nil ? "evet" : "hayır"
            AsistLog.error("Siri kaydı diske yazılamadı (bellekte: " + inMemory + ")", .intents)
            return TurkishSpeech.saveFailed
        }
        let reviewText = item.needsReview ? "evet" : "hayır"
        let logLine = "Siri kaydı: tür=" + item.kind.rawValue + " seviye=" + proposal.level.rawValue
        AsistLog.info(logLine + " inceleme=" + reviewText, .intents)
        // 4 — never requestReconcile here: the process may be suspended right after perform() returns.
        await AppEnvironment.shared.engine.reconcile(reason: "intent")
        // 4b — WP13: a low-confidence capture may be improved by Akıllı Mod within ≤ 8 s. The on-device item is
        // already persisted and planned, so a slow or failed network never loses the capture (D34); an upgrade is
        // itself persisted and reconciled before the answer.
        var finalProposal = proposal
        if CaptureService.wantsSmartMode(itemResult, settings: store.settings),
           SmartModeClient.shared.isReady(store.settings),
           let upgraded = await upgradeHeadless(itemID: item.id, text: trimmed, source: source, onDevice: itemResult,
                                                now: now) {
            finalProposal = upgraded
        }
        // 5 (store state re-read after the await)
        let saved = store.item(item.id) ?? item
        let lowConfidence = finalProposal.level == .review || saved.needsReview
        return TurkishSpeech.confirmation(for: saved, projectName: store.projectName(for: saved), headless: true,
                                          lowConfidence: lowConfidence,
                                          appliedDefaultTime: finalProposal.appliedDefaultTime,
                                          now: now, calendar: calendar)
    }

    /// asist://kayit/<id>?eylem=yaptim → markDone + undo toast.
    func completeFromLink(_ id: UUID) {
        guard ensureLoaded() else {
            reportDataUnavailable()
            return
        }
        guard let item = store.item(id), item.isOpen else {
            toasts.show(CaptureCopy.notFound)
            Haptics.warning()
            return
        }
        let now = Date()
        guard let outcome = store.markDone(id, at: now), store.canPersist else {
            AsistLog.error("Bağlantıdan tamamlama kaydedilemedi", .store)
            toasts.show(CaptureCopy.saveFailed, seconds: 6)
            Haptics.error()
            return
        }
        toasts.show(CaptureCopy.doneToast(outcome.0, item: item, now: now, calendar: AppTime.calendar),
                    undo: outcome.1)
        Haptics.success()
    }

    // MARK: - Akıllı Mod (WP13, 04 Appendix B.2 / revision 3)

    /// Smart Mode is asked only when it is switched on with "Emin olamadığımda sor", the capture is not a command and
    /// the on-device parse is below the review threshold (`.smartModeSuggested`, confidence < 0.60) or the
    /// classifier found no kind cue (`.noKindCue`).
    static func wantsSmartMode(_ result: ParseResult, settings: AppSettings) -> Bool {
        guard settings.smartModeEnabled, settings.smartModeAutoOnLowConfidence else { return false }
        guard result.kind != .command else { return false }
        if result.flags.contains(.smartModeSuggested) || result.flags.contains(.noKindCue) {
            return true
        }
        return result.confidence < ParserSettings().smartModeThreshold
    }

    /// Interactive card: the on-device reading is already on screen; Smart Mode runs in the background and upgrades
    /// the card in place when it returns a valid, more confident item before the user touched the card. Forced-kind
    /// captures (project notes, "Takip ekle") and "Sesle ertele" are never sent.
    func requestSmartInterpretation(for draft: CaptureDraft, text: String, request: ListenRequest, now: Date) {
        guard !draft.isResolved, request.kind == nil, request.snoozeItemID == nil else { return }
        let settings = store.settings
        guard CaptureService.wantsSmartMode(draft.parse, settings: settings) else { return }
        let client = SmartModeClient.shared
        guard client.isReady(settings) else { return }
        draft.smartState = .working
        let projects = store.projects
        let places = store.places
        let hint = draft.parse.understood
        let onDeviceConfidence = draft.parse.confidence
        let calendar = AppTime.calendar
        AsistLog.info("Akıllı Mod: düşük güvenli kart yorumlatılıyor", .smart)
        Task { @MainActor [weak self] in
            let outcome = await client.interpret(utterance: text, now: now, settings: settings, projects: projects,
                                                 places: places, onDeviceHint: hint, calendar: calendar,
                                                 timeout: SmartModeClient.interactiveParseTimeout)
            guard let self = self else { return }
            self.applySmartOutcome(outcome, to: draft, text: text, request: request,
                                   onDeviceConfidence: onDeviceConfidence)
        }
    }

    private func applySmartOutcome(_ outcome: Result<ParseResult, SmartModeError>, to draft: CaptureDraft,
                                   text: String, request: ListenRequest, onDeviceConfidence: Double) {
        let smart: ParseResult
        switch outcome {
        case .failure(let error):
            AsistLog.info("Akıllı Mod: kart güncellenmedi (" + error.logCode + ")", .smart)
            if !draft.isResolved {
                draft.smartState = .failed(error.userMessage + " Cihaz içi sonuç kullanılıyor.")
            }
            return
        case .success(let value):
            smart = value
        }
        guard !draft.isResolved else {
            AsistLog.info("Akıllı Mod: cevap geldiğinde kart zaten kapanmıştı", .smart)
            return
        }
        guard smart.kind != .command, smart.item != nil else {
            draft.smartState = .unchanged("Akıllı Mod bunu bir komut olarak yorumladı; kart değiştirilmedi.")
            AsistLog.info("Akıllı Mod: komut yorumu karta uygulanmadı", .smart)
            return
        }
        guard smart.confidence > onDeviceConfidence else {
            draft.smartState = .unchanged("Akıllı Mod daha iyi bir yorum bulamadı.")
            AsistLog.info("Akıllı Mod: yorum cihaz içi sonuçtan iyi değil", .smart)
            return
        }
        guard !draft.isEdited else {
            draft.smartState = .unchanged("Kartı değiştirdiğin için Akıllı Mod önerisi uygulanmadı.")
            AsistLog.info("Akıllı Mod: kart düzenlenmişti, öneri uygulanmadı", .smart)
            return
        }
        let now = Date()
        var proposal = makeProposal(smart, text: text, source: draft.source, request: request, interactive: true,
                                    now: now)
        proposal.item.smartModeUsed = true
        proposal.item.appendHistory(.smartMode, at: now)
        draft.applySmart(parse: smart, proposal: proposal)
        Haptics.light()
        AsistLog.info("Akıllı Mod: kart güncellendi (tür=" + proposal.item.kind.rawValue + " seviye="
                      + proposal.level.rawValue + ")", .smart)
    }

    /// Headless (Siri / Shortcut) pass over the already saved and planned item. Returns Smart Mode's proposal when the
    /// item was upgraded (persisted, then reconciled — D34), else nil (the on-device item stays untouched).
    private func upgradeHeadless(itemID: UUID, text: String, source: CaptureSource, onDevice: ParseResult,
                                 now: Date) async -> CaptureProposal? {
        let settings = store.settings
        let projects = store.projects
        let places = store.places
        let outcome = await SmartModeClient.shared.interpret(utterance: text, now: now, settings: settings,
                                                             projects: projects, places: places,
                                                             onDeviceHint: onDevice.understood,
                                                             calendar: AppTime.calendar,
                                                             timeout: SmartModeClient.headlessParseTimeout)
        let smart: ParseResult
        switch outcome {
        case .failure(let error):
            AsistLog.info("Akıllı Mod (Siri): cihaz içi kayıt korundu (" + error.logCode + ")", .intents)
            return nil
        case .success(let value):
            smart = value
        }
        guard smart.kind != .command, smart.item != nil, smart.confidence > onDevice.confidence else {
            AsistLog.info("Akıllı Mod (Siri): daha iyi yorum yok, cihaz içi kayıt korundu", .intents)
            return nil
        }
        guard store.isLoaded, let current = store.item(itemID), current.isOpen else { return nil }
        let proposal = makeProposal(smart, text: text, source: source, request: ListenRequest(), interactive: false,
                                    now: Date())
        let upgraded = proposal.item
        let token = store.update(itemID, event: .smartMode) { item in
            item.kind = upgraded.kind
            item.title = upgraded.title
            item.notes = upgraded.notes
            item.priority = upgraded.priority
            item.dueDate = upgraded.dueDate
            item.hasTime = upgraded.hasTime
            item.recurrence = upgraded.recurrence
            item.leadTimesMinutes = upgraded.leadTimesMinutes
            item.isEvent = upgraded.isEvent
            item.person = upgraded.person
            item.projectID = upgraded.projectID
            item.needsReview = upgraded.needsReview
            item.parseConfidence = upgraded.parseConfidence
            item.smartModeUsed = true
        }
        guard token != nil, store.canPersist else {
            AsistLog.error("Akıllı Mod (Siri): güncelleme kaydedilemedi; cihaz içi kayıt duruyor", .store)
            return nil
        }
        AsistLog.info("Akıllı Mod (Siri): kayıt güncellendi (tür=" + upgraded.kind.rawValue + ")", .intents)
        await AppEnvironment.shared.engine.reconcile(reason: "intent.smart")
        return proposal
    }

    // MARK: - Private: drafts

    private func presentDraft(_ draft: CaptureDraft) {
        if let previous = activeDraft, previous.id != draft.id, !previous.isResolved {
            // A card that is replaced by a newer capture is saved, never dropped (03 principle 3).
            finalize(previous, implicit: true)
        }
        if router.showOnboarding {
            // The onboarding cover hides every sheet (live test "1 dakika sonra su içmeyi hatırlat"): save directly.
            finalize(draft, implicit: false)
            return
        }
        activeDraft = draft
        router.present(.confirm(draft))
        announce(draft)
    }

    private func announce(_ draft: CaptureDraft) {
        if draft.isLowConfidence || draft.needsTime {
            Haptics.warning()
        } else {
            Haptics.light()
        }
        if draft.needsTime {
            speakIfPrivate("Ne zaman hatırlatayım?", source: draft.source)
        } else if draft.isLowConfidence {
            speakIfPrivate("Emin olamadım, ekrandan kontrol eder misin?", source: draft.source)
        }
    }

    /// Saves the draft. `implicit` = the user did not tap "Kaydet" (swipe, background, replaced card).
    @discardableResult
    private func finalize(_ draft: CaptureDraft, implicit: Bool) -> UndoToken? {
        guard !draft.isResolved else { return nil }
        draft.isResolved = true
        if activeDraft?.id == draft.id {
            activeDraft = nil
        }
        let now = Date()
        let calendar = AppTime.calendar
        let settings = store.settings
        var item = draft.item
        var appliedDefault = draft.appliedDefaultTime

        // D20: a reminder whose "Ne zaman?" was never answered → "Zaman söylenmezse" setting (.ask → +1 h).
        if item.kind == .reminder && item.dueDate == nil && item.placeID == nil {
            let behavior: NoTimeBehavior = settings.noTimeBehavior == .ask ? .inOneHour : settings.noTimeBehavior
            item.dueDate = ItemFactory.noTimeDefault(behavior, now: now, settings: settings, calendar: calendar)
            item.hasTime = true
            appliedDefault = true
        }
        // 03 principle 3: an unconfirmed low-confidence card is kept, marked "Emin değilim" (after a Smart Mode
        // upgrade the level of Smart Mode's validated proposal counts).
        if implicit && draft.effectiveLevel == .review && item.kind != .note {
            item.needsReview = true
        }
        item.updatedAt = now

        let token = store.add(item)
        guard let undoToken = token, store.canPersist else {
            // A failed write keeps the item in memory and retries it (05a #3): offering a re-capture then would
            // create a duplicate, so the transcript retry is offered only when the item is really absent.
            let inMemory = store.item(item.id) != nil
            AsistLog.error("Kayıt kaydedilemedi (bellekte: " + (inMemory ? "evet" : "hayır") + ")", .store)
            let text = draft.heardText.trimmingCharacters(in: .whitespacesAndNewlines)
            if inMemory {
                toasts.show(CaptureCopy.keptInMemory, seconds: 6)
            } else if !text.isEmpty {
                // Nothing reached the store: "Geri Al" re-opens the card so the sentence is not lost.
                toasts.show(CaptureCopy.saveFailed, undoTranscript: text, seconds: 8)
            } else {
                toasts.show(CaptureCopy.saveFailed, seconds: 6)
            }
            Haptics.error()
            return nil
        }

        let saved = store.item(item.id) ?? item
        toasts.show(savedToastText(saved, now: now, calendar: calendar), undo: undoToken)
        Haptics.success()
        let implicitText = implicit ? "evet" : "hayır"
        let logLine = "Kaydedildi: tür=" + saved.kind.rawValue + " seviye=" + draft.effectiveLevel.rawValue
        let smartText = draft.smartState == .applied ? " akıllı=evet" : ""
        AsistLog.info(logLine + " örtük=" + implicitText + smartText, .app)
        if !implicit {
            let sentence = TurkishSpeech.confirmation(for: saved, projectName: store.projectName(for: saved),
                                                      headless: false, lowConfidence: false,
                                                      appliedDefaultTime: appliedDefault, now: now, calendar: calendar)
            speakIfPrivate(sentence, source: draft.source)
        }
        return undoToken
    }

    private func takeRecentlyDiscarded(matching text: String) -> CaptureDraft? {
        guard let draft = recentlyDiscarded else { return nil }
        recentlyDiscarded = nil
        guard Date().timeIntervalSince(recentlyDiscardedAt) < 15 else { return nil }
        let heard = draft.heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard heard == text else { return nil }
        return draft
    }

    private func savedToastText(_ item: Item, now: Date, calendar: Calendar) -> String {
        if item.kind == .note {
            if let name = store.projectName(for: item), !name.isEmpty {
                return "Not kaydedildi · " + name
            }
            return "Not kaydedildi"
        }
        guard let anchor = item.anchorDate else {
            // Revision 4 (07 §9.10): a place reminder without a date says where it will ring.
            if let place = store.place(item.placeID), let trigger = item.placeTrigger {
                return "Kaydedildi · " + LocationPlanner.placeLabel(name: place.name, trigger: trigger)
            }
            return "Kaydedildi · Zamanı belirsiz"
        }
        let when = TurkishDateFormatter.shortDateTime(anchor, now: now, calendar: calendar,
                                                      includeTime: item.hasTime || item.snoozedUntil != nil)
        return "Kaydedildi · " + when
    }

    // MARK: - Private: parsing helpers

    private func ensureLoaded() -> Bool {
        if !store.isLoaded {
            store.load()
        }
        return store.isLoaded
    }

    private func reportDataUnavailable() {
        AsistLog.error("İşlem yapılamadı: veri dosyası okunamıyor", .store)
        toasts.show(TurkishSpeech.dataUnavailable, seconds: 6)
        Haptics.error()
    }

    /// A result that ItemFactory can turn into an item: commands (when a kind was forced, or a malformed
    /// command without payload) become a plain item carrying the whole sentence (nothing is dropped).
    private func captureResult(from result: ParseResult, text: String, forcedKind: ItemKind?) -> ParseResult {
        if result.kind != .command && result.item != nil {
            return result
        }
        let kind = forcedKind ?? .task
        var confidence = 0.5
        if forcedKind == .note {
            confidence = 0.85
        } else if forcedKind != nil {
            confidence = 0.65
        }
        return fallbackResult(text: text, kind: kind, confidence: confidence)
    }

    private func fallbackResult(text: String, kind: ItemKind, confidence: Double) -> ParseResult {
        let title = CaptureService.fallbackTitle(text)
        let parsedKind = ParsedKind(rawValue: kind.rawValue) ?? ParsedKind.task
        let body: String? = kind == .note ? text : nil
        let parsedItem = ParsedItem(kind: kind, title: title, body: body)
        return ParseResult(kind: parsedKind, item: parsedItem, command: nil, confidence: confidence,
                           flags: [ParseFlag.titleFallback], understood: kind.label + " — " + title,
                           relativePhrase: nil, originalText: text, normalizedText: TurkishText.lower(text))
    }

    static func fallbackTitle(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Kayıt"
        }
        return TurkishText.upperFirst(TurkishText.truncated(trimmed, max: 80))
    }

    /// ItemFactory proposal; never nil (a last-resort item keeps the raw sentence, marked "Emin değilim").
    private func makeProposal(_ result: ParseResult, text: String, source: CaptureSource, request: ListenRequest,
                              interactive: Bool, now: Date) -> CaptureProposal {
        let calendar = AppTime.calendar
        let context = CaptureContext(settings: store.settings, projects: store.projects, places: store.places,
                                     forcedKind: request.kind, forcedProjectID: request.projectID,
                                     interactive: interactive)
        if let proposal = ItemFactory.proposal(from: result, source: source, context: context, now: now,
                                               calendar: calendar) {
            return proposal
        }
        let fallback = fallbackResult(text: text, kind: request.kind ?? .task, confidence: 0.5)
        if let proposal = ItemFactory.proposal(from: fallback, source: source, context: context, now: now,
                                               calendar: calendar) {
            return proposal
        }
        var item = Item(kind: request.kind ?? .task, title: CaptureService.fallbackTitle(text), originalText: text,
                        needsReview: true, source: source, parseConfidence: 0.5, createdAt: now)
        item.projectID = request.projectID
        item.appendHistory(.created, at: now)
        return CaptureProposal(item: item, level: .review, needsTime: false, appliedDefaultTime: false,
                               defaultedToToday: false, alternativeTimes: [])
    }

    // MARK: - Private: voice snooze ("Sesle ertele", 05b D5)

    private func snoozeByVoice(_ text: String, itemID: UUID, source: CaptureSource) {
        let now = Date()
        let calendar = AppTime.calendar
        guard let item = store.item(itemID), item.isOpen else {
            toasts.show(CaptureCopy.notFound)
            Haptics.warning()
            return
        }
        let result = parser().parse(text, now: now)
        guard let target = CaptureSnoozeTiming.voiceTarget(from: result, item: item, now: now, calendar: calendar) else {
            let message = "Zamanı anlayamadım. Tekrar dener misin?"
            toasts.show(message, seconds: 6)
            Haptics.warning()
            speakIfPrivate(message, source: source)
            return
        }
        guard let token = store.snooze(itemID, until: target, at: now), store.canPersist else {
            AsistLog.error("Sesle erteleme kaydedilemedi", .store)
            toasts.show(CaptureCopy.saveFailed, seconds: 6)
            Haptics.error()
            return
        }
        let label = TurkishDateFormatter.shortDateTime(target, now: now, calendar: calendar, includeTime: true)
        toasts.show("Ertelendi · " + label, undo: token)
        Haptics.success()
        AsistLog.info("Sesle ertelendi", .app)
        let sentence = "Erteledim, " + TurkishSpeech.spokenWhen(target, now: now, calendar: calendar) + " hatırlatacağım."
        speakIfPrivate(sentence, source: source)
    }

    // MARK: - Private: headless commands (D22)

    private func headlessCommand(_ command: ParsedCommand, text: String, source: CaptureSource, now: Date,
                                 calendar: Calendar) async -> String {
        switch command.type {
        case .query:
            let answer = AgendaBuilder.answer(to: command, items: store.items, projects: store.projects, now: now,
                                              settings: store.settings, calendar: calendar)
            AsistLog.info("Siri sorgusu yanıtlandı", .intents)
            return answer.text
        case .complete, .cancel, .snooze:
            let dateFilter: Date? = command.type == .snooze ? command.targetDate : command.date
            // G5 (WP1): "geldi / ulaştı / gitti" completions prefer waiting items, as in CommandExecutor.
            let preferWaiting = command.type == .complete && CommandExecutor.mentionsArrival(text)
            let ranked = FuzzyMatcher.rank(query: command.queryText, person: command.person, project: command.project,
                                           date: dateFilter, preferWaiting: preferWaiting, items: store.items,
                                           projects: store.projects, calendar: calendar)
            let decision = FuzzyMatcher.decide(ranked)
            switch decision {
            case .single(let id):
                router.request(.openItem(id))
            case .ambiguous:
                router.request(.today)
            case MatchDecision.none:
                // Nothing to complete / delete / snooze: the sentence is kept as a task to review, never dropped.
                return await headlessUnmatched(text: text, source: source)
            }
            AsistLog.info("Siri komutu uygulamaya yönlendirildi: " + command.type.rawValue, .intents)
            return "Bunun için Asist'i açman gerekiyor."
        }
    }

    private func headlessUnmatched(text: String, source: CaptureSource) async -> String {
        switch saveUnmatchedCommand(text: text, source: source) {
        case .saved:
            // Never requestReconcile here: the process may be suspended right after perform() returns.
            await AppEnvironment.shared.engine.reconcile(reason: "intent")
            AsistLog.info("Siri komutu eşleşmedi; cümle incelenecek görev olarak kaydedildi", .intents)
            return "Eşleşen kayıt bulamadım; cümleni gözden geçirmen için kaydettim."
        case .keptInMemory, .failed:
            return TurkishSpeech.saveFailed
        }
    }

    // MARK: - Private: speech

    /// D18: spoken only for voice captures and only when the route is private (or the user allowed the speaker).
    private func speakIfPrivate(_ text: String, source: CaptureSource) {
        guard source == .voice else { return }
        let voice = AppEnvironment.shared.voice
        guard voice.shouldSpeakConfirmation(settings: store.settings) else { return }
        let sentence = TurkishSpeech.dialogSafe(text)
        guard !sentence.isEmpty else { return }
        Task { @MainActor in
            await voice.speak(sentence)
        }
    }
}

// MARK: - Shared helpers (CaptureService + CommandExecutor)

/// Turkish copy shared by the capture services (03 §7.12 as amended by 04 §5.5).
enum CaptureCopy {
    /// `error.save_failed` (04 §3.6.8).
    static let saveFailed = "Kaydedilemedi. Tekrar dene."
    /// The write failed but the store keeps the change in memory and retries it: no re-capture (it would duplicate).
    static let keptInMemory = "Diske yazılamadı; kayıt bellekte duruyor, tekrar denenecek."
    static let notFound = "Kayıt bulunamadı."

    /// `toast.done` / `toast.done_recurring`.
    static func doneToast(_ result: DoneResult, item: Item, now: Date, calendar: Calendar) -> String {
        switch result {
        case .completed:
            return item.kind == .waiting ? "Geldi olarak işaretlendi" : "Tamamlandı"
        case .nextOccurrence(let next):
            let when = TurkishDateFormatter.shortDateTime(next, now: now, calendar: calendar, includeTime: item.hasTime)
            return "Bu seferlik tamamlandı · Sıradaki: " + when
        }
    }
}

/// New-time resolution for voice snooze / reschedule (03 §5.8 #26: a day without a spoken clock keeps the
/// item's own time; "yarım saat sonra" is relative to now).
enum CaptureSnoozeTiming {
    /// 366 days in minutes (same bound as `Item.leadTimesMinutes` decoding).
    static let maxMinutes = 527_040

    static func keepingClock(of item: Item, on day: Date, calendar: Calendar) -> Date {
        guard item.hasTime, let reference = item.dueDate ?? item.anchorDate else { return day }
        let parts = calendar.dateComponents([.hour, .minute], from: reference)
        let clock = ClockTime(parts.hour ?? 9, parts.minute ?? 0)
        return AsistCalendar.date(on: day, at: clock, calendar: calendar)
    }

    /// Future instant for `date` (whole minute), or nil when it lies in the past.
    static func resolve(_ date: Date, explicitTime: Bool, item: Item, now: Date, calendar: Calendar) -> Date? {
        if !explicitTime {
            let kept = keepingClock(of: item, on: date, calendar: calendar)
            if kept > now {
                return AsistCalendar.ceilToMinute(kept)
            }
        }
        if date > now {
            return AsistCalendar.ceilToMinute(date)
        }
        return nil
    }

    static func minutesTarget(_ minutes: Int, now: Date) -> Date? {
        guard minutes > 0 else { return nil }
        let clamped = min(minutes, maxMinutes)
        return AsistCalendar.ceilToMinute(now.addingTimeInterval(TimeInterval(clamped * 60)))
    }

    /// "Sesle ertele": the first of item dueDate / command.date / command.snoozeMinutes that lies in the future.
    static func voiceTarget(from result: ParseResult, item: Item, now: Date, calendar: Calendar) -> Date? {
        let defaultTimeApplied = result.flags.contains(.defaultTimeApplied)
        if let parsed = result.item, let due = parsed.dueDate {
            let explicit = parsed.hasTime && !defaultTimeApplied
            if let target = resolve(due, explicitTime: explicit, item: item, now: now, calendar: calendar) {
                return target
            }
        }
        if let command = result.command {
            if let date = command.date,
               let target = resolve(date, explicitTime: !defaultTimeApplied, item: item, now: now, calendar: calendar) {
                return target
            }
            if let minutes = command.snoozeMinutes, let target = minutesTarget(minutes, now: now) {
                return target
            }
        }
        return nil
    }

    /// Voice snooze command confirmed in MatchConfirmationSheet: command.date ?? now + (snoozeMinutes ?? 60).
    static func commandTarget(_ command: ParsedCommand, explicitTime: Bool, item: Item, now: Date,
                              calendar: Calendar) -> Date {
        if let date = command.date,
           let target = resolve(date, explicitTime: explicitTime, item: item, now: now, calendar: calendar) {
            return target
        }
        if let minutes = command.snoozeMinutes, let target = minutesTarget(minutes, now: now) {
            return target
        }
        return AsistCalendar.ceilToMinute(now.addingTimeInterval(3600))
    }
}
