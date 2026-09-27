// API: App/Services/CaptureDraft.swift
// WP7 (04 §3.6.8, 03 §4.5, D10/D20/D33): model behind ConfirmationSheet.
import Foundation
import Observation
import UIKit
import AsistCore

/// WP13: state of the background Akıllı Mod interpretation of a low-confidence card (shown as a badge).
enum SmartDraftState: Equatable {
    case idle
    case working
    /// The card now shows Smart Mode's reading ("Akıllı Mod ile yorumlandı").
    case applied
    /// Valid answer but the card was kept (not better, a command, or the user already edited the card).
    case unchanged(String)
    /// Network / key / refusal …: the on-device result stays (Turkish user text).
    case failed(String)
}

/// Model behind ConfirmationSheet (reference type so chips edit it in place; v1.1 Smart Mode updates it too).
///
/// Countdown rules (03 §4.5, D10):
/// - level `.autoSave` (confidence ≥ 0.80) → `settings.autoSaveSeconds` (0 = kapalı, 3 / 4 / 6);
/// - level `.confirm` (0.60 ..< 0.80) → 6 s (never shorter than the user's setting);
/// - level `.review`, `needsTime`, VoiceOver running or the setting "Kapalı" → no countdown (0).
/// Any touch on the card calls `touch()` (or sets `autoSaveActive = false`) and stops the countdown for good.
/// A Smart Mode upgrade (`applySmart`) never starts a countdown: `level` stays the on-device level.
@MainActor
@Observable
final class CaptureDraft: Identifiable {
    nonisolated let id: UUID         // nonisolated: read by SheetRoute.id / Identifiable from any context
    let heardText: String
    let source: CaptureSource
    /// On-device parse; replaced by Smart Mode's validated reading in `applySmart`.
    private(set) var parse: ParseResult
    /// On-device confirmation level (drives the countdown; never changed afterwards).
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
    /// The capture context the card came from (forced kind / project, e.g. "Bu projeye sesli not");
    /// "Tekrar söyle" listens again with it.
    var request: ListenRequest = ListenRequest()

    /// The item exactly as the parser/ItemFactory (or Smart Mode) proposed it (`revertToProposal()` undoes chip edits).
    private(set) var proposedItem: Item
    /// WP13 badge state.
    var smartState: SmartDraftState = .idle
    /// Level of Smart Mode's proposal once applied (nil = on-device reading).
    private(set) var smartLevel: ConfirmationLevel? = nil
    /// Incremented by every `applySmart` so the sheet re-syncs its local text fields.
    private(set) var smartRevision: Int = 0
    /// `AppSettings.autoSaveSeconds` at the moment the card was created (clamped 0…30).
    let autoSaveSetting: Int
    /// Moment the card was created.
    let createdAt: Date

    init(heardText: String, source: CaptureSource, parse: ParseResult, proposal: CaptureProposal, autoSaveSeconds: Int) {
        let clampedSetting = min(30, max(0, autoSaveSeconds))
        let seconds = CaptureDraft.countdown(level: proposal.level, needsTime: proposal.needsTime,
                                             autoSaveSeconds: clampedSetting)
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
        self.autoSaveActive = seconds > 0
        self.proposedItem = proposal.item
        self.autoSaveSetting = clampedSetting
        self.createdAt = Date()
    }

    /// 0 when auto-save must not run (review level, needsTime, VoiceOver running, autoSaveSeconds == 0).
    /// This is the configured length of the countdown; whether it is still running is `autoSaveActive`.
    var countdownSeconds: Int {
        CaptureDraft.countdown(level: level, needsTime: needsTime, autoSaveSeconds: autoSaveSetting)
    }

    /// Any user interaction with the card: the countdown stops and does not restart (03 §4.5).
    func touch() {
        if autoSaveActive {
            autoSaveActive = false
        }
    }

    /// true when a chip changed anything compared to the proposal.
    var isEdited: Bool {
        item != proposedItem
    }

    /// Undoes all chip edits (back to the parser's proposal). Counts as a touch.
    func revertToProposal() {
        touch()
        item = proposedItem
    }

    /// Low-confidence card ("Bunu mu demek istedin?", 03 §5.5).
    var isLowConfidence: Bool {
        level == .review
    }

    /// Level used when the card is saved without confirmation (03 principle 3): Smart Mode's level once applied.
    var effectiveLevel: ConfirmationLevel {
        smartLevel ?? level
    }

    /// WP13: replaces the card's content with Smart Mode's validated reading. Callers check `isResolved` and
    /// `isEdited` first (a user edit is never overwritten). A running countdown stops: changed content is never
    /// auto-saved unseen (a swipe / background still saves it, 03 principle 3).
    func applySmart(parse newParse: ParseResult, proposal: CaptureProposal) {
        autoSaveActive = false
        parse = newParse
        item = proposal.item
        proposedItem = proposal.item
        needsTime = proposal.needsTime
        alternativeTimes = proposal.alternativeTimes
        appliedDefaultTime = proposal.appliedDefaultTime
        defaultedToToday = proposal.defaultedToToday
        smartLevel = proposal.level
        smartState = .applied
        smartRevision += 1
    }

    // MARK: - Countdown rule

    static func countdown(level: ConfirmationLevel, needsTime: Bool, autoSaveSeconds: Int) -> Int {
        if autoSaveSeconds <= 0 || needsTime {
            return 0
        }
        if UIAccessibility.isVoiceOverRunning {
            return 0
        }
        switch level {
        case .autoSave:
            return autoSaveSeconds
        case .confirm:
            return autoSaveSeconds + 5              // medium confidence: a little longer to read
        case .review:
            return 0
        }
    }
}
