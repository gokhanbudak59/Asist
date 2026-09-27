// FILE: App/UI/DesignSystem/Tokens.swift
import SwiftUI
import UIKit
import AsistCore

extension Color {
    static let asistOverdue = Color.red
    static let asistToday = Color.orange
    static let asistUpcoming = Color.blue
    static let asistDone = Color.green
    static let asistNote = Color.gray
    static let asistFollowUp = Color.teal
    static let asistReview = Color.yellow
    static let asistAccent = Color.indigo
    static let asistBackground = Color(uiColor: .systemGroupedBackground)
    static let asistCard = Color(uiColor: .secondarySystemGroupedBackground)

    static func project(_ color: ProjectColor) -> Color {
        switch color {
        case .blue: return Color.blue
        case .green: return Color.green
        case .orange: return Color.orange
        case .red: return Color.red
        case .purple: return Color.purple
        case .teal: return Color.teal
        case .pink: return Color.pink
        case .brown: return Color.brown
        }
    }
}

enum Metrics {
    static let micLarge: CGFloat = 88
    static let micFloating: CGFloat = 64
    static let listeningDoneHeight: CGFloat = 72
    static let primaryButtonHeight: CGFloat = 56
    static let chipHeight: CGFloat = 44
    static let chipMinWidth: CGFloat = 64
    static let chipSpacing: CGFloat = 8
    static let rowMinHeight: CGFloat = 64
    static let completionVisual: CGFloat = 28
    static let completionHitArea: CGFloat = 44
    static let cornerRadius: CGFloat = 14
    static let padding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let stripeWidth: CGFloat = 4
}

enum Symbol {
    static let reminder = "bell.fill"
    static let task = "circle"
    static let taskDone = "checkmark.circle.fill"
    static let note = "note.text"
    static let followUp = "hourglass"
    static let recurrence = "repeat"
    static let preAlert = "bell.badge"
    static let place = "location.fill"
    static let project = "folder.fill"
    static let person = "person.fill"
    static let checklist = "checklist"
    static let critical = "flag.fill"
    static let important = "exclamationmark.circle.fill"
    static let overdue = "exclamationmark.triangle.fill"
    static let mic = "mic.fill"
    static let listening = "waveform"
    static let stop = "stop.circle.fill"
    static let keyboard = "keyboard"
    static let speak = "speaker.wave.2.fill"
    static let briefing = "sunrise.fill"
    static let endOfDay = "moon.fill"
    static let snooze = "clock.arrow.circlepath"
    static let mute = "bell.slash.fill"
    static let event = "calendar"
    static let voiceSnooze = "mic.badge.plus"
    static let smartMode = "sparkles"
    static let email = "envelope.fill"
    static let message = "paperplane.fill"
    static let export = "square.and.arrow.up"
    static let importData = "square.and.arrow.down"
    static let backTap = "hand.tap.fill"
    static let review = "questionmark.circle.fill"
    static let tabToday = "sun.max.fill"
    static let tabLists = "list.bullet"
    static let tabProjects = "folder.fill"
    static let tabSettings = "gearshape.fill"
}

extension ItemKind {
    var symbol: String {
        switch self {
        case .reminder: return Symbol.reminder
        case .task: return Symbol.task
        case .note: return Symbol.note
        case .waiting: return Symbol.followUp
        }
    }
}

extension Item {
    /// Row stripe/time color: overdue red, today orange, waiting teal, note gray, else blue.
    func statusColor(now: Date, calendar: Calendar) -> Color {
        if kind == .note { return Color.asistNote }
        if isOverdue(at: now, calendar: calendar) { return Color.asistOverdue }
        if kind == .waiting { return Color.asistFollowUp }
        if isDueToday(at: now, calendar: calendar) { return Color.asistToday }
        return Color.asistUpcoming
    }
}
