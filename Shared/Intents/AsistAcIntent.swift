// FILE: Shared/Intents/AsistAcIntent.swift
// Compiled into BOTH targets (app + AsistWidgets). Controls run it: the system opens Asist and performs it in the
// app process (OpenIntent). App-only code stays inside #if ASIST_APP (07 R4-D2, §2.2 r53).
import AppIntents

enum AsistEkran: String, AppEnum, CaseIterable {
    case dinle
    case yaz

    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Asist ekranı")
    static let caseDisplayRepresentations: [AsistEkran: DisplayRepresentation] = [
        .dinle: DisplayRepresentation(title: "Dinle"),
        .yaz: DisplayRepresentation(title: "Yaz")
    ]
}

struct AsistAcIntent: OpenIntent {
    static let title: LocalizedStringResource = "Asist'i Aç"
    static let description: IntentDescription? = IntentDescription("Asist'i açar; hemen dinlemeye ya da yazmaya başlar.")

    @Parameter(title: "Ekran")
    var target: AsistEkran

    init() {}

    init(target: AsistEkran) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if ASIST_APP
        AppEnvironment.shared.bootstrap()
        switch target {
        case .dinle:
            AppEnvironment.shared.router.request(.listen(ListenRequest()))
        case .yaz:
            AppEnvironment.shared.router.request(.compose)
        }
        #endif
        return .result()
    }
}
