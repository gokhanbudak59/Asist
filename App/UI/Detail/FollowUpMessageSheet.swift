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
        guard let item = store.item(itemID) else { return }
        text = FollowUpMessageSheet.template(for: item, allItems: store.items)
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
