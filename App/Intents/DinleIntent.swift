// FILE: App/Intents/DinleIntent.swift
import AppIntents

struct DinleIntent: AppIntent {
    static let title: LocalizedStringResource = "Asist Dinle"
    static let description: IntentDescription? = IntentDescription("Asist'i açar ve sesli komut dinlemeye başlar.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.bootstrap()
        AppEnvironment.shared.router.request(.listen(ListenRequest()))
        return .result()
    }
}

@available(*, deprecated)
extension DinleIntent {
    static var openAppWhenRun: Bool { true }
}
