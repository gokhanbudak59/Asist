// FILE: App/Intents/BugunIntent.swift
import AppIntents
import AsistCore

struct BugunIntent: AppIntent {
    static let title: LocalizedStringResource = "Bugün Ne Var"
    static let description: IntentDescription? = IntentDescription("Bugünkü ve geciken işleri sesli özetler.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let env = AppEnvironment.shared
        env.bootstrap()
        if !env.store.isLoaded { env.store.load() }
        guard env.store.isLoaded else {
            return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dataUnavailable)))
        }
        let answer = AgendaBuilder.todaySpoken(items: env.store.items, projects: env.store.projects, now: Date(),
                                               settings: env.store.settings, calendar: AppTime.calendar)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dialogSafe(answer.text))))
    }
}
