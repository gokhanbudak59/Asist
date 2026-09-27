import Foundation
import XCTest
@testable import AsistCore

/// 04 §3.5.6 rules R1–R12: D20/D21/D33 defaults, event detection (D31), confirmation levels (D10), alternatives.
/// Reference instant: Sun 2026-09-27 10:30 (Europe/Istanbul) unless stated.
final class ItemFactoryTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let now = TestSupport.date("2026-09-27T10:30")

    private func parsed(_ kind: ItemKind, _ title: String, due: String? = nil, hasTime: Bool = true,
                        priority: Priority = .normal, project: String? = nil, place: PlaceRef? = nil,
                        leads: [Int] = [], body: String? = nil) -> ParsedItem {
        ParsedItem(kind: kind, title: title, body: body, dueDate: due.map { TestSupport.date($0) },
                   hasTime: due != nil && hasTime, priority: priority, project: project, place: place,
                   leadTimesMinutes: leads)
    }

    private func result(_ item: ParsedItem, confidence: Double = 0.9, flags: Set<ParseFlag> = [],
                        text: String = "cümle") -> ParseResult {
        let kind = ParsedKind(rawValue: item.kind.rawValue) ?? .task
        return ParseResult(kind: kind, item: item, command: nil, confidence: confidence, flags: flags,
                           understood: item.title, relativePhrase: nil, originalText: text, normalizedText: text)
    }

    private func context(interactive: Bool = true, settings: AppSettings = AppSettings(), projects: [Project] = [],
                         forcedKind: ItemKind? = nil, forcedProjectID: UUID? = nil) -> CaptureContext {
        CaptureContext(settings: settings, projects: projects, places: [], forcedKind: forcedKind,
                       forcedProjectID: forcedProjectID, interactive: interactive)
    }

    private func propose(_ result: ParseResult, source: CaptureSource = .voice, context ctx: CaptureContext? = nil,
                         at instant: Date? = nil) -> CaptureProposal? {
        ItemFactory.proposal(from: result, source: source, context: ctx ?? context(), now: instant ?? now,
                             calendar: calendar)
    }

    // MARK: - Basics

    func testCommandHasNoProposal() {
        let command = ParseResult(kind: .command, item: nil, command: ParsedCommand(type: .query, scope: .today),
                                  confidence: 1, flags: [], understood: "Bugünün ajandası", relativePhrase: nil,
                                  originalText: "bugün ne var", normalizedText: "bugün ne var")
        XCTAssertNil(propose(command))
    }

    func testCopiesParsedFields() throws {
        let item = parsed(.reminder, "Teklif konusu", due: "2026-09-29T15:00", priority: .high, leads: [30, 30, -5, 10])
        var parsedItem = item
        parsedItem.person = "  Ahmet "
        parsedItem.tags = ["fikir"]
        let proposal = try XCTUnwrap(propose(result(parsedItem, confidence: 0.92,
                                                    text: "Salı günü teklif konusunu bana saat 3'te hatırlat")))
        XCTAssertEqual(proposal.item.kind, .reminder)
        XCTAssertEqual(proposal.item.title, "Teklif konusu")
        XCTAssertEqual(proposal.item.dueDate, TestSupport.date("2026-09-29T15:00"))
        XCTAssertTrue(proposal.item.hasTime)
        XCTAssertEqual(proposal.item.priority, .high)
        XCTAssertEqual(proposal.item.person, "Ahmet")
        XCTAssertEqual(proposal.item.tags, ["fikir"])
        XCTAssertEqual(proposal.item.leadTimesMinutes, [10, 30])
        XCTAssertEqual(proposal.item.originalText, "Salı günü teklif konusunu bana saat 3'te hatırlat")
        XCTAssertEqual(proposal.item.parseConfidence, 0.92)
        XCTAssertEqual(proposal.item.source, .voice)
        XCTAssertEqual(proposal.item.createdAt, now)
        XCTAssertEqual(proposal.item.history.count, 1)
        XCTAssertEqual(proposal.item.history.first?.event, .created)
        XCTAssertEqual(proposal.level, .autoSave)
        XCTAssertFalse(proposal.needsTime)
        XCTAssertFalse(proposal.appliedDefaultTime)
        XCTAssertFalse(proposal.defaultedToToday)
        XCTAssertFalse(proposal.item.needsReview)
    }

    func testEmptyTitleGetsKindLabel() throws {
        let proposal = try XCTUnwrap(propose(result(parsed(.reminder, "  ", due: "2026-09-27T10:35"), confidence: 0.4)))
        XCTAssertEqual(proposal.item.title, "Hatırlatma")
        XCTAssertEqual(proposal.level, .review)
    }

    // MARK: - R1 fallback (D33)

    func testNoteFallbackBecomesTask() throws {
        let note = parsed(.note, "Hat 3 sensör kablosu değişecek", body: "Hat 3 sensör kablosu değişecek")
        let interactive = try XCTUnwrap(propose(result(note, confidence: 0.85, flags: [.noKindCue])))
        XCTAssertEqual(interactive.item.kind, .task)
        XCTAssertEqual(interactive.level, .confirm)
        XCTAssertFalse(interactive.item.needsReview)
        XCTAssertTrue(interactive.defaultedToToday)
        XCTAssertEqual(interactive.item.notes, "")

        let headless = try XCTUnwrap(propose(result(note, confidence: 0.85, flags: [.noKindCue]), source: .siri,
                                             context: context(interactive: false)))
        XCTAssertEqual(headless.item.kind, .task)
        XCTAssertTrue(headless.item.needsReview)
    }

    func testRealNoteStaysNoteWithoutSchedule() throws {
        let note = parsed(.note, "Işık perdesi mesafesi tekrar ölçülecek", body: "ışık perdesi mesafesi tekrar ölçülecek")
        let proposal = try XCTUnwrap(propose(result(note, confidence: 1.0)))
        XCTAssertEqual(proposal.item.kind, .note)
        XCTAssertNil(proposal.item.dueDate)
        XCTAssertEqual(proposal.item.notes, "ışık perdesi mesafesi tekrar ölçülecek")
        XCTAssertFalse(proposal.defaultedToToday)
    }

    func testForcedNoteKeepsVerbatimText() throws {
        let reminder = parsed(.reminder, "Toplantı", due: "2026-09-28T15:00")
        let proposal = try XCTUnwrap(propose(result(reminder, text: "yarın 3'te toplantı var"),
                                             context: context(forcedKind: .note)))
        XCTAssertEqual(proposal.item.kind, .note)
        XCTAssertNil(proposal.item.dueDate)
        XCTAssertFalse(proposal.item.hasTime)
        XCTAssertEqual(proposal.item.notes, "yarın 3'te toplantı var")
        XCTAssertEqual(proposal.item.title, "Yarın 3'te toplantı var")
    }

    // MARK: - R5/R6 (D20, P4)

    func testUrgentTaskWithoutDateAsksWhenInteractive() throws {
        let task = parsed(.task, "Pano ısınma problemini Hakan'la konuş", priority: .critical)
        let proposal = try XCTUnwrap(propose(result(task, confidence: 0.9)))
        XCTAssertEqual(proposal.item.kind, .reminder)
        XCTAssertTrue(proposal.needsTime)
        XCTAssertEqual(proposal.level, .review)
        XCTAssertNil(proposal.item.dueDate)
        XCTAssertFalse(proposal.item.needsReview)
    }

    func testReminderWithoutTimeHeadlessGetsOneHour() throws {
        let reminder = parsed(.reminder, "Hakan'ı ara")
        let proposal = try XCTUnwrap(propose(result(reminder, confidence: 0.85), source: .siri,
                                             context: context(interactive: false)))
        XCTAssertEqual(proposal.item.dueDate, TestSupport.date("2026-09-27T11:30"))
        XCTAssertTrue(proposal.item.hasTime)
        XCTAssertTrue(proposal.appliedDefaultTime)
        XCTAssertFalse(proposal.needsTime)
    }

    func testReminderWithoutTimeInteractiveWithEveningSetting() throws {
        var settings = AppSettings()
        settings.noTimeBehavior = .thisEvening
        let proposal = try XCTUnwrap(propose(result(parsed(.reminder, "İlacımı iç")),
                                             context: context(settings: settings)))
        XCTAssertEqual(proposal.item.dueDate, TestSupport.date("2026-09-27T19:00"))
        XCTAssertTrue(proposal.appliedDefaultTime)
        XCTAssertFalse(proposal.needsTime)
    }

    func testNoTimeDefault() {
        let settings = AppSettings()
        XCTAssertEqual(ItemFactory.noTimeDefault(.inOneHour, now: now, settings: settings, calendar: calendar),
                       TestSupport.date("2026-09-27T11:30"))
        XCTAssertEqual(ItemFactory.noTimeDefault(.ask, now: now.addingTimeInterval(20), settings: settings, calendar: calendar),
                       TestSupport.date("2026-09-27T11:31"))
        XCTAssertEqual(ItemFactory.noTimeDefault(.thisEvening, now: now, settings: settings, calendar: calendar),
                       TestSupport.date("2026-09-27T19:00"))
        let late = TestSupport.date("2026-09-27T20:00")
        XCTAssertEqual(ItemFactory.noTimeDefault(.thisEvening, now: late, settings: settings, calendar: calendar),
                       TestSupport.date("2026-09-27T21:00"))
    }

    // MARK: - R7 today policy (D33)

    func testUndatedTaskGoesToToday() throws {
        let task = parsed(.task, "Sipariş formunu doldur")
        let proposal = try XCTUnwrap(propose(result(task)))
        XCTAssertEqual(proposal.item.dueDate, TestSupport.date("2026-09-27T11:00"))
        XCTAssertFalse(proposal.item.hasTime)
        XCTAssertTrue(proposal.defaultedToToday)
        XCTAssertFalse(proposal.appliedDefaultTime)
    }

    func testTodayPolicyTable() {
        let settings = AppSettings()
        func policy(_ s: String) -> String {
            TestSupport.format(ItemFactory.todayPolicy(now: TestSupport.date(s), settings: settings, calendar: calendar))
        }
        XCTAssertEqual(policy("2026-09-28T07:00"), "2026-09-28T09:00")   // default time still ahead
        XCTAssertEqual(policy("2026-09-28T08:50"), "2026-09-28T10:00")   // 09:00 < now + 15 → 09:20 ↑ 10:00
        XCTAssertEqual(policy("2026-09-27T10:30"), "2026-09-27T11:00")
        XCTAssertEqual(policy("2026-09-27T10:31"), "2026-09-27T12:00")
        XCTAssertEqual(policy("2026-09-28T17:50"), "2026-09-28T19:00")
        XCTAssertEqual(policy("2026-09-28T18:00"), "2026-09-29T09:00")   // at/after workEnd → tomorrow
        XCTAssertEqual(policy("2026-09-28T23:40"), "2026-09-29T09:00")
    }

    func testUndatedTaskFromOtherSourcesStaysUnscheduled() throws {
        let proposal = try XCTUnwrap(propose(result(parsed(.task, "Kalibrasyon")), source: .importFile))
        XCTAssertNil(proposal.item.dueDate)
        XCTAssertFalse(proposal.defaultedToToday)
    }

    // MARK: - R8 waiting (D21)

    func testWaitingWithoutDateGetsTwoWorkdays() throws {
        let waiting = parsed(.waiting, "I/O listesi")
        let proposal = try XCTUnwrap(propose(result(waiting)))
        XCTAssertEqual(proposal.item.dueDate, TestSupport.date("2026-09-29T10:00"))
        XCTAssertFalse(proposal.item.hasTime)
        XCTAssertTrue(proposal.appliedDefaultTime)
    }

    func testDefaultWaitingDueSkipsWeekend() {
        let friday = TestSupport.date("2026-10-02T15:00")
        XCTAssertEqual(ItemFactory.defaultWaitingDue(now: friday, settings: AppSettings(), calendar: calendar),
                       TestSupport.date("2026-10-06T10:00"))
    }

    func testWaitingWithSpokenDayIsAskedAtFollowUpTime() throws {
        let waiting = parsed(.waiting, "Devreye alma raporu", due: "2026-10-02T09:00", hasTime: false)
        let proposal = try XCTUnwrap(propose(result(waiting)))
        XCTAssertEqual(proposal.item.dueDate, TestSupport.date("2026-10-02T16:00"))
        XCTAssertTrue(proposal.item.hasTime)
        XCTAssertFalse(proposal.appliedDefaultTime)
    }

    // MARK: - R9 events (D31)

    func testEventDetection() throws {
        let meeting = parsed(.reminder, "ABB ile toplantı", due: "2026-10-01T14:00")
        let proposal = try XCTUnwrap(propose(result(meeting)))
        XCTAssertTrue(proposal.item.isEvent)
        XCTAssertEqual(proposal.item.kind, .reminder)
        XCTAssertEqual(proposal.item.leadTimesMinutes, [15])

        let spokenLead = parsed(.task, "Müşteri ziyareti", due: "2026-10-01T14:00", leads: [30])
        let withLead = try XCTUnwrap(propose(result(spokenLead)))
        XCTAssertTrue(withLead.item.isEvent)
        XCTAssertEqual(withLead.item.kind, .reminder)
        XCTAssertEqual(withLead.item.leadTimesMinutes, [30])

        let untimed = parsed(.reminder, "ABB ile toplantı", due: "2026-10-01T09:00", hasTime: false)
        XCTAssertFalse(try XCTUnwrap(propose(result(untimed))).item.isEvent)

        let notEvent = parsed(.task, "Toplantı notlarını gönder", due: "2026-10-01T14:00")
        XCTAssertFalse(try XCTUnwrap(propose(result(notEvent))).item.isEvent)
    }

    func testIsEventTitle() {
        XCTAssertTrue(ItemFactory.isEventTitle("ABB ile toplantı var"))
        XCTAssertTrue(ItemFactory.isEventTitle("ABB toplantısı"))
        XCTAssertTrue(ItemFactory.isEventTitle("Randevu var mı"))
        XCTAssertTrue(ItemFactory.isEventTitle("Tedarikçiyle yemek"))
        XCTAssertTrue(ItemFactory.isEventTitle("Kocaeli FAT"))
        XCTAssertTrue(ItemFactory.isEventTitle("Arka Cep SAT'ı"))
        XCTAssertTrue(ItemFactory.isEventTitle("Performans görüşmesi olacak"))
        XCTAssertFalse(ItemFactory.isEventTitle("toplantı notlarını gönder"))
        XCTAssertFalse(ItemFactory.isEventTitle("Eski arabayı sat"))
        XCTAssertFalse(ItemFactory.isEventTitle(""))
        XCTAssertFalse(ItemFactory.isEventTitle("var"))
    }

    // MARK: - R2 / R3

    func testProjectMatchedByAliasElseForced() throws {
        let project = Project(name: "Arka Cep", aliases: ["Kocaeli"], createdAt: TestSupport.date("2026-09-01T09:00"))
        let other = Project(name: "Bakım", createdAt: TestSupport.date("2026-09-01T09:00"))
        let ctx = context(projects: [project, other], forcedProjectID: other.id)

        let named = parsed(.task, "Robot hücresi", due: "2026-09-28T09:00", project: "kocaeli")
        XCTAssertEqual(try XCTUnwrap(propose(result(named), context: ctx)).item.projectID, project.id)

        let unnamed = parsed(.task, "Robot hücresi", due: "2026-09-28T09:00")
        XCTAssertEqual(try XCTUnwrap(propose(result(unnamed), context: ctx)).item.projectID, other.id)

        let unknown = parsed(.task, "Robot hücresi", due: "2026-09-28T09:00", project: "Yeni Hat")
        XCTAssertNil(try XCTUnwrap(propose(result(unknown), context: context(projects: [project]))).item.projectID)
    }

    func testPlaceBecomesNotesLine() throws {
        let place = PlaceRef(name: "Fabrika", trigger: .onArrive)
        let item = parsed(.reminder, "Yedek parça listesini sor", due: "2026-09-28T09:00", place: place)
        let proposal = try XCTUnwrap(propose(result(item)))
        XCTAssertEqual(proposal.item.notes, "Yer: Fabrika (varınca)")
        XCTAssertNil(proposal.item.placeID)
        XCTAssertNil(proposal.item.placeTrigger)
    }

    // MARK: - R11 levels (D10) and R12

    func testLevels() {
        let item = parsed(.reminder, "X", due: "2026-09-28T09:00")
        XCTAssertEqual(ItemFactory.level(for: result(item, confidence: 0.80)), .autoSave)
        XCTAssertEqual(ItemFactory.level(for: result(item, confidence: 0.79)), .confirm)
        XCTAssertEqual(ItemFactory.level(for: result(item, confidence: 0.60)), .confirm)
        XCTAssertEqual(ItemFactory.level(for: result(item, confidence: 0.59)), .review)
        XCTAssertEqual(ItemFactory.level(for: result(item, confidence: 0.95, flags: [.pastDue])), .review)
        XCTAssertEqual(ItemFactory.level(for: result(item, confidence: 0.95, flags: [.conflictingDates])), .review)
        XCTAssertEqual(ItemFactory.level(for: result(item, confidence: 0.95, flags: [.needsTime])), .review)
        XCTAssertEqual(ItemFactory.level(for: result(item, confidence: 0.95, flags: [.nextWeekAmbiguous])), .confirm)
    }

    func testHeadlessReviewMarksNeedsReview() throws {
        let item = parsed(.reminder, "Belirsiz bir şey", due: "2026-09-28T09:00")
        let headless = try XCTUnwrap(propose(result(item, confidence: 0.5), source: .siri,
                                             context: context(interactive: false)))
        XCTAssertTrue(headless.item.needsReview)
        let interactive = try XCTUnwrap(propose(result(item, confidence: 0.5)))
        XCTAssertFalse(interactive.item.needsReview)
    }

    // MARK: - R10 alternatives

    func testNextWeekAmbiguousOffersPlusSevenDays() throws {
        let item = parsed(.reminder, "Teklif konusu", due: "2026-09-29T15:00")
        let proposal = try XCTUnwrap(propose(result(item, confidence: 0.79, flags: [.nextWeekAmbiguous])))
        XCTAssertEqual(proposal.alternativeTimes, [TestSupport.date("2026-10-06T15:00")])
        XCTAssertEqual(proposal.level, .confirm)
    }

    func testAmbiguousHourOffersOtherReading() throws {
        let evening = parsed(.reminder, "Sunucu yedeğine bak", due: "2026-09-27T21:00")
        let first = try XCTUnwrap(propose(result(evening, confidence: 0.7, flags: [.ambiguousHourNearest])))
        XCTAssertEqual(first.alternativeTimes, [TestSupport.date("2026-09-28T09:00")])

        let afternoon = parsed(.reminder, "Ali'yi ara", due: "2026-09-27T15:00")
        let second = try XCTUnwrap(propose(result(afternoon, confidence: 0.7, flags: [.ambiguousHourNearest])))
        XCTAssertEqual(second.alternativeTimes, [TestSupport.date("2026-09-28T03:00")])
    }

    func testBareWeekdayEqualToTodayOffersToday() throws {
        let item = parsed(.reminder, "Ali'yi ara", due: "2026-10-04T15:00")
        let proposal = try XCTUnwrap(propose(result(item, text: "pazar 3'te Ali'yi ara")))
        XCTAssertEqual(proposal.alternativeTimes, [TestSupport.date("2026-09-27T15:00")])

        let explicitNextWeek = try XCTUnwrap(propose(result(item, text: "haftaya pazar 3'te Ali'yi ara")))
        XCTAssertEqual(explicitNextWeek.alternativeTimes, [])
    }

    // MARK: - Checklist templates (03 Ek A)

    func testChecklistTemplates() throws {
        let ids = ChecklistTemplates.all.map { $0.id }
        XCTAssertEqual(ids, ["fat", "sat", "devreye_alma", "saha_ziyareti", "toplanti"])
        let fat = try XCTUnwrap(ChecklistTemplates.template(id: "fat"))
        XCTAssertEqual(fat.name, "FAT (Fabrika Kabul Testi)")
        XCTAssertEqual(fat.entries.count, 7)
        XCTAssertEqual(fat.entries.first, "Test prosedürü müşteriye gönderildi ve onaylandı")
        let first = ChecklistTemplates.entries(for: fat)
        let second = ChecklistTemplates.entries(for: fat)
        XCTAssertEqual(first.map { $0.text }, fat.entries)
        XCTAssertTrue(first.allSatisfy { !$0.done })
        XCTAssertNotEqual(first[0].id, second[0].id)
        XCTAssertEqual(ChecklistTemplates.template(id: "toplanti")?.entries.last, "Toplantı sonrası aksiyonlar Asist'e kaydedildi")
        XCTAssertNil(ChecklistTemplates.template(id: "yok"))
    }
}
