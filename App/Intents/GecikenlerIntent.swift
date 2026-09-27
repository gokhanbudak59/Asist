// FILE: App/Intents/GecikenlerIntent.swift
import AppIntents
import AsistCore

struct GecikenlerIntent: AppIntent {
    static let title: LocalizedStringResource = "Gecikenler"
    static let description: IntentDescription? = IntentDescription("Geciken işleri sesli okur.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let env = AppEnvironment.shared
        env.bootstrap()
        if !env.store.isLoaded { env.store.load() }
        guard env.store.isLoaded else {
            return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dataUnavailable)))
        }
        let answer = AgendaBuilder.overdueSpoken(items: env.store.items, now: Date(), settings: env.store.settings,
                                                 calendar: AppTime.calendar)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dialogSafe(answer.text))))
    }
}
