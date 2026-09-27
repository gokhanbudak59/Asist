// API: App/Services/CaptureDraft.swift
// WP0 STUB (04 §3.6.8) — replaced by WP7. Copies the proposal; the countdown is disabled (0).
import Foundation
import Observation
import AsistCore

/// Model behind ConfirmationSheet (reference type so chips edit it in place; v1.1 Smart Mode updates it too).
@MainActor
@Observable
final class CaptureDraft: Identifiable {
    nonisolated let id: UUID         // nonisolated: read by SheetRoute.id / Identifiable from any context
    let heardText: String
    let source: CaptureSource
    let parse: ParseResult
    let level: ConfirmationLevel
    var item: Item                   // edited by chips
    var needsTime: Bool
    var alternativeTimes: [Date]
    var appliedDefaultTime: Bool
    /// D33 chips Bugün / Yarın / Zamanı belirsiz are shown.
    var defaultedToToday: Bool
    /// Countdown active; any touch sets false (03 §4.5).
    var autoSaveActive: Bool
    /// Set by commit/discard; prevents double handling on sheet dismissal.
    var isResolved: Bool = false

    init(heardText: String, source: CaptureSource, parse: ParseResult, proposal: CaptureProposal, autoSaveSeconds: Int) {
        self.id = UUID()
        self.heardText = heardText
        self.source = source
        self.parse = parse
        self.level = proposal.level
        self.item = proposal.item
        self.needsTime = proposal.needsTime
        self.alternativeTimes = proposal.alternativeTimes
        self.appliedDefaultTime = proposal.appliedDefaultTime
        self.defaultedToToday = proposal.defaultedToToday
        self.autoSaveActive = autoSaveSeconds > 0
    }

    /// 0 when auto-save must not run (WP0 STUB: always 0).
    var countdownSeconds: Int { 0 }
}
