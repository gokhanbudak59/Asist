// LocationPlanningTests.swift — revision 4, F6 (07 §9.3, §9.4, §13): the nag planner with place-only items
// (anchor = locationFiredAt) and the capture factory's place rule R3 (configured place → placeID/placeTrigger,
// no time defaults). Reference week: Mon 2026-09-28 is a workday (default settings: 08:30–18:00, Nazik for normal).
import Foundation
import XCTest
@testable import AsistCore

final class LocationPlanningTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let created = TestSupport.date("2026-09-20T09:00")

    // MARK: - Helpers

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-4000-8000-" + AsistCalendar.pad(n, 12))!
    }

    private var fabrika: Place {
        Place(id: uuid(900), name: "Fabrika", aliases: ["saha"], latitude: 40.7806, longitude: 29.9420,
              radiusMeters: 200, createdAt: created)
    }

    private var emptyFabrika: Place {
        Place(id: uuid(901), name: "Fabrika", latitude: 0, longitude: 0, radiusMeters: 150, createdAt: created)
    }

    private func placeOnlyItem(_ n: Int, kind: ItemKind = .reminder, priority: Priority = .normal) -> Item {
        var item = Item(id: uuid(n), kind: kind, title: "Pano kontrolü", createdAt: created)
        item.priority = priority
        item.placeID = fabrika.id
        item.placeTrigger = .onArrive
        return item
    }

    private func plan(_ items: [Item], now: String, locationSlotsUsed: Int = 0) -> PlanResult {
        let input = PlanInput(items: items, projects: [], places: [fabrika], settings: AppSettings(),
                              now: TestSupport.date(now), calendar: calendar, signingExpiry: nil,
                              locationSlotsUsed: locationSlotsUsed)
        return NagPlanner.plan(input)
    }

    /// Item notifications (sentinels excluded), chronological.
    private func itemNotifications(_ result: PlanResult, _ id: UUID) -> [PlannedNotification] {
        let mine = result.notifications.filter { $0.itemID == id && $0.kind != .sentinel }
        return mine.sorted { (lhs: PlannedNotification, rhs: PlannedNotification) -> Bool in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Planner (07 §9.3)

    func testUnfiredPlaceOnlyItemPlansNothing() {
        let item = placeOnlyItem(1)
        XCTAssertNil(item.anchorDate)
        let result = plan([item], now: "2026-09-28T10:00")
        XCTAssertTrue(itemNotifications(result, item.id).isEmpty)
    }

    func testFiredPlaceOnlyItemNagsFromDeliveryTime() throws {
        var item = placeOnlyItem(1)
        let fired = TestSupport.date("2026-09-28T09:55")
        item.locationFiredAt = fired
        let now = TestSupport.date("2026-09-28T10:00")
        let result = plan([item], now: "2026-09-28T10:00")
        let mine = itemNotifications(result, item.id)
        let first = try XCTUnwrap(mine.first)
        XCTAssertEqual(first.id, NotificationID.chain(item.id, 1))
        XCTAssertEqual(first.kind, .nag)
        XCTAssertEqual(first.attempt, 1)
        XCTAssertEqual(first.fireDate, fired.addingTimeInterval(10 * 60))
        for notification in mine {
            XCTAssertGreaterThan(notification.fireDate, now)
            XCTAssertNotEqual(notification.id, NotificationID.chain(item.id, 0))
            XCTAssertGreaterThanOrEqual(notification.attempt, 1)
            XCTAssertEqual(notification.threadID, NotificationID.thread(item.id))
        }
    }

    func testSnoozedPlaceOnlyItemPlansFromTheSnooze() throws {
        var item = placeOnlyItem(1)
        let snooze = TestSupport.date("2026-09-28T10:30")
        item.snoozedUntil = snooze
        item.snoozeCount = 1
        let result = plan([item], now: "2026-09-28T10:00")
        let first = try XCTUnwrap(itemNotifications(result, item.id).first)
        XCTAssertEqual(first.id, NotificationID.chain(item.id, 0))
        XCTAssertEqual(first.fireDate, snooze)
    }

    func testPlaceWithDueIgnoresLocationFiredAt() {
        var timed = placeOnlyItem(1)
        timed.dueDate = TestSupport.date("2026-09-28T15:00")
        timed.hasTime = true
        var fired = timed
        fired.locationFiredAt = TestSupport.date("2026-09-28T09:00")
        let before = itemNotifications(plan([timed], now: "2026-09-28T10:00"), timed.id)
        let after = itemNotifications(plan([fired], now: "2026-09-28T10:00"), fired.id)
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(before, after)
        XCTAssertEqual(before.first?.id, NotificationID.chain(timed.id, 0))
        XCTAssertEqual(before.first?.fireDate, TestSupport.date("2026-09-28T15:00"))
    }

    func testImmediateRequestsMatchPlanForFiredPlaceItem() {
        var item = placeOnlyItem(1)
        item.locationFiredAt = TestSupport.date("2026-09-28T09:55")
        let input = PlanInput(items: [item], projects: [], places: [fabrika], settings: AppSettings(),
                              now: TestSupport.date("2026-09-28T10:00"), calendar: calendar, signingExpiry: nil)
        let immediate = NagPlanner.immediateRequests(for: item, input: input, limit: 2)
        XCTAssertEqual(immediate.map { $0.id }, [NotificationID.chain(item.id, 1), NotificationID.chain(item.id, 2)])
        var unfired = item
        unfired.locationFiredAt = nil
        XCTAssertTrue(NagPlanner.immediateRequests(for: unfired, input: input, limit: 2).isEmpty)
    }

    func testLocationSlotsReduceItemBudget() {
        let input = PlanInput(items: [], projects: [], places: [], settings: AppSettings(),
                              now: TestSupport.date("2026-09-28T10:00"), calendar: calendar, signingExpiry: nil,
                              locationSlotsUsed: 10)
        XCTAssertEqual(input.itemBudget, 40)
        XCTAssertEqual(plan([], now: "2026-09-28T10:00", locationSlotsUsed: 10).itemBudget, 40)
        XCTAssertEqual(plan([], now: "2026-09-28T10:00").itemBudget, 50)
    }

    // MARK: - Factory (07 §9.4)

    private func parsed(_ kind: ItemKind, _ title: String, due: String? = nil, priority: Priority = .normal,
                        place: PlaceRef?) -> ParsedItem {
        ParsedItem(kind: kind, title: title, dueDate: due.map { TestSupport.date($0) }, hasTime: due != nil,
                   priority: priority, place: place)
    }

    private func result(_ item: ParsedItem, text: String = "Fabrikaya varınca pano kontrolünü hatırlat") -> ParseResult {
        let kind = ParsedKind(rawValue: item.kind.rawValue) ?? .task
        return ParseResult(kind: kind, item: item, command: nil, confidence: 0.9, flags: [], understood: item.title,
                           relativePhrase: nil, originalText: text, normalizedText: text)
    }

    private func propose(_ item: ParsedItem, places: [Place], interactive: Bool = true,
                         source: CaptureSource = .voice) -> CaptureProposal? {
        let context = CaptureContext(settings: AppSettings(), projects: [], places: places, interactive: interactive)
        return ItemFactory.proposal(from: result(item), source: source, context: context,
                                    now: TestSupport.date("2026-09-28T10:00"), calendar: calendar)
    }

    func testConfiguredPlaceBecomesPlaceOnlyReminder() throws {
        let arrive = PlaceRef(name: "Fabrika", trigger: .onArrive)
        let interactive = try XCTUnwrap(propose(parsed(.reminder, "Pano kontrolü", place: arrive), places: [fabrika]))
        XCTAssertEqual(interactive.item.placeID, fabrika.id)
        XCTAssertEqual(interactive.item.placeTrigger, .onArrive)
        XCTAssertEqual(interactive.item.notes, "")
        XCTAssertNil(interactive.item.dueDate)
        XCTAssertFalse(interactive.item.hasTime)
        XCTAssertFalse(interactive.needsTime)
        XCTAssertFalse(interactive.appliedDefaultTime)
        XCTAssertFalse(interactive.defaultedToToday)
        XCTAssertEqual(interactive.level, .autoSave)
        XCTAssertEqual(interactive.item.kind, .reminder)

        let headless = try XCTUnwrap(propose(parsed(.reminder, "Pano kontrolü", place: arrive), places: [fabrika],
                                             interactive: false, source: .siri))
        XCTAssertEqual(headless.item.placeID, fabrika.id)
        XCTAssertNil(headless.item.dueDate)
        XCTAssertFalse(headless.needsTime)
        XCTAssertFalse(headless.appliedDefaultTime)
        XCTAssertFalse(headless.item.needsReview)
    }

    func testAliasAndCaseMatchAndLeaveTrigger() throws {
        let leave = PlaceRef(name: "SAHA", trigger: .onLeave)
        let proposal = try XCTUnwrap(propose(parsed(.reminder, "Ahmet'i ara", place: leave), places: [emptyFabrika, fabrika]))
        XCTAssertEqual(proposal.item.placeID, fabrika.id)
        XCTAssertEqual(proposal.item.placeTrigger, .onLeave)
    }

    func testPlaceOnlyTaskIsNotMovedToToday() throws {
        let arrive = PlaceRef(name: "Fabrika", trigger: .onArrive)
        let task = try XCTUnwrap(propose(parsed(.task, "Yedek parça listesi", place: arrive), places: [fabrika]))
        XCTAssertEqual(task.item.kind, .task)
        XCTAssertNil(task.item.dueDate)
        XCTAssertFalse(task.defaultedToToday)
        XCTAssertEqual(task.item.placeID, fabrika.id)

        // R5 (urgent task → reminder) does not apply to a place-only task either.
        let urgent = try XCTUnwrap(propose(parsed(.task, "Arızayı kontrol et", priority: .high, place: arrive),
                                           places: [fabrika]))
        XCTAssertEqual(urgent.item.kind, .task)
        XCTAssertNil(urgent.item.dueDate)
        XCTAssertFalse(urgent.needsTime)
    }

    func testConfiguredPlaceWithDueKeepsTheTime() throws {
        let arrive = PlaceRef(name: "Fabrika", trigger: .onArrive)
        let proposal = try XCTUnwrap(propose(parsed(.reminder, "Pano kontrolü", due: "2026-09-29T15:00", place: arrive),
                                             places: [fabrika]))
        XCTAssertEqual(proposal.item.placeID, fabrika.id)
        XCTAssertEqual(proposal.item.dueDate, TestSupport.date("2026-09-29T15:00"))
        XCTAssertTrue(proposal.item.hasTime)
    }

    func testUnconfiguredPlaceKeepsVersionOneBehaviour() throws {
        let arrive = PlaceRef(name: "Fabrika", trigger: .onArrive)
        let proposal = try XCTUnwrap(propose(parsed(.reminder, "Pano kontrolü", place: arrive), places: [emptyFabrika]))
        XCTAssertNil(proposal.item.placeID)
        XCTAssertNil(proposal.item.placeTrigger)
        XCTAssertEqual(proposal.item.notes, "Yer: Fabrika (varınca)")
        XCTAssertTrue(proposal.needsTime)
        XCTAssertEqual(proposal.level, .review)

        let unknown = try XCTUnwrap(propose(parsed(.reminder, "Pano kontrolü", place: PlaceRef(name: "Depo", trigger: .onLeave)),
                                            places: [fabrika]))
        XCTAssertNil(unknown.item.placeID)
        XCTAssertEqual(unknown.item.notes, "Yer: Depo (çıkınca)")
    }

    func testNoteIgnoresPlaces() throws {
        let arrive = PlaceRef(name: "Fabrika", trigger: .onArrive)
        let note = try XCTUnwrap(propose(parsed(.note, "Pano notu", place: arrive), places: [fabrika]))
        XCTAssertEqual(note.item.kind, .note)
        XCTAssertNil(note.item.placeID)
        XCTAssertNil(note.item.placeTrigger)
        XCTAssertFalse(note.item.notes.contains("Yer:"))
    }
}
