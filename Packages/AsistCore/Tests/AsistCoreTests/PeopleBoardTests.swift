import Foundation
import XCTest
@testable import AsistCore

/// 07 §8.2 / §13: the Kişiler board (people derived from items) and the combined Takip reminder message.
/// Reference instant: Sun 2026-09-27 10:30 (Europe/Istanbul).
final class PeopleBoardTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let now = TestSupport.date("2026-09-27T10:30")

    private func makeItem(_ kind: ItemKind, _ title: String, due: String? = nil, hasTime: Bool = false,
                          person: String? = nil, created: String = "2026-09-20T09:00",
                          updated: String? = nil) -> Item {
        Item(kind: kind, title: title, dueDate: due.map { TestSupport.date($0) }, hasTime: hasTime, person: person,
             createdAt: TestSupport.date(created), updatedAt: updated.map { TestSupport.date($0) })
    }

    private func done(_ title: String, person: String?, completed: String) -> Item {
        var item = makeItem(.task, title, due: "2026-06-01T09:00", person: person, created: "2026-06-01T09:00",
                            updated: completed)
        item.status = .done
        item.completedAt = TestSupport.date(completed)
        return item
    }

    /// Ahmet (3 follow-ups, 1 overdue, 4 spellings of one key), a title mention, Mehmet (open task), Veli (one
    /// follow-up), Ayşe (activity 7 days ago), Yakın (57 days ago), Eski Firma (149 days ago).
    private func fixture() -> [Item] {
        [
            makeItem(.waiting, "I/O listesi", due: "2026-09-22T10:00", person: "Ahmet", created: "2026-09-20T09:00"),
            makeItem(.waiting, "Fiyat teklifi", due: "2026-09-29T10:00", person: "ahmet ",
                     created: "2026-09-25T09:00"),
            makeItem(.waiting, "Numune", due: "2026-09-28T10:00", person: "AHMET", created: "2026-09-27T08:00"),
            done("Pano şeması", person: "Ahmet", completed: "2026-09-26T16:00"),
            makeItem(.task, "Ahmet'e teklifi gönder", created: "2026-09-26T09:00"),
            makeItem(.task, "Mehmet ile görüş", person: "Mehmet", created: "2026-09-26T09:00"),
            makeItem(.waiting, "Kalibrasyon raporu", due: "2026-09-30T10:00", person: "Veli",
                     created: "2026-09-25T09:00"),
            done("Eğitim planı", person: "Ayşe", completed: "2026-09-20T10:00"),
            done("Servis raporu", person: "Yakın", completed: "2026-08-01T10:00"),
            done("Eski sipariş", person: "Eski Firma", completed: "2026-05-01T10:00")
        ]
    }

    // MARK: - Grouping and display name

    func testSpellingsGroupIntoOneKey() {
        XCTAssertEqual(PeopleBoard.key(for: " Ahmet "), "ahmet")
        XCTAssertEqual(PeopleBoard.key(for: "AHMET"), "ahmet")
        XCTAssertEqual(PeopleBoard.key(for: "Ayşe"), "ayse")
        let board = PeopleBoard.build(items: fixture(), now: now, calendar: calendar)
        let ahmet = board.filter { $0.key == "ahmet" }
        XCTAssertEqual(ahmet.count, 1)
        XCTAssertEqual(ahmet.first?.displayName, "Ahmet")          // 2 of 4 spellings
        XCTAssertEqual(ahmet.first?.followUps.count, 3)
    }

    func testDisplayNameTieUsesTheMostRecentlyUpdatedSpelling() {
        let items = [
            makeItem(.task, "Birinci", person: "Ali", created: "2026-09-10T09:00", updated: "2026-09-20T09:00"),
            makeItem(.task, "İkinci", person: "ALİ", created: "2026-09-10T09:00", updated: "2026-09-26T09:00")
        ]
        let summary = PeopleBoard.summary(forKey: "ali", items: items, now: now, calendar: calendar)
        XCTAssertEqual(summary?.displayName, "ALİ")
    }

    // MARK: - Honorifics

    func testKeyDropsTrailingHonorificsAndLeadingSayin() {
        XCTAssertEqual(PeopleBoard.key(for: "Ahmet Bey"), "ahmet")
        XCTAssertEqual(PeopleBoard.key(for: "Ayşe Hanım"), "ayse")
        XCTAssertEqual(PeopleBoard.key(for: "Sayın Hasan Bey"), "hasan")
        XCTAssertEqual(PeopleBoard.key(for: "Mehmet Ağabey"), "mehmet")
        XCTAssertEqual(PeopleBoard.key(for: "Kemal Hocam"), "kemal")
        XCTAssertEqual(PeopleBoard.key(for: "Ali Usta"), "ali")
        XCTAssertEqual(PeopleBoard.key(for: "Usta Ahmet"), "usta ahmet", "only trailing honorifics are dropped")
        XCTAssertEqual(PeopleBoard.key(for: "Şef"), "sef", "a name made only of an honorific keeps its key")
        XCTAssertEqual(PeopleBoard.key(for: "Ahmet Ak"), "ahmet ak")
        XCTAssertEqual(PeopleBoard.key(for: "  "), "")
    }

    func testHonorificSpellingsMergeIntoOnePerson() {
        let items = [
            makeItem(.waiting, "Teklif", due: "2026-09-29T10:00", person: "Ahmet", created: "2026-09-20T09:00"),
            makeItem(.waiting, "Numune", due: "2026-09-30T10:00", person: "Ahmet", created: "2026-09-21T09:00"),
            makeItem(.waiting, "Fatura", due: "2026-09-28T10:00", person: "Ahmet Bey", created: "2026-09-22T09:00"),
            makeItem(.waiting, "Onay", due: "2026-09-29T10:00", person: "Ayşe", created: "2026-09-22T09:00"),
            makeItem(.waiting, "Çizim", due: "2026-09-30T10:00", person: "Ayşe Hanım", created: "2026-09-23T09:00"),
            makeItem(.waiting, "Kablo", due: "2026-09-30T10:00", person: "Ahmet Ak", created: "2026-09-23T09:00")
        ]
        let board = PeopleBoard.build(items: items, now: now, calendar: calendar)
        XCTAssertEqual(board.map { $0.key }, ["ahmet", "ayse", "ahmet ak"])
        let ahmet = board.first { $0.key == "ahmet" }
        XCTAssertEqual(ahmet?.displayName, "Ahmet Bey", "the fuller spelling wins for the greeting")
        XCTAssertEqual(ahmet?.followUps.map { $0.title }, ["Fatura", "Teklif", "Numune"])
        let ayse = board.first { $0.key == "ayse" }
        XCTAssertEqual(ayse?.displayName, "Ayşe Hanım")
        XCTAssertEqual(ayse?.followUps.count, 2)
        XCTAssertEqual(board.first { $0.key == "ahmet ak" }?.followUps.count, 1)
    }

    // MARK: - Mentions

    func testMentionNeedsTheWholeNameNotItsStrippedForm() {
        let items = [
            makeItem(.task, "Teklif fiyatından emin ol", created: "2026-09-26T09:00"),
            makeItem(.task, "Gül Hanım'ı ara", created: "2026-09-26T09:30"),
            makeItem(.task, "Emine'ye numuneyi ver", created: "2026-09-26T10:00"),
            makeItem(.waiting, "Rapor", due: "2026-09-29T10:00", person: "Emine"),
            makeItem(.waiting, "Sipariş", due: "2026-09-29T10:00", person: "Gülten")
        ]
        let emine = PeopleBoard.summary(forKey: "emine", items: items, now: now, calendar: calendar)
        XCTAssertEqual(emine?.openItems.map { $0.title }, ["Emine'ye numuneyi ver"])
        let gulten = PeopleBoard.summary(forKey: "gulten", items: items, now: now, calendar: calendar)
        XCTAssertEqual(gulten?.openItems.count, 0)

        let ayse = [
            makeItem(.task, "Ayşe'ye çizimi gönder", created: "2026-09-26T09:00"),
            makeItem(.task, "Ayşeye numuneyi ver", created: "2026-09-26T10:00"),
            makeItem(.task, "Ayşe ile toplantı", created: "2026-09-26T11:00"),
            makeItem(.waiting, "Onay", due: "2026-09-29T10:00", person: "Ayşe")
        ]
        let summary = PeopleBoard.summary(forKey: "ayse", items: ayse, now: now, calendar: calendar)
        XCTAssertEqual(summary?.openItems.map { $0.title },
                       ["Ayşe'ye çizimi gönder", "Ayşeye numuneyi ver", "Ayşe ile toplantı"])
    }

    // MARK: - Follow-ups, open items, history

    func testFollowUpsOldestFirstWithOverdueCount() {
        let summary = PeopleBoard.summary(forKey: "ahmet", items: fixture(), now: now, calendar: calendar)
        XCTAssertEqual(summary?.followUps.map { $0.title }, ["I/O listesi", "Numune", "Fiyat teklifi"])
        XCTAssertEqual(summary?.overdueFollowUps, 1)
        XCTAssertEqual(summary?.lastActivity, TestSupport.date("2026-09-27T08:00"))
    }

    func testTitleMentionCountsAsOpenWork() {
        let items = fixture()
        let ahmet = PeopleBoard.summary(forKey: "ahmet", items: items, now: now, calendar: calendar)
        XCTAssertEqual(ahmet?.openItems.map { $0.title }, ["Ahmet'e teklifi gönder"])
        let mehmet = PeopleBoard.summary(forKey: "mehmet", items: items, now: now, calendar: calendar)
        XCTAssertEqual(mehmet?.openItems.map { $0.title }, ["Mehmet ile görüş"])

        // Honorifics and words shorter than 3 characters are not required in the title.
        var more = items
        more.append(makeItem(.task, "Rapor", person: "Ahmet Bey", created: "2026-09-26T10:00"))
        more.append(makeItem(.task, "Kablo", person: "Ahmet Ak", created: "2026-09-26T10:00"))
        // "Ahmet Bey" is the same person as "Ahmet": an old "ahmet bey" route resolves to the merged summary.
        let bey = PeopleBoard.summary(forKey: "ahmet bey", items: more, now: now, calendar: calendar)
        XCTAssertEqual(bey?.key, "ahmet")
        XCTAssertEqual(bey?.openItems.map { $0.title }, ["Ahmet'e teklifi gönder", "Rapor"])
        XCTAssertEqual(bey?.followUps.count, 3)
        let ak = PeopleBoard.summary(forKey: "ahmet ak", items: more, now: now, calendar: calendar)
        XCTAssertEqual(ak?.openItems.map { $0.title }, ["Ahmet'e teklifi gönder", "Kablo"])

        // A name made only of an honorific never matches titles.
        more.append(makeItem(.task, "Şef'e sor", created: "2026-09-26T11:00"))
        more.append(makeItem(.waiting, "Onay", due: "2026-09-29T10:00", person: "Şef"))
        let sef = PeopleBoard.summary(forKey: "sef", items: more, now: now, calendar: calendar)
        XCTAssertEqual(sef?.openItems.count, 0)
        XCTAssertEqual(sef?.followUps.count, 1)

        // Unsuffixed and suffixed forms of a name that ends in a case-suffix letter.
        let ayse = [
            makeItem(.task, "Ayşeye numuneyi ver", created: "2026-09-26T09:00"),
            makeItem(.task, "Ayşe ile toplantı", created: "2026-09-26T10:00"),
            makeItem(.task, "Ayşenur'u ara", created: "2026-09-26T11:00"),
            makeItem(.task, "Bütçe", person: "Ayşe", created: "2026-09-26T12:00")
        ]
        let summary = PeopleBoard.summary(forKey: "ayse", items: ayse, now: now, calendar: calendar)
        XCTAssertEqual(summary?.openItems.map { $0.title }, ["Ayşeye numuneyi ver", "Ayşe ile toplantı", "Bütçe"])
    }

    func testRecentDoneIsCappedAndNewestFirst() {
        var items: [Item] = []
        for day in 20...25 {
            items.append(done("İş " + String(day), person: "Ahmet", completed: "2026-09-" + String(day) + "T10:00"))
        }
        items.append(done("Çok eski", person: "Ahmet", completed: "2026-07-01T10:00"))
        let summary = PeopleBoard.summary(forKey: "ahmet", items: items, now: now, calendar: calendar)
        XCTAssertEqual(summary?.recentDone.map { $0.title }, ["İş 25", "İş 24", "İş 23", "İş 22", "İş 21"])
    }

    func testDeletedItemsDoNotCarryAPerson() {
        var item = makeItem(.waiting, "Silinen", due: "2026-09-29T10:00", person: "Selin")
        item.status = .deleted
        XCTAssertNil(PeopleBoard.summary(forKey: "selin", items: [item], now: now, calendar: calendar))
        XCTAssertTrue(PeopleBoard.build(items: [item], now: now, calendar: calendar).isEmpty)
        XCTAssertNil(PeopleBoard.summary(forKey: "", items: fixture(), now: now, calendar: calendar))
    }

    // MARK: - Board filter and order

    func testInactivePeopleAreDroppedAndOrderIsStable() {
        let board = PeopleBoard.build(items: fixture(), now: now, calendar: calendar)
        XCTAssertEqual(board.map { $0.key }, ["ahmet", "veli", "mehmet", "ayse", "yakin"])
        XCTAssertNotNil(PeopleBoard.summary(forKey: "eski firma", items: fixture(), now: now, calendar: calendar))
    }

    // MARK: - Message

    func testReminderMessageForZeroOneAndThreeFollowUps() {
        let items = fixture()
        let mehmet = PeopleBoard.summary(forKey: "mehmet", items: items, now: now, calendar: calendar)
        let veli = PeopleBoard.summary(forKey: "veli", items: items, now: now, calendar: calendar)
        let ahmet = PeopleBoard.summary(forKey: "ahmet", items: items, now: now, calendar: calendar)
        guard let mehmetSummary = mehmet, let veliSummary = veli, let ahmetSummary = ahmet else {
            XCTFail("fixture")
            return
        }
        XCTAssertEqual(PeopleBoard.reminderMessage(for: mehmetSummary, greetingName: "Mehmet", userName: "Gökhan",
                                                   now: now, calendar: calendar), "")
        XCTAssertEqual(PeopleBoard.reminderMessage(for: veliSummary, greetingName: "Veli Bey", userName: " Gökhan ",
                                                   now: now, calendar: calendar),
                       "Merhaba Veli Bey, Kalibrasyon raporu konusunda son durum nedir? Teşekkürler.\nGökhan")
        XCTAssertEqual(PeopleBoard.reminderMessage(for: veliSummary, greetingName: nil, userName: "",
                                                   now: now, calendar: calendar),
                       "Merhaba, Kalibrasyon raporu konusunda son durum nedir? Teşekkürler.")
        let expected: String = "Merhaba,\n"
            + "Aşağıdaki konularda son durumu paylaşabilir misiniz?\n"
            + "• I/O listesi (7 gündür bekliyorum)\n"
            + "• Numune\n"
            + "• Fiyat teklifi (2 gündür bekliyorum)\n"
            + "Teşekkürler."
        XCTAssertEqual(PeopleBoard.reminderMessage(for: ahmetSummary, greetingName: "  ", userName: "",
                                                   now: now, calendar: calendar), expected)
        let body: String = String(expected.dropFirst("Merhaba,\n".count))
        let named: String = "Merhaba Ahmet Bey,\n" + body + "\nGökhan"
        XCTAssertEqual(PeopleBoard.reminderMessage(for: ahmetSummary, greetingName: "Ahmet Bey", userName: "Gökhan",
                                                   now: now, calendar: calendar), named)
    }
}
