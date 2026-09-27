import Foundation
import XCTest
@testable import AsistCore

/// 03 §5.8 rows 24–26, 03 §5.10 decision table, 02 §10.6 query texts, G5 ("geldi" prefers waiting items).
final class FuzzyMatcherTests: XCTestCase {
    private let calendar = TestSupport.calendar

    private func makeItem(_ kind: ItemKind, _ title: String, due: String? = nil, person: String? = nil,
                          projectID: UUID? = nil, original: String? = nil) -> Item {
        Item(kind: kind, title: title, originalText: original, dueDate: due.map { TestSupport.date($0) },
             hasTime: due != nil, person: person, projectID: projectID,
             createdAt: TestSupport.date("2026-09-27T10:30"))
    }

    private var teklif: Item {
        makeItem(.reminder, "Teklif konusu", due: "2026-09-29T15:00",
                 original: "Salı günü teklif konusunu bana saat 3'te hatırlat")
    }
    private var ahmet: Item {
        makeItem(.reminder, "Ahmet'i ara", due: "2026-09-28T09:00", person: "Ahmet",
                 original: "Yarın sabah Ahmet'i aramayı hatırlat")
    }
    private var rapor: Item {
        makeItem(.reminder, "Haftalık rapor", due: "2026-09-28T09:00")
    }

    private func decide(_ query: String?, items: [Item], person: String? = nil, project: String? = nil,
                        date: Date? = nil, preferWaiting: Bool = false, projects: [Project] = []) -> MatchDecision {
        let ranked = FuzzyMatcher.rank(query: query, person: person, project: project, date: date,
                                       preferWaiting: preferWaiting, items: items, projects: projects,
                                       calendar: calendar)
        return FuzzyMatcher.decide(ranked)
    }

    // MARK: - Tokens

    func testTokensStripApostropheSuffixAndStopWords() {
        XCTAssertEqual(FuzzyMatcher.tokens("Ahmet'i arama hatırlatmasını"), ["ahmet", "aram"])
        XCTAssertEqual(FuzzyMatcher.tokens("teklif konusunu"), ["teklif", "konu"])
        XCTAssertEqual(FuzzyMatcher.tokens("Teklif konusu"), ["teklif", "konu"])
        XCTAssertEqual(FuzzyMatcher.tokens("Kalibrasyon işini"), ["kalibrasyon"])
        XCTAssertEqual(FuzzyMatcher.tokens("bunu"), [])
        XCTAssertEqual(FuzzyMatcher.tokens(""), [])
        let hat = FuzzyMatcher.tokens("Hat 3 yedeğini")
        XCTAssertEqual(hat.first, "hat")
        XCTAssertTrue(hat.contains("3"))
        // Short words keep their ending (no stem below 3 letters).
        XCTAssertEqual(FuzzyMatcher.tokens("ara"), ["ara"])
    }

    func testMatchQuality() {
        XCTAssertEqual(FuzzyMatcher.matchQuality("teklif", "teklif"), 1.0)
        XCTAssertEqual(FuzzyMatcher.matchQuality("teklif", "teklifi"), 0.9)
        XCTAssertEqual(FuzzyMatcher.matchQuality("ara", "aram"), 0.9)
        XCTAssertEqual(FuzzyMatcher.matchQuality("yedeg", "yedek"), 0.8)
        XCTAssertEqual(FuzzyMatcher.matchQuality("kontrol", "kontak"), 0)
        XCTAssertEqual(FuzzyMatcher.matchQuality("3", "30"), 0)
        XCTAssertEqual(FuzzyMatcher.matchQuality("al", "alarm"), 0)
    }

    // MARK: - 03 §5.8 rows 24–26

    func testRow24CompleteTeklifIsi() {
        let items = [teklif, ahmet, rapor]
        XCTAssertEqual(decide("teklif işi", items: items), .single(items[0].id))
    }

    func testRow25CancelAhmetArama() {
        let items = [teklif, ahmet, rapor]
        XCTAssertEqual(decide("ahmet arama", items: items), .single(items[1].id))
        XCTAssertEqual(decide("Ahmet'i", items: items), .single(items[1].id))
    }

    func testRow26SnoozeTeklif() {
        let items = [teklif, ahmet, rapor]
        XCTAssertEqual(decide("teklifi", items: items), .single(items[0].id))
    }

    func testScoreIsHighForGoodMatchAndZeroForUnrelated() {
        let item = teklif
        XCTAssertGreaterThanOrEqual(FuzzyMatcher.score(query: "teklif konusu", item: item, projectName: nil), 0.95)
        XCTAssertEqual(FuzzyMatcher.score(query: "fatura", item: item, projectName: nil), 0)
        XCTAssertEqual(FuzzyMatcher.score(query: "bunu", item: item, projectName: nil), 0)
    }

    // MARK: - Decisions

    func testAmbiguousWhenTwoItemsMatchEqually() {
        let revizyon = makeItem(.task, "Teklif revizyonu hazırla", due: "2026-09-30T10:00")
        let items = [teklif, revizyon, ahmet]
        guard case .ambiguous(let ids) = decide("teklif", items: items) else {
            return XCTFail("expected ambiguous")
        }
        XCTAssertEqual(Set(ids), Set([items[0].id, items[1].id]))
    }

    func testNoneWhenNothingMatches() {
        XCTAssertEqual(decide("fatura ödemesi", items: [teklif, ahmet, rapor]), MatchDecision.none)
        XCTAssertEqual(decide(nil, items: [teklif, ahmet]), MatchDecision.none)
        XCTAssertEqual(decide("", items: [teklif, ahmet]), MatchDecision.none)
    }

    func testClosedAndDeletedItemsAreIgnored() {
        var done = teklif
        done.status = .done
        var deleted = makeItem(.reminder, "Teklif konusu")
        deleted.status = .deleted
        XCTAssertEqual(decide("teklif", items: [done, deleted, ahmet]), MatchDecision.none)
    }

    func testDecideThresholds() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        XCTAssertEqual(FuzzyMatcher.decide([FuzzyMatch(itemID: a, score: 0.9), FuzzyMatch(itemID: b, score: 0.3)]), .single(a))
        XCTAssertEqual(FuzzyMatcher.decide([FuzzyMatch(itemID: b, score: 0.5), FuzzyMatch(itemID: a, score: 0.95)]), .single(a))
        XCTAssertEqual(FuzzyMatcher.decide([FuzzyMatch(itemID: a, score: 0.7), FuzzyMatch(itemID: b, score: 0.6)]),
                       .ambiguous([a, b]))
        XCTAssertEqual(FuzzyMatcher.decide([FuzzyMatch(itemID: a, score: 0.55)]), MatchDecision.none)
        XCTAssertEqual(FuzzyMatcher.decide([]), MatchDecision.none)
        let many = [FuzzyMatch(itemID: a, score: 0.5), FuzzyMatch(itemID: b, score: 0.45),
                    FuzzyMatch(itemID: c, score: 0.42), FuzzyMatch(itemID: UUID(), score: 0.41)]
        guard case .ambiguous(let ids) = FuzzyMatcher.decide(many) else {
            return XCTFail("expected ambiguous")
        }
        XCTAssertEqual(ids, [a, b, c])
    }

    // MARK: - Filters and G5

    func testPreferWaitingAddsBonus() {
        let waiting = makeItem(.waiting, "Çizim ve şablon listesi", due: "2026-09-29T10:00", person: "Mehmet")
        let plain = FuzzyMatcher.rank(query: "çizim föyü", person: nil, project: nil, date: nil, preferWaiting: false,
                                      items: [waiting], projects: [], calendar: calendar)
        let preferred = FuzzyMatcher.rank(query: "çizim föyü", person: nil, project: nil, date: nil, preferWaiting: true,
                                          items: [waiting], projects: [], calendar: calendar)
        XCTAssertEqual(plain.count, 1)
        XCTAssertEqual(preferred.count, 1)
        XCTAssertEqual(preferred[0].score - plain[0].score, 0.15, accuracy: 0.0001)
    }

    func testGeldiMatchesWaitingItemWithPerson() {
        let waiting = makeItem(.waiting, "Çizimler", due: "2026-10-02T16:00", person: "Mehmet")
        let other = makeItem(.reminder, "Çizim şablonunu güncelle", due: "2026-09-29T10:00")
        let items = [other, waiting]
        XCTAssertEqual(decide("mehmet çizimler", items: items, person: "Mehmet", preferWaiting: true),
                       .single(waiting.id))
    }

    func testDateFilterNarrowsToThatDay() {
        let friday = makeItem(.reminder, "Toplantı", due: "2026-10-02T10:00")
        let monday = makeItem(.reminder, "Toplantı", due: "2026-10-05T10:00")
        let items = [friday, monday]
        XCTAssertEqual(decide("toplantıyı", items: items, date: TestSupport.date("2026-10-02T00:00")), .single(friday.id))
        guard case .ambiguous = decide("toplantı", items: items) else {
            return XCTFail("expected ambiguous without a date filter")
        }
        XCTAssertEqual(decide("toplantı", items: items, date: TestSupport.date("2026-10-03T00:00")), MatchDecision.none)
    }

    func testProjectFilterUsesAliases() {
        let project = Project(name: "Arka Cep", aliases: ["Kocaeli"], createdAt: TestSupport.date("2026-09-01T09:00"))
        let inProject = makeItem(.task, "Devreye alma raporu", due: "2026-09-30T09:00", projectID: project.id)
        let elsewhere = makeItem(.task, "Haftalık rapor", due: "2026-09-30T09:00")
        let items = [inProject, elsewhere]
        XCTAssertEqual(decide("rapor", items: items, project: "kocaeli", projects: [project]), .single(inProject.id))
    }

    func testFilterOnlyCommandPointsAtSingleItem() {
        let items = [teklif, ahmet, rapor]
        XCTAssertEqual(decide(nil, items: items, person: "Ahmet"), .single(items[1].id))
        XCTAssertEqual(decide("bunu", items: items, person: "Ahmet Bey"), .single(items[1].id))
    }
}
