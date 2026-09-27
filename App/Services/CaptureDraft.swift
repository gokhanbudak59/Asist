// API: App/Services/CaptureDraft.swift
// WP7 (04 §3.6.8, 03 §4.5, D10/D20/D33): model behind ConfirmationSheet.
import Foundation
import Observation
import UIKit
import AsistCore

/// Model behind ConfirmationSheet (reference type so chips edit it in place; v1.1 Smart Mode updates it too).
///
/// Countdown rules (03 §4.5, D10):
/// - level `.autoSave` (confidence ≥ 0.80) → `settings.autoSaveSeconds` (0 = kapalı, 3 / 4 / 6);
/// - level `.confirm` (0.60 ..< 0.80) → 6 s (never shorter than the user's setting);
/// - level `.review`, `needsTime`, VoiceOver running or the setting "Kapalı" → no countdown (0).
/// Any touch on the card calls `touch()` (or sets `autoSaveActive = false`) and stops the countdown for good.
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

    /// The item exactly as the parser/ItemFactory proposed it (`revertToProposal()` undoes chip edits).
    let proposedItem: Item
    /// `AppSettings.autoSaveSeconds` at the moment the card was created (clamped 0…10).
    let autoSaveSetting: Int
    /// Moment the card was created.
    let createdAt: Date

    init(heardText: String, source: CaptureSource, parse: ParseResult, proposal: CaptureProposal, autoSaveSeconds: Int) {
        let clampedSetting = min(10, max(0, autoSaveSeconds))
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
            return max(6, autoSaveSeconds)
        case .review:
            return 0
        }
    }
}
