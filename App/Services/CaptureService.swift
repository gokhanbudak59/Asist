// API: App/Services/CaptureService.swift
// WP0 STUB (04 §3.6.8) — replaced by WP7. Nothing is captured or saved.
import Foundation
import AsistCore

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

    /// Stores references only (never touches AppEnvironment.shared, §4.1 r13).
    init(store: DataStore, router: AppRouter, toasts: ToastCenter) {
        self.store = store
        self.router = router
        self.toasts = toasts
    }

    /// Parser for current settings/projects/places + AppTime.calendar (WP0 STUB: not cached).
    func parser() -> TurkishParser {
        let settings = ParserSettings(settings: store.settings, projects: store.projects, places: store.places)
        return TurkishParser(settings: settings, calendar: AppTime.calendar)
    }

    func invalidateParser() {}

    /// Speech-recognizer vocabulary (WP0 STUB: empty).
    func contextualStrings() -> [String] {
        []
    }

    func handleTranscript(_ text: String, source: CaptureSource, request: ListenRequest) async {}

    func addFromKeyboard(_ text: String, request: ListenRequest) async {}

    func preview(_ text: String, request: ListenRequest) -> CapturePreview? {
        nil
    }

    func commit(_ draft: CaptureDraft) {
        draft.isResolved = true
        if activeDraft?.id == draft.id { activeDraft = nil }
    }

    func discard(_ draft: CaptureDraft) {
        draft.isResolved = true
        if activeDraft?.id == draft.id { activeDraft = nil }
    }

    func commitActiveDraftIfNeeded() {}

    func saveInterruptedTranscript(_ text: String) {}

    /// Siri / Shortcut. Never opens UI. (WP0 STUB: nothing is saved; honest answer.)
    func captureHeadless(text: String, source: CaptureSource) async -> String {
        "Bu sürümde henüz kayıt alamıyorum. Asist'i açıp tekrar dener misin?"
    }

    func completeFromLink(_ id: UUID) {}
}
