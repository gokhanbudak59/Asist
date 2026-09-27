// LocationPlannerTests.swift — revision 4, F6 (07 §9.2, §13): geofence candidates, content, fingerprints and the
// Konumlar text helpers. Fixed dates (TestSupport, Europe/Istanbul); nothing reads Date() or the device locale.
import Foundation
import XCTest
@testable import AsistCore

final class LocationPlannerTests: XCTestCase {
    private let created = TestSupport.date("2026-09-20T09:00")

    // MARK: - Helpers

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-4000-8000-" + AsistCalendar.pad(n, 12))!
    }

    private func fabrika(radius: Double = 200) -> Place {
        Place(id: uuid(900), name: "Fabrika", aliases: ["saha"], latitude: 40.7806, longitude: 29.9420,
              radiusMeters: radius, createdAt: created)
    }

    private func emptySlot(_ n: Int, _ name: String) -> Place {
        Place(id: uuid(n), name: name, latitude: 0, longitude: 0, radiusMeters: 150, createdAt: created)
    }

    private func placeItem(_ n: Int, title: String = "Pano kontrolü", kind: ItemKind = .reminder,
                           priority: Priority = .normal, place: Place? = nil, trigger: PlaceTrigger? = .onArrive,
                           createdAt: String = "2026-09-20T09:00") -> Item {
        var item = Item(id: uuid(n), kind: kind, title: title, createdAt: TestSupport.date(createdAt))
        item.priority = priority
        item.placeID = (place ?? fabrika()).id
        item.placeTrigger = trigger
        return item
    }

    // MARK: - isConfigured / radius

    func testIsConfigured() {
        XCTAssertFalse(LocationPlanner.isConfigured(emptySlot(1, "Ofis")))
        XCTAssertTrue(LocationPlanner.isConfigured(fabrika()))
        XCTAssertTrue(LocationPlanner.isConfigured(Place(name: "Ekvator", latitude: 0, longitude: 29.5, createdAt: created)))
        XCTAssertTrue(LocationPlanner.isConfigured(Place(name: "Sınır", latitude: -90, longitude: 180, createdAt: created)))
        XCTAssertFalse(LocationPlanner.isConfigured(Place(name: "Bozuk", latitude: 91, longitude: 10, createdAt: created)))
        XCTAssertFalse(LocationPlanner.isConfigured(Place(name: "Bozuk", latitude: 10, longitude: -181, createdAt: created)))
        XCTAssertFalse(LocationPlanner.isConfigured(Place(name: "Bozuk", latitude: Double.nan, longitude: 10,
                                                          createdAt: created)))
        XCTAssertFalse(LocationPlanner.isUsableFix(latitude: 0, longitude: 0))
        XCTAssertTrue(LocationPlanner.isUsableFix(latitude: 40.1, longitude: 29.2))
    }

    func testRadiusClampAndLabels() {
        XCTAssertEqual(LocationPlanner.clampedRadius(50), 100)
        XCTAssertEqual(LocationPlanner.clampedRadius(5000), 1000)
        XCTAssertEqual(LocationPlanner.clampedRadius(250), 250)
        XCTAssertEqual(LocationPlanner.clampedRadius(Double.nan), 150)
        XCTAssertEqual(LocationPlanner.radiusChoices, [100, 150, 250, 500, 1000])
        XCTAssertEqual(LocationPlanner.radiusLabel(150), "150 m")
        XCTAssertEqual(LocationPlanner.radiusLabel(1000), "1 km")
        XCTAssertEqual(LocationPlanner.radiusLabel(20), "100 m")
        XCTAssertEqual(LocationPlanner.seedPlaceNames, ["Fabrika", "Ofis", "Ev"])
    }

    // MARK: - Candidates

    func testCandidateFieldsAndIDFormat() throws {
        let item = placeItem(1)
        let specs = LocationPlanner.candidates(items: [item], places: [fabrika()], projects: [])
        let spec = try XCTUnwrap(specs.first)
        XCTAssertEqual(specs.count, 1)
        XCTAssertEqual(spec.id, "asist.loc." + item.id.uuidString)
        XCTAssertEqual(spec.id, NotificationID.location(item.id))
        XCTAssertEqual(NotificationID.itemID(from: spec.id), item.id)
        XCTAssertFalse(NotificationID.isPlannerManaged(spec.id))
        XCTAssertEqual(spec.itemID, item.id)
        XCTAssertEqual(spec.latitude, 40.7806)
        XCTAssertEqual(spec.longitude, 29.9420)
        XCTAssertEqual(spec.radiusMeters, 200)
        XCTAssertTrue(spec.notifyOnEntry)
        XCTAssertFalse(spec.notifyOnExit)
        XCTAssertEqual(spec.categoryID, NotificationCategoryID.item)
        XCTAssertEqual(spec.threadID, NotificationID.thread(item.id))
        XCTAssertFalse(spec.fingerprint.isEmpty)
    }

    func testCandidatesExcludeIneligibleItems() {
        let office = emptySlot(901, "Ofis")
        var done = placeItem(1)
        done.status = .done
        var deleted = placeItem(2)
        deleted.status = .deleted
        let note = placeItem(3, kind: .note)
        var fired = placeItem(4)
        fired.locationFiredAt = TestSupport.date("2026-09-27T09:00")
        let noTrigger = placeItem(5, trigger: nil)
        let unconfigured = placeItem(6, place: office)
        var missingPlace = placeItem(7)
        missingPlace.placeID = uuid(999)
        var noPlace = placeItem(8)
        noPlace.placeID = nil
        let eligible = placeItem(9)
        let items = [done, deleted, note, fired, noTrigger, unconfigured, missingPlace, noPlace, eligible]
        let specs = LocationPlanner.candidates(items: items, places: [fabrika(), office], projects: [])
        XCTAssertEqual(specs.map { $0.itemID }, [eligible.id])
        XCTAssertTrue(LocationPlanner.candidates(items: items, places: [office], projects: []).isEmpty)
    }

    func testCandidatesOrderByPriorityThenCreatedAtThenID() {
        let low = placeItem(1, priority: .low, createdAt: "2026-09-10T09:00")
        let normalLate = placeItem(2, priority: .normal, createdAt: "2026-09-21T09:00")
        let normalEarly = placeItem(3, priority: .normal, createdAt: "2026-09-19T09:00")
        let critical = placeItem(4, priority: .critical, createdAt: "2026-09-25T09:00")
        let normalSameB = placeItem(6, priority: .normal, createdAt: "2026-09-19T09:00")
        let normalSameA = placeItem(5, priority: .normal, createdAt: "2026-09-19T09:00")
        let specs = LocationPlanner.candidates(items: [low, normalLate, normalEarly, critical, normalSameB, normalSameA],
                                               places: [fabrika()], projects: [])
        XCTAssertEqual(specs.map { $0.itemID },
                       [critical.id, normalEarly.id, normalSameA.id, normalSameB.id, normalLate.id, low.id])
    }

    func testCandidatesAreCappedAtTen() {
        var items: [Item] = []
        for n in 1...12 {
            items.append(placeItem(n, createdAt: "2026-09-" + AsistCalendar.pad(n + 10, 2) + "T09:00"))
        }
        let specs = LocationPlanner.candidates(items: items, places: [fabrika()], projects: [])
        XCTAssertEqual(specs.count, LocationPlanner.maxRequests)
        XCTAssertEqual(specs.count, 10)
        XCTAssertEqual(specs.first?.itemID, uuid(1))
        XCTAssertEqual(specs.last?.itemID, uuid(10))
    }

    func testRadiusIsClampedInSpec() {
        let tight = fabrika(radius: 20)
        let wide = Place(id: uuid(902), name: "Depo", latitude: 40.9, longitude: 29.1, radiusMeters: 9000,
                         createdAt: created)
        let specs = LocationPlanner.candidates(items: [placeItem(1, place: tight), placeItem(2, place: wide)],
                                               places: [tight, wide], projects: [])
        XCTAssertEqual(specs.map { $0.radiusMeters }, [100, 1000])
    }

    func testLeaveTriggerAndFollowUpCategory() throws {
        let leaving = placeItem(1, title: "Ahmet'i ara", trigger: .onLeave)
        let waiting = placeItem(2, title: "Teklif dönüşü", kind: .waiting, createdAt: "2026-09-21T09:00")
        let specs = LocationPlanner.candidates(items: [leaving, waiting], places: [fabrika()], projects: [])
        XCTAssertEqual(specs.count, 2)
        let first = try XCTUnwrap(specs.first { $0.itemID == leaving.id })
        XCTAssertFalse(first.notifyOnEntry)
        XCTAssertTrue(first.notifyOnExit)
        XCTAssertEqual(first.categoryID, NotificationCategoryID.item)
        XCTAssertEqual(first.text.subtitle, "Fabrika · çıkınca")
        let second = try XCTUnwrap(specs.first { $0.itemID == waiting.id })
        XCTAssertTrue(second.notifyOnEntry)
        XCTAssertEqual(second.categoryID, NotificationCategoryID.followUp)
    }

    // MARK: - Content

    func testContentStrings() {
        var item = placeItem(1, title: "Pano kontrolünü yap")
        let plain = LocationPlanner.content(item: item, place: fabrika(), projectName: nil)
        XCTAssertEqual(plain.title, "Pano kontrolünü yap")
        XCTAssertEqual(plain.subtitle, "Fabrika · varınca")
        XCTAssertEqual(plain.body, "“✓ Yaptım” demezsen, bir sonraki açılışta hatırlatmaya devam ederim.")
        XCTAssertEqual(plain.body, LocationPlanner.notificationBody)

        let withProject = LocationPlanner.content(item: item, place: fabrika(), projectName: "Kocaeli Hattı")
        XCTAssertEqual(withProject.subtitle, "Fabrika · varınca · Kocaeli Hattı")
        let blankProject = LocationPlanner.content(item: item, place: fabrika(), projectName: "  ")
        XCTAssertEqual(blankProject.subtitle, "Fabrika · varınca")

        item.title = "   "
        XCTAssertEqual(LocationPlanner.content(item: item, place: fabrika(), projectName: nil).title, "Hatırlatma")
        item.title = "Çıkınca\nAhmet'i ara"
        item.placeTrigger = .onLeave
        let leaving = LocationPlanner.content(item: item, place: fabrika(), projectName: nil)
        XCTAssertEqual(leaving.title, "Çıkınca Ahmet'i ara")
        XCTAssertEqual(leaving.subtitle, "Fabrika · çıkınca")
    }

    func testCandidateContentUsesProjectName() throws {
        let project = Project(id: uuid(700), name: "Kocaeli Hattı", createdAt: created)
        var item = placeItem(1)
        item.projectID = project.id
        let spec = try XCTUnwrap(LocationPlanner.candidates(items: [item], places: [fabrika()],
                                                            projects: [project]).first)
        XCTAssertEqual(spec.text.subtitle, "Fabrika · varınca · Kocaeli Hattı")
    }

    // MARK: - Fingerprint

    func testFingerprintIsStableAndTracksRequestFields() throws {
        let item = placeItem(1)
        let base = try XCTUnwrap(LocationPlanner.candidates(items: [item], places: [fabrika()], projects: []).first)
        let again = try XCTUnwrap(LocationPlanner.candidates(items: [item], places: [fabrika()], projects: []).first)
        XCTAssertEqual(base.fingerprint, again.fingerprint)

        // Fields that do not reach the system request keep the fingerprint.
        var noted = item
        noted.notes = "Yeni not"
        noted.priority = .high
        let sameRequest = try XCTUnwrap(LocationPlanner.candidates(items: [noted], places: [fabrika()],
                                                                   projects: []).first)
        XCTAssertEqual(sameRequest.fingerprint, base.fingerprint)

        var retitled = item
        retitled.title = "Başka iş"
        let titleChanged = try XCTUnwrap(LocationPlanner.candidates(items: [retitled], places: [fabrika()],
                                                                    projects: []).first)
        XCTAssertNotEqual(titleChanged.fingerprint, base.fingerprint)

        let wider = fabrika(radius: 500)
        let radiusChanged = try XCTUnwrap(LocationPlanner.candidates(items: [item], places: [wider],
                                                                     projects: []).first)
        XCTAssertNotEqual(radiusChanged.fingerprint, base.fingerprint)

        var leaving = item
        leaving.placeTrigger = .onLeave
        let triggerChanged = try XCTUnwrap(LocationPlanner.candidates(items: [leaving], places: [fabrika()],
                                                                      projects: []).first)
        XCTAssertNotEqual(triggerChanged.fingerprint, base.fingerprint)

        var moved = fabrika()
        moved.latitude = 40.7807
        let coordinateChanged = try XCTUnwrap(LocationPlanner.candidates(items: [item], places: [moved],
                                                                         projects: []).first)
        XCTAssertNotEqual(coordinateChanged.fingerprint, base.fingerprint)
    }

    func testFingerprintFormula() {
        let text = NotificationText(title: "A", subtitle: "B", body: "C")
        let spec = LocationRequestSpec(id: "asist.loc.X", itemID: uuid(1), latitude: 1.5, longitude: 2.25,
                                       radiusMeters: 150, notifyOnEntry: true, notifyOnExit: false, text: text,
                                       categoryID: "ASIST_ITEM", threadID: "asist.i.X")
        XCTAssertEqual(spec.fingerprint, StableHash.fnv1a64("asist.loc.X|1.5|2.25|150.0|1|0|A|B|C|ASIST_ITEM"))
    }

    // MARK: - Helpers of the Konumlar screens

    func testConfiguredPlaceLookupByNameAndAlias() {
        let places = [emptySlot(901, "Ofis"), fabrika()]
        XCTAssertEqual(LocationPlanner.configuredPlace(named: "fabrika", in: places)?.id, fabrika().id)
        XCTAssertEqual(LocationPlanner.configuredPlace(named: "FABRİKA", in: places)?.id, fabrika().id)
        XCTAssertEqual(LocationPlanner.configuredPlace(named: "Saha", in: places)?.id, fabrika().id)
        XCTAssertNil(LocationPlanner.configuredPlace(named: "Ofis", in: places))
        XCTAssertNil(LocationPlanner.configuredPlace(named: "Depo", in: places))
        XCTAssertNil(LocationPlanner.configuredPlace(named: "  ", in: places))
    }

    func testOpenItemCount() {
        var done = placeItem(1)
        done.status = .done
        let open = placeItem(2)
        let other = placeItem(3, place: emptySlot(901, "Ofis"))
        let note = placeItem(4, kind: .note)
        XCTAssertEqual(LocationPlanner.openItemCount(placeID: fabrika().id, items: [done, open, other, note]), 1)
    }

    func testSettingsSubtitle() {
        let slots = [emptySlot(1, "Fabrika"), emptySlot(2, "Ofis"), emptySlot(3, "Ev")]
        XCTAssertEqual(LocationPlanner.settingsSubtitle(places: []), "Fabrika, ofis, ev · henüz kayıtlı yer yok")
        XCTAssertEqual(LocationPlanner.settingsSubtitle(places: slots), "Fabrika, ofis, ev · henüz kayıtlı yer yok")
        XCTAssertEqual(LocationPlanner.settingsSubtitle(places: slots + [fabrika()]), "1 yer kayıtlı")
    }

    func testAliasParsing() {
        XCTAssertEqual(LocationPlanner.aliases(from: "saha, tesis ,, Saha; üretim\nfabrika", excluding: "Fabrika"),
                       ["saha", "tesis", "üretim"])
        XCTAssertEqual(LocationPlanner.aliases(from: "   "), [])
        XCTAssertEqual(LocationPlanner.aliasText(["saha", "tesis"]), "saha, tesis")
    }

    func testCoordinateText() {
        XCTAssertEqual(LocationPlanner.coordinateText(40.78061234), "40.78061")
        XCTAssertEqual(LocationPlanner.coordinateText(29.942), "29.94200")
        XCTAssertEqual(LocationPlanner.coordinateText(-3), "-3.00000")
        XCTAssertEqual(LocationPlanner.coordinateText(0.00001), "0.00001")
        XCTAssertEqual(LocationPlanner.coordinateText(-0.000001), "0.00000")
        XCTAssertEqual(LocationPlanner.coordinateText(12.5, decimals: 0), "13")
        XCTAssertEqual(LocationPlanner.coordinateText(Double.infinity), "0")
    }

    func testSavedText() {
        XCTAssertEqual(LocationPlanner.savedText(accuracy: 12.4), "Konum kaydedildi (±12 m)")
        XCTAssertEqual(LocationPlanner.savedText(accuracy: 100), "Konum kaydedildi (±100 m)")
        XCTAssertEqual(LocationPlanner.savedText(accuracy: 140),
                       "Konum kaydedildi (±140 m) — doğruluk düşük, açık alanda tekrar dene")
        XCTAssertEqual(LocationPlanner.savedText(accuracy: -1), "Konum kaydedildi")
        XCTAssertEqual(LocationPlanner.placeLabel(name: " Ofis ", trigger: .onLeave), "Ofis · çıkınca")
        XCTAssertEqual(LocationPlanner.placeLabel(name: "", trigger: .onArrive), "Yer · varınca")
    }
}
