// FILE: App/Services/ToastCenter.swift
import Foundation
import Observation
import AsistCore

@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id: UUID
        let text: String
        let undo: UndoToken?
        /// "Vazgeç" in the listening overlay: "Geri Al" re-opens the confirmation card with this text (05b B9).
        let undoTranscript: String?

        var hasUndo: Bool { undo != nil || undoTranscript != nil }
    }

    private(set) var current: Toast?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(_ text: String, undo: UndoToken? = nil, undoTranscript: String? = nil, seconds: Double = 5) {
        let toast = Toast(id: UUID(), text: text, undo: undo, undoTranscript: undoTranscript)
        current = toast
        hideTask?.cancel()
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard let self = self, !Task.isCancelled, self.current?.id == toast.id else { return }
            self.current = nil
        }
    }

    func performUndo() {
        guard let toast = current else { return }
        current = nil
        if let token = toast.undo {
            AppEnvironment.shared.store.undo(token)
        } else if let transcript = toast.undoTranscript {
            Task { @MainActor in
                await AppEnvironment.shared.capture.handleTranscript(transcript, source: .voice, request: ListenRequest())
            }
        }
        Haptics.selection()
    }

    func dismiss() {
        current = nil
    }
}
