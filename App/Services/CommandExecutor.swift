// API: App/Services/CommandExecutor.swift
// WP0 STUB (04 §3.6.8) — replaced by WP7. Commands are ignored.
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

    /// Stores references only (never touches AppEnvironment.shared, §4.1 r13).
    init(store: DataStore, router: AppRouter, toasts: ToastCenter) {
        self.store = store
        self.router = router
        self.toasts = toasts
    }

    func execute(_ command: ParsedCommand, originalText: String, source: CaptureSource) async {}

    /// "Oku" button, briefing "Sesli oku", asist://oku.
    func readTodayAgenda() async {}

    /// User confirmed in MatchConfirmationSheet (WP0 STUB: nothing changes).
    @discardableResult func apply(_ proposal: MatchProposal, itemID: UUID) -> UndoToken? {
        nil
    }
}
