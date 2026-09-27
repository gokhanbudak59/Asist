// WP10 — Takip hatırlatma mesajı (03 §4.8 detail.fu_message, 05b F15).
import SwiftUI
import UIKit
import AsistCore

@MainActor
struct FollowUpMessageSheet: View {
    let itemID: UUID

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @State private var text = ""
    @State private var loaded = false
    /// WP13 "Akıllı taslak": shown only when Smart Mode is on and a key is stored (checked on appear).
    @State private var smartReady = false
    @State private var smartBusy = false
    @State private var smartStatus: String? = nil

    /// Explicit: private @State storage must not narrow the memberwise initializer's access (SheetHost.swift).
    init(itemID: UUID) {
        self.itemID = itemID
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Takip mesajı")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") {
                            router.dismissSheet()
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .onAppear {
            load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let item = store.item(itemID), item.status != .deleted {
            Form {
                Section {
                    Label(item.title, systemImage: Symbol.followUp)
                        .font(.headline)
                    if let person = item.person, !person.isEmpty {
                        Label(person, systemImage: Symbol.person)
                            .foregroundStyle(Color.secondary)
                    }
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                } header: {
                    SectionHeader(title: "MESAJ")
                } footer: {
                    Text("Göndermeden önce metni düzenleyebilirsin.")
                }
                if smartReady {
                    Section {
                        Button {
                            requestSmartDraft(item)
                        } label: {
                            HStack(spacing: 10) {
                                Label(smartButtonTitle, systemImage: Symbol.smartMode)
                                Spacer()
                                if smartBusy {
                                    ProgressView()
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(smartBusy)
                    } footer: {
                        Text(smartStatus ?? "Akıllı Mod bu takibin başlığını, kişisini, proje adını, notlarını ve hitap adını Anthropic'e gönderip kibar bir mesaj taslağı hazırlar; mevcut metnin yerine geçer.")
                    }
                }
                Section {
                    ShareLink(item: text) {
                        Label("Mesajı gönder…", systemImage: Symbol.message)
                            .frame(minHeight: 44)
                    }
                    Button {
                        UIPasteboard.general.string = text
                        toasts.show("Mesaj kopyalandı")
                        Haptics.selection()
                    } label: {
                        Label("Kopyala", systemImage: "doc.on.doc")
                            .frame(minHeight: 44)
                    }
                }
                if item.isOpen {
                    Section {
                        ChipRow {
                            Chip(title: "Yarın") {
                                askAgain(workdays: 1)
                            }
                            Chip(title: "2 gün sonra") {
                                askAgain(workdays: 2)
                            }
                            Chip(title: "Pazartesi") {
                                askAgainMonday()
                            }
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        SectionHeader(title: "YENİDEN NE ZAMAN SORALIM?")
                    } footer: {
                        Text("Mesajı gönderdikten sonra seç; o zamana kadar bu takip için sormam.")
                    }
                }
            }
        } else {
            EmptyStateView(title: "Kayıt bulunamadı",
                           message: "Bu takip silinmiş ya da artık mevcut değil.",
                           systemImage: "questionmark.folder")
        }
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        smartReady = SmartModeClient.shared.isReady(store.settings)
        guard let item = store.item(itemID) else { return }
        text = FollowUpMessageSheet.template(for: item, allItems: store.items)
    }

    private var smartButtonTitle: String {
        smartBusy ? "Taslak hazırlanıyor…" : "Akıllı taslak"
    }

    /// WP13: replaces the template with a Smart Mode draft; failures leave the text untouched and explain why.
    private func requestSmartDraft(_ item: Item) {
        guard !smartBusy else { return }
        smartBusy = true
        smartStatus = nil
        let settings = store.settings
        let projectName = store.projectName(for: item)
        let now = Date()
        let calendar = AppTime.calendar
        Task { @MainActor in
            let result = await SmartModeClient.shared.draftMessage(for: item, projectName: projectName,
                                                                   settings: settings, now: now, calendar: calendar)
            smartBusy = false
            switch result {
            case .success(let message):
                text = message
                smartStatus = "Akıllı Mod ile hazırlandı. Göndermeden önce kontrol et."
                Haptics.success()
            case .failure(let error):
                smartStatus = error.userMessage
                Haptics.warning()
            }
        }
    }

    private func askAgain(workdays: Int) {
        let target = NagPlanner.followUpAsk(after: Date(), workdays: workdays, settings: store.settings,
                                            calendar: AppTime.calendar)
        DetailItemActions.snooze(itemID, until: target, store: store, toasts: toasts)
        router.dismissSheet()
    }

    private func askAgainMonday() {
        let target = NagPlanner.nextMonday(now: Date(), settings: store.settings, calendar: AppTime.calendar)
        DetailItemActions.snooze(itemID, until: target, store: store, toasts: toasts)
        router.dismissSheet()
    }

    // MARK: - Template (03 detail.fu_message.template, 05b F15)

    /// "Merhaba Ahmet Bey, teklif konusunda son durum nedir? Teşekkürler." — the name is used only when the
    /// person field looks like a person (honorific or a person known from earlier records), else "Merhaba,".
    static func template(for item: Item, allItems: [Item]) -> String {
        let topic = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var greeting = "Merhaba,"
        if let person = item.person?.trimmingCharacters(in: .whitespacesAndNewlines), !person.isEmpty,
           looksLikePerson(person, allItems: allItems) {
            greeting = "Merhaba " + person + ","
        }
        if topic.isEmpty {
            return greeting + " son durum nedir? Teşekkürler."
        }
        return greeting + " " + topic + " konusunda son durum nedir? Teşekkürler."
    }

    private static let honorifics: Set<String> = [
        "bey", "beyefendi", "hanim", "hanimefendi", "hn", "bay", "bayan", "sayin", "abi", "abla", "hoca", "hocam",
        "usta", "sef", "mudur", "muhendis", "dr", "prof"
    ]

    private static let companyWords: Set<String> = [
        "as", "ltd", "sti", "san", "tic", "gmbh", "inc", "corp", "co", "ag", "sa", "srl", "spa", "bv", "llc",
        "otomasyon", "elektrik", "elektronik", "makina", "makine", "muhendislik", "firma", "firmasi", "sirket",
        "sirketi", "holding", "grup", "group", "fabrika", "fabrikasi", "teknik", "teknoloji", "enerji", "sanayi",
        "ticaret", "insaat", "lojistik", "tedarik", "servis", "robotik", "kontrol", "sistem", "sistemleri"
    ]

    private static let brandNames: Set<String> = [
        "siemens", "abb", "festo", "schneider", "omron", "beckhoff", "rockwell", "allen", "sick", "balluff", "pilz",
        "fanuc", "kuka", "yaskawa", "mitsubishi", "delta", "danfoss", "sew", "lenze", "phoenix", "wago", "turck",
        "ifm", "bosch", "rexroth", "smc", "keyence", "ford", "tofas", "toyota", "renault", "arcelik", "vestel",
        "beko", "eaton", "legrand", "weidmuller", "rittal", "murrelektronik", "pepperl", "banner", "cognex",
        "endress", "vega", "krohne", "emerson", "honeywell", "yokogawa", "hitachi", "panasonic", "lg", "samsung"
    ]

    static func looksLikePerson(_ person: String, allItems: [Item]) -> Bool {
        let key = TurkishText.searchKey(person)
        guard !key.isEmpty else { return false }
        let words = key.split(separator: " ").map { String($0) }
        for word in words where honorifics.contains(word) {
            return true
        }
        for word in words where companyWords.contains(word) || brandNames.contains(word) {
            return false
        }
        if key.hasSuffix(" a s") {
            return false            // "Kaya Makina A.Ş."
        }
        if isAllCapsAcronym(person) {
            return false            // "ABB", "FESTO", "TEİAŞ"
        }
        let known = ParserSettings.frequentPeople(in: allItems, minCount: 2)
        for name in known where TurkishText.searchKey(name) == key {
            return true
        }
        return false
    }

    private static func isAllCapsAcronym(_ text: String) -> Bool {
        let letters = text.filter { $0.isLetter }
        guard letters.count >= 2 else { return false }
        return TurkishText.upper(letters) == letters
    }
}
