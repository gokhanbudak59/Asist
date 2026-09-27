// FILE: App/Intents/KaydetIntent.swift
import AppIntents
import AsistCore

struct KaydetIntent: AppIntent {
    static let title: LocalizedStringResource = "Asist'e Kaydet"
    static let description: IntentDescription? = IntentDescription("Söylediğini hatırlatma, görev, not veya takip olarak kaydeder. Uygulama açılmaz.")

    @Parameter(title: "Metin", requestValueDialog: IntentDialog("Ne kaydedeyim?"))
    var metin: String

    static var parameterSummary: some ParameterSummary {
        Summary("Kaydet: \(\.$metin)")
    }

    init() {}

    init(metin: String) {
        self.metin = metin
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: "Boş bir şey kaydedemedim. Tekrar söyler misin?")))
        }
        AppEnvironment.shared.bootstrap()
        // captureHeadless persists AND awaits the reconcile before returning (D34, 05a #1).
        let sentence = await AppEnvironment.shared.capture.captureHeadless(text: text, source: CaptureSource.siri)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: TurkishSpeech.dialogSafe(sentence))))
    }
}
