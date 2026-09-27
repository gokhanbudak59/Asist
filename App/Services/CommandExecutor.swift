// API: App/Services/CommandExecutor.swift
// WP7 (04 §3.6.8; 03 §5.9–5.10; 02 §10.5–10.6; G3–G6): spoken queries, voice complete / cancel / snooze /
// reschedule with fuzzy matching and an explicit confirmation sheet.
import Foundation
import AsistCore

struct MatchProposal: Identifiable {
    let id: UUID
    let command: ParsedCommand
    let candidates: [UUID]           // 1…3
    let decision: MatchDecision
}

@MainActor
final class CommandExecutor {
    private let store: DataStore
    private let router: AppRouter
    private let toasts: ToastCenter

    /// Snooze proposals whose new date carried no spoken clock time: the item keeps its own time on that day
    /// (03 §5.8 #26 "Teklifi perşembeye ertele" → Perşembe 15:00).
    private var dayOnlySnoozes: Set<UUID> = []

    /// Stores references only (never touches AppEnvironment.shared, §4.1 r13).
    init(store: DataStore, router: AppRouter, toasts: ToastCenter) {
        self.store = store
        self.router = router
        self.toasts = toasts
    }

    /// query → AgendaBuilder.answer → router.present(.agenda(answer)) + voice.speak(answer.text) (always spoken, D18);
    /// complete/cancel/snooze → FuzzyMatcher → .single/.ambiguous → router.present(.match(proposal)) + spoken
    /// question; .none → toast "Buna uyan bir kayıt bulamadım."
    func execute(_ command: ParsedCommand, originalText: String, source: CaptureSource) async {
        var timeIsDefault = false
        if command.type == .snooze && command.date != nil {
            // The command carries no "time was a default" bit; the parser's flags have it.
            let reparsed = AppEnvironment.shared.capture.parser().parse(originalText, now: Date())
            timeIsDefault = reparsed.flags.contains(.defaultTimeApplied)
        }
        await run(command, originalText: originalText, source: source, timeIsDefault: timeIsDefault)
    }

    /// Same as `execute`, for callers that already hold the parse flags (CaptureService).
    func run(_ command: ParsedCommand, originalText: String, source: CaptureSource, timeIsDefault: Bool) async {
        if !store.isLoaded {
            store.load()
        }
        guard store.isLoaded else {
            AsistLog.error("Komut uygulanamadı: veri dosyası okunamıyor", .store)
            toasts.show(TurkishSpeech.dataUnavailable, seconds: 6)
            Haptics.error()
            return
        }
        let now = Date()
        let calendar = AppTime.calendar
        AsistLog.info("Komut: " + command.type.rawValue, .app)
        switch command.type {
        case .query:
            let answer = AgendaBuilder.answer(to: command, items: store.items, projects: store.projects, now: now,
                                              settings: store.settings, calendar: calendar)
            await presentAnswer(answer)
        case .complete, .cancel, .snooze:
            await proposeMatch(command, originalText: originalText, source: source, timeIsDefault: timeIsDefault,
                               now: now, calendar: calendar)
        }
    }

    /// "Oku" button, briefing "Sesli oku", asist://oku.
    func readTodayAgenda() async {
        if !store.isLoaded {
            store.load()
        }
        guard store.isLoaded else {
            AsistLog.error("Ajanda okunamadı: veri dosyası okunamıyor", .store)
            toasts.show(TurkishSpeech.dataUnavailable, seconds: 6)
            Haptics.error()
            return
        }
        let voice = AppEnvironment.shared.voice
        if voice.phase == .speaking {
            voice.stopSpeaking()
        }
        let answer = AgendaBuilder.todaySpoken(items: store.items, projects: store.projects, now: Date(),
                                               settings: store.settings, calendar: AppTime.calendar)
        await presentAnswer(answer)
    }

    /// User confirmed in MatchConfirmationSheet. Snooze target = command.date ?? now + (snoozeMinutes ?? 60).
    /// Cancel = delete (always confirmed by the sheet). Returns the undo token shown in the toast.
    @discardableResult func apply(_ proposal: MatchProposal, itemID: UUID) -> UndoToken? {
        let dayOnly = dayOnlySnoozes.contains(proposal.id)
        dayOnlySnoozes.remove(proposal.id)
        if !store.isLoaded {
            store.load()
        }
        guard store.isLoaded else {
            AsistLog.error("Eşleşme uygulanamadı: veri dosyası okunamıyor", .store)
            toasts.show(TurkishSpeech.dataUnavailable, seconds: 6)
            Haptics.error()
            return nil
        }
        guard let item = store.item(itemID), item.isOpen else {
            toasts.show(CaptureCopy.notFound)
            Haptics.warning()
            return nil
        }
        let now = Date()
        let calendar = AppTime.calendar
        switch proposal.command.type {
        case .complete:
            guard let outcome = store.markDone(itemID, at: now), store.canPersist else {
                reportSaveFailed("tamamlama")
                return nil
            }
            toasts.show(CaptureCopy.doneToast(outcome.0, item: item, now: now, calendar: calendar), undo: outcome.1)
            Haptics.success()
            AsistLog.info("Sesle tamamlandı", .app)
            speakConfirmation(item.kind == .waiting ? "Geldi olarak işaretledim." : "Tamamlandı olarak işaretledim.")
            return outcome.1
        case .cancel:
            guard let token = store.delete(itemID, at: now), store.canPersist else {
                reportSaveFailed("silme")
                return nil
            }
            toasts.show("Silindi", undo: token)
            Haptics.success()
            AsistLog.info("Sesle silindi", .app)
            speakConfirmation("Sildim.")
            return token
        case .snooze:
            let target = CaptureSnoozeTiming.commandTarget(proposal.command, explicitTime: !dayOnly, item: item,
                                                           now: now, calendar: calendar)
            guard let token = store.snooze(itemID, until: target, at: now), store.canPersist else {
                reportSaveFailed("erteleme")
                return nil
            }
            let label = TurkishDateFormatter.shortDateTime(target, now: now, calendar: calendar, includeTime: true)
            toasts.show("Ertelendi · " + label, undo: token)
            Haptics.success()
            AsistLog.info("Sesle ertelendi", .app)
            speakConfirmation("Erteledim, " + TurkishSpeech.spokenWhen(target, now: now, calendar: calendar)
                              + " hatırlatacağım.")
            return token
        case .query:
            return nil
        }
    }

    // MARK: - Private

    private func presentAnswer(_ answer: SpokenAnswer) async {
        router.present(.agenda(answer))
        Haptics.light()
        let text = TurkishSpeech.dialogSafe(answer.text)
        guard !text.isEmpty else { return }
        // Query answers are always spoken (D18); the voice coordinator picks the route.
        await AppEnvironment.shared.voice.speak(text)
    }

    private func proposeMatch(_ command: ParsedCommand, originalText: String, source: CaptureSource,
                              timeIsDefault: Bool, now: Date, calendar: Calendar) async {
        // Snooze: `date` is the NEW time, `targetDate` filters the item (G3); complete/cancel: `date` filters.
        let dateFilter: Date? = command.type == .snooze ? command.targetDate : command.date
        let preferWaiting = command.type == .complete && CommandExecutor.mentionsArrival(originalText)
        let ranked = FuzzyMatcher.rank(query: command.queryText, person: command.person, project: command.project,
                                       date: dateFilter, preferWaiting: preferWaiting, items: store.items,
                                       projects: store.projects, calendar: calendar)
        let decision = FuzzyMatcher.decide(ranked)

        var rawCandidates: [UUID] = []
        switch decision {
        case .single(let id):
            rawCandidates = [id]
        case .ambiguous(let ids):
            rawCandidates = ids
        case MatchDecision.none:
            rawCandidates = []
        }
        var candidates: [UUID] = []
        for id in rawCandidates where !candidates.contains(id) {
            if let item = store.item(id), item.isOpen {
                candidates.append(id)
            }
            if candidates.count == 3 {
                break
            }
        }

        guard let first = candidates.first, let firstItem = store.item(first) else {
            AsistLog.info("Komut için eşleşme bulunamadı: " + command.type.rawValue, .app)
            let message = "Buna uyan bir kayıt bulamadım."
            toasts.show(message)
            Haptics.warning()
            await speakIfVoice(message, source: source)
            return
        }

        let finalDecision: MatchDecision = candidates.count == 1 ? .single(first) : .ambiguous(candidates)
        let proposal = MatchProposal(id: UUID(), command: command, candidates: candidates, decision: finalDecision)
        if command.type == .snooze && timeIsDefault {
            if dayOnlySnoozes.count > 50 {
                dayOnlySnoozes.removeAll()
            }
            dayOnlySnoozes.insert(proposal.id)
        }
        router.present(.match(proposal))
        Haptics.light()
        AsistLog.info("Eşleşme onayı istendi: " + command.type.rawValue + " aday=" + String(candidates.count), .app)

        if candidates.count == 1 {
            let prompt = question(for: command, item: firstItem, dayOnly: timeIsDefault, now: now,
                                  calendar: calendar)
            await speakIfVoice(prompt, source: source)
        } else {
            await speakIfVoice("Birden fazla kayıt buldum, ekrandan seçer misin?", source: source)
        }
    }

    /// 03 §7.12 `tts.confirm_done` / `tts.confirm_delete`; snooze names the new time without a suffix after it.
    private func question(for command: ParsedCommand, item: Item, dayOnly: Bool, now: Date,
                          calendar: Calendar) -> String {
        let quoted = "“" + TurkishText.truncated(item.title, max: 60) + "”"
        switch command.type {
        case .complete:
            return item.kind == .waiting ? quoted + " geldi mi?" : quoted + " tamamlandı mı?"
        case .cancel:
            return quoted + " silinsin mi?"
        case .snooze:
            let target = CaptureSnoozeTiming.commandTarget(command, explicitTime: !dayOnly, item: item, now: now,
                                                           calendar: calendar)
            let when = TurkishSpeech.spokenWhen(target, now: now, calendar: calendar)
            return quoted + " ertelensin mi? Yeni zaman: " + when + "."
        case .query:
            return ""
        }
    }

    /// G5: "geldi / ulaştı / elime geçti / teslim alındı / gitti" → waiting items are preferred.
    static func mentionsArrival(_ text: String) -> Bool {
        let key = " " + TurkishText.searchKey(text) + " "
        let cues: [String] = [" geldi ", " ulasti ", " elime gecti ", " teslim alindi ", " gitti "]
        for cue in cues where key.contains(cue) {
            return true
        }
        return false
    }

    /// Questions and "not found" are spoken for voice commands (the user is talking to the app).
    private func speakIfVoice(_ text: String, source: CaptureSource) async {
        guard source == .voice else { return }
        let sentence = TurkishSpeech.dialogSafe(text)
        guard !sentence.isEmpty else { return }
        await AppEnvironment.shared.voice.speak(sentence)
    }

    /// Result confirmations follow D18 (private route or "Hoparlörden de söyle").
    private func speakConfirmation(_ text: String) {
        let voice = AppEnvironment.shared.voice
        guard voice.shouldSpeakConfirmation(settings: store.settings) else { return }
        let sentence = TurkishSpeech.dialogSafe(text)
        guard !sentence.isEmpty else { return }
        Task { @MainActor in
            await voice.speak(sentence)
        }
    }

    private func reportSaveFailed(_ action: String) {
        AsistLog.error("Sesli komut kaydedilemedi: " + action, .store)
        toasts.show(CaptureCopy.saveFailed, seconds: 6)
        Haptics.error()
    }
}
