import Foundation
import XCTest
@testable import AsistCore

/// 04 §3.1 / §3.2 persistence rules (WP4): round trip with the frozen store coding (`.iso8601`, sorted keys),
/// forward compatibility (unknown keys and enum values, missing fields, corrupt array elements), every stored
/// property has a CodingKey, and the decode clamps of §3.2.3–§3.2.10.
final class ModelCodingTests: XCTestCase {

    // MARK: - Fixtures

    private let itemID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let secondItemID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let projectID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let placeID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let checklistID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

    /// Same configuration as the app store (App/Store/ImportExport.swift `StoreCoding`).
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try makeDecoder().decode(type, from: Data(json.utf8))
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try makeEncoder().encode(value)
        return try makeDecoder().decode(T.self, from: data)
    }

    private func jsonKeys<T: Encodable>(_ value: T) throws -> Set<String> {
        let data = try makeEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        let dictionary = try XCTUnwrap(object as? [String: Any])
        return Set(dictionary.keys)
    }

    private func storedPropertyNames(_ value: Any) -> Set<String> {
        var names = Set<String>()
        for child in Mirror(reflecting: value).children {
            if let label = child.label {
                names.insert(label)
            }
        }
        return names
    }

    /// Every optional set, so the synthesized encoder writes every key.
    private func fullItem() -> Item {
        let created = TestSupport.date("2026-09-27T10:14")
        let history = [HistoryEntry(date: created, event: .created, detail: "sesle")]
        let checklist = [ChecklistEntry(id: checklistID, text: "Fiyat listesi", done: true)]
        return Item(id: itemID,
                    kind: .reminder,
                    title: "Teklif konusu",
                    notes: "Ahmet'e sor",
                    originalText: "salı teklif konusunu hatırlat",
                    status: .open,
                    priority: .high,
                    dueDate: TestSupport.date("2026-09-29T15:00"),
                    hasTime: true,
                    recurrence: Recurrence(frequency: .weekly, interval: 2, weekdays: [2, 4], monthDay: 3, month: 5),
                    snoozedUntil: TestSupport.date("2026-09-29T15:10"),
                    snoozeCount: 1,
                    leadTimesMinutes: [10, 60],
                    nagProfile: .israrci,
                    isEvent: false,
                    person: "Ahmet",
                    projectID: projectID,
                    placeID: placeID,
                    placeTrigger: .onLeave,
                    locationFiredAt: TestSupport.date("2026-09-28T08:00"),
                    tags: ["teklif", "abb"],
                    checklist: checklist,
                    needsReview: true,
                    source: .voice,
                    parseConfidence: 0.5,
                    smartModeUsed: true,
                    createdAt: created,
                    updatedAt: TestSupport.date("2026-09-27T10:20"),
                    completedAt: TestSupport.date("2026-09-30T09:00"),
                    deletedAt: TestSupport.date("2026-10-01T09:00"),
                    lastDismissedAt: TestSupport.date("2026-09-29T15:02"),
                    completedOccurrences: 3,
                    history: history)
    }

    private func fullSettings() -> AppSettings {
        var settings = AppSettings()
        settings.userName = "Gökhan"
        settings.autoSaveSeconds = 20
        settings.workdays = [1, 2, 3, 4, 5, 6]
        settings.workStart = ClockTime(8, 0)
        settings.profileForNormal = .israrci
        settings.silenceSeconds = 2.5
        settings.eventDefaultLeadMinutes = 30
        settings.activeProjectID = projectID
        settings.onboardingCompleted = true
        settings.muteUntil = TestSupport.date("2026-09-27T11:30")
        return settings
    }

    private func fullMeta() -> AppMeta {
        var meta = AppMeta()
        meta.createdAt = TestSupport.date("2026-09-20T09:00")
        meta.lastSavedAt = TestSupport.date("2026-09-27T10:21")
        meta.lastProfileStamp = 1_790_000_000
        meta.lastReconcileAt = TestSupport.date("2026-09-27T10:21")
        meta.lastReconcileReason = "active"
        meta.lastPlannedCount = 42
        meta.lastDroppedCount = 2
        meta.lastBackgroundRefreshAt = TestSupport.date("2026-09-27T06:00")
        meta.lastDailyBackupDay = "20260927"
        meta.lastEndOfDayMove = MoveRecord(movedAt: TestSupport.date("2026-09-26T17:50"), before: [fullItem()])
        meta.composeDraft = "yarın"
        meta.dismissedBanners = ["kalici": TestSupport.date("2026-10-27T10:00")]
        meta.installDate = TestSupport.date("2026-09-20T09:00")
        meta.writerBuild = 57
        return meta
    }

    private func fullProject() -> Project {
        Project(id: projectID, name: "Arka Cep", aliases: ["arka cep hattı"], color: .orange, archived: false,
                createdAt: TestSupport.date("2026-09-20T09:00"), updatedAt: TestSupport.date("2026-09-21T09:00"))
    }

    private func fullPlace() -> Place {
        Place(id: placeID, name: "Fabrika", aliases: ["saha"], latitude: 40.75, longitude: 29.5, radiusMeters: 200,
              createdAt: TestSupport.date("2026-09-20T09:00"))
    }

    private func fullDocument() -> AppData {
        let second = Item(id: secondItemID, kind: .note, title: "Pano ölçüleri",
                          createdAt: TestSupport.date("2026-09-26T12:00"))
        return AppData(items: [fullItem(), second],
                       projects: [fullProject()],
                       places: [fullPlace()],
                       settings: fullSettings(),
                       meta: fullMeta())
    }

    // MARK: - Round trip

    func testAppDataRoundTripPreservesEverything() throws {
        let original = fullDocument()
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.items.count, 2)
        XCTAssertEqual(decoded.meta.lastEndOfDayMove?.before.first?.id, itemID)
        XCTAssertEqual(decoded.settings.muteUntil, TestSupport.date("2026-09-27T11:30"))
    }

    func testEmptyDocumentRoundTrip() throws {
        let now = TestSupport.date("2026-09-27T10:30")
        let empty = AppData.empty(now: now)
        XCTAssertEqual(empty.meta.createdAt, now)
        XCTAssertEqual(empty.meta.installDate, now)
        XCTAssertEqual(empty.schemaVersion, AppData.currentSchemaVersion)
        XCTAssertEqual(try roundTrip(empty), empty)
    }

    func testDatesAreWholeSecondISO8601InUTC() throws {
        var item = fullItem()
        item.dueDate = TestSupport.date("2026-09-27T10:30")          // Istanbul (UTC+3)
        let data = try makeEncoder().encode(item)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"dueDate\":\"2026-09-27T07:30:00Z\""), text)
    }

    // MARK: - Every stored property is persisted (a missing CodingKey compiles but silently drops data)

    func testItemEncodesEveryStoredProperty() throws {
        let item = fullItem()
        XCTAssertEqual(try jsonKeys(item), storedPropertyNames(item))
        XCTAssertEqual(storedPropertyNames(item).count, 33)
    }

    func testSettingsEncodeEveryStoredPropertyAndNoProfileTable() throws {
        let settings = fullSettings()
        let keys = try jsonKeys(settings)
        XCTAssertEqual(keys, storedPropertyNames(settings))
        XCTAssertFalse(keys.contains("nagProfiles"))
    }

    func testMetaAndSmallTypesEncodeEveryStoredProperty() throws {
        let meta = fullMeta()
        XCTAssertEqual(try jsonKeys(meta), storedPropertyNames(meta))
        let project = fullProject()
        XCTAssertEqual(try jsonKeys(project), storedPropertyNames(project))
        let place = fullPlace()
        XCTAssertEqual(try jsonKeys(place), storedPropertyNames(place))
        let rule = Recurrence(frequency: .yearly, interval: 1, weekdays: [1], monthDay: 15, month: 6)
        XCTAssertEqual(try jsonKeys(rule), storedPropertyNames(rule))
        let entry = HistoryEntry(date: TestSupport.date("2026-09-27T10:00"), event: .snoozed, detail: "28 Eyl 09:00")
        XCTAssertEqual(try jsonKeys(entry), storedPropertyNames(entry))
        let move = MoveRecord(movedAt: TestSupport.date("2026-09-27T17:50"), before: [])
        XCTAssertEqual(try jsonKeys(move), storedPropertyNames(move))
        let document = fullDocument()
        XCTAssertEqual(try jsonKeys(document), storedPropertyNames(document))
    }

    // MARK: - Forward compatibility

    func testUnknownKeysAreIgnoredAtEveryLevel() throws {
        let original = fullDocument()
        let data = try makeEncoder().encode(original)
        // Textual injection (sorted keys make the first key of every object predictable); avoids re-serializing
        // through JSONSerialization.
        var text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\"items\":["))
        text = "{\"gelecekAlani\":{\"a\":[1,2]}," + String(text.dropFirst())
        XCTAssertTrue(text.contains("{\"checklist\":"))
        text = text.replacingOccurrences(of: "{\"checklist\":", with: "{\"yeniAlan\":\"x\",\"checklist\":")
        XCTAssertTrue(text.contains("{\"activeProjectID\":"))
        text = text.replacingOccurrences(of: "{\"activeProjectID\":", with: "{\"yeniAyar\":true,\"activeProjectID\":")
        XCTAssertTrue(text.contains("{\"composeDraft\":"))
        text = text.replacingOccurrences(of: "{\"composeDraft\":", with: "{\"yeniMeta\":5,\"composeDraft\":")
        let decoded = try makeDecoder().decode(AppData.self, from: Data(text.utf8))
        XCTAssertEqual(decoded, original)
    }

    func testUnknownEnumValuesFallBackToDocumentedCases() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Gelecek sürüm kaydı",
          "kind": "project",
          "status": "archived",
          "priority": 9,
          "nagProfile": "cokIsrarci",
          "source": "telepathy",
          "placeTrigger": "hover",
          "recurrence": { "frequency": "hourly", "interval": 1 },
          "history": [ { "date": "2026-09-27T07:30:00Z", "event": "teleported" } ]
        }
        """
        let item = try decode(Item.self, json)
        XCTAssertEqual(item.id, itemID)
        XCTAssertEqual(item.kind, .task)
        XCTAssertEqual(item.status, .open)
        XCTAssertEqual(item.priority, .normal)
        XCTAssertEqual(item.nagProfile, .nazik)
        XCTAssertEqual(item.source, .other)
        XCTAssertEqual(item.placeTrigger, .onArrive)
        XCTAssertEqual(item.recurrence?.frequency, .daily)
        XCTAssertEqual(item.history.count, 1)
        XCTAssertEqual(item.history.first?.event, .other)

        let project = try decode(Project.self, "{\"name\":\"P\",\"color\":\"gold\"}")
        XCTAssertEqual(project.color, .blue)
        let settings = try decode(AppSettings.self, "{\"ttsRate\":\"warp\",\"badgeMode\":\"x\",\"noTimeBehavior\":\"y\"}")
        XCTAssertEqual(settings.ttsRate, .normal)
        XCTAssertEqual(settings.badgeMode, .overdue)
        XCTAssertEqual(settings.noTimeBehavior, .ask)

        // WP0-FIX: an unknown profile raw value falls back to that field's documented default (D7), not to .nazik.
        let profiles = try decode(AppSettings.self,
                                  "{\"profileForCritical\":\"cokIsrarci\",\"profileForHigh\":7,\"profileForLow\":\"x\"}")
        XCTAssertEqual(profiles.profileForCritical, .birakmaz)
        XCTAssertEqual(profiles.profileForHigh, .israrci)
        XCTAssertEqual(profiles.profileForLow, .nazik)
        XCTAssertEqual(profiles.profileForNormal, .nazik)
    }

    func testMissingFieldsUseDefaults() throws {
        let item = try decode(Item.self, "{}")
        XCTAssertEqual(item.kind, .task)
        XCTAssertEqual(item.title, "")
        XCTAssertEqual(item.notes, "")
        XCTAssertEqual(item.status, .open)
        XCTAssertEqual(item.priority, .normal)
        XCTAssertNil(item.dueDate)
        XCTAssertFalse(item.hasTime)
        XCTAssertNil(item.recurrence)
        XCTAssertEqual(item.snoozeCount, 0)
        XCTAssertEqual(item.leadTimesMinutes, [])
        XCTAssertNil(item.nagProfile)
        XCTAssertFalse(item.isEvent)
        XCTAssertEqual(item.checklist, [])
        XCTAssertEqual(item.history, [])
        XCTAssertEqual(item.source, .other)
        XCTAssertEqual(item.createdAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(item.updatedAt, item.createdAt)

        let document = try decode(AppData.self, "{}")
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.items, [])
        XCTAssertEqual(document.projects, [])
        XCTAssertEqual(document.places, [])
        XCTAssertEqual(document.settings, AppSettings())
        XCTAssertEqual(document.meta, AppMeta())

        let settings = try decode(AppSettings.self, "{\"userName\":\"Gökhan\"}")
        var expected = AppSettings()
        expected.userName = "Gökhan"
        XCTAssertEqual(settings, expected)

        let meta = try decode(AppMeta.self, "{}")
        XCTAssertEqual(meta.writerBuild, 0)
        XCTAssertNil(meta.lastSavedAt)

        let updatedFallsBackToCreated = try decode(Item.self, "{\"createdAt\":\"2026-09-27T07:30:00Z\"}")
        XCTAssertEqual(updatedFallsBackToCreated.createdAt, TestSupport.date("2026-09-27T10:30"))
        XCTAssertEqual(updatedFallsBackToCreated.updatedAt, updatedFallsBackToCreated.createdAt)
    }

    func testGarbledFieldsDegradeFieldByField() throws {
        let json = """
        {
          "title": "Pano",
          "dueDate": "dün",
          "priority": "high",
          "hasTime": "evet",
          "snoozeCount": "iki",
          "tags": "tek",
          "checklist": [ { "text": "Kablo" }, 3, "bozuk" ],
          "history": { "a": 1 }
        }
        """
        let item = try decode(Item.self, json)
        XCTAssertEqual(item.title, "Pano")
        XCTAssertNil(item.dueDate)
        XCTAssertEqual(item.priority, .normal)
        XCTAssertFalse(item.hasTime)
        XCTAssertEqual(item.snoozeCount, 0)
        XCTAssertEqual(item.tags, [])
        XCTAssertEqual(item.checklist.count, 1)
        XCTAssertEqual(item.checklist.first?.text, "Kablo")
        XCTAssertEqual(item.history, [])
    }

    func testCorruptArrayElementsAreDroppedNotTheWholeArray() throws {
        let json = """
        {
          "schemaVersion": 1,
          "items": [
            { "id": "11111111-1111-1111-1111-111111111111", "title": "Birinci" },
            null,
            42,
            "bozuk",
            [1, 2],
            null,
            { "id": "44444444-4444-4444-4444-444444444444", "title": "İkinci" }
          ],
          "projects": [ 7, null, { "name": "Arka Cep" } ],
          "places": [ true, null ]
        }
        """
        // WP0-FIX: JSON null elements are skipped (LossyDecodableArray) — the elements after a null survive.
        let document = try decode(AppData.self, json)
        XCTAssertEqual(document.items.map { $0.title }, ["Birinci", "İkinci"])
        XCTAssertEqual(document.items.map { $0.id }, [itemID, secondItemID])
        XCTAssertEqual(document.projects.map { $0.name }, ["Arka Cep"])
        XCTAssertEqual(document.places, [])
    }

    /// The store's structural check (05a #22) exists because this decodes "successfully" to empty collections.
    func testWrongTopLevelTypesDecodeAsDefaults() throws {
        let json = """
        { "items": { "a": 1 }, "projects": "x", "settings": 5, "meta": [1] }
        """
        let document = try decode(AppData.self, json)
        XCTAssertEqual(document.items, [])
        XCTAssertEqual(document.projects, [])
        XCTAssertEqual(document.settings, AppSettings())
        XCTAssertEqual(document.meta, AppMeta())
    }

    func testRevisionOneProfileTableKeyIsIgnored() throws {
        let json = """
        { "profileForHigh": "birakmaz", "nagProfiles": { "nazik": { "dailyCap": 99 } } }
        """
        let settings = try decode(AppSettings.self, json)
        XCTAssertEqual(settings.profileForHigh, .birakmaz)
        XCTAssertEqual(settings.nagProfiles, NagProfiles())
    }

    func testNotADocumentThrows() {
        XCTAssertThrowsError(try decode(AppData.self, "[1, 2, 3]"))
        XCTAssertThrowsError(try decode(AppData.self, "{ \"items\": [ "))
    }

    // MARK: - Decode clamps

    func testSettingsClamps() throws {
        let json = """
        {
          "autoSaveSeconds": 5,
          "workdays": [],
          "waitingDefaultWorkdays": 50,
          "eventDefaultLeadMinutes": -5,
          "backupReminderWeekday": 0,
          "silenceSeconds": 0.1,
          "profileForLow": "etkinlik",
          "profileForHigh": "takip",
          "workStart": { "hour": 25, "minute": -1 }
        }
        """
        let settings = try decode(AppSettings.self, json)
        XCTAssertEqual(settings.autoSaveSeconds, 12)
        XCTAssertEqual(settings.workdays, [1, 2, 3, 4, 5])
        XCTAssertEqual(settings.waitingDefaultWorkdays, 10)
        XCTAssertEqual(settings.eventDefaultLeadMinutes, 0)
        XCTAssertEqual(settings.backupReminderWeekday, 1)
        XCTAssertEqual(settings.silenceSeconds, 0.8, accuracy: 0.000_1)
        XCTAssertEqual(settings.profileForLow, .nazik)
        XCTAssertEqual(settings.profileForHigh, .israrci)
        XCTAssertEqual(settings.workStart, ClockTime(23, 0))

        let upper = """
        {
          "autoSaveSeconds": 0,
          "workdays": [9, 0, 6, 3, 3],
          "waitingDefaultWorkdays": -3,
          "eventDefaultLeadMinutes": 99999,
          "backupReminderWeekday": 9,
          "silenceSeconds": 10
        }
        """
        let other = try decode(AppSettings.self, upper)
        XCTAssertEqual(other.autoSaveSeconds, 0)
        XCTAssertEqual(other.workdays, [3, 6])
        XCTAssertEqual(other.waitingDefaultWorkdays, 1)
        XCTAssertEqual(other.eventDefaultLeadMinutes, 1440)
        XCTAssertEqual(other.backupReminderWeekday, 7)
        XCTAssertEqual(other.silenceSeconds, 5, accuracy: 0.000_1)
    }

    func testClockTimeClamps() throws {
        XCTAssertEqual(try decode(ClockTime.self, "{\"hour\":25,\"minute\":-1}"), ClockTime(23, 0))
        XCTAssertEqual(try decode(ClockTime.self, "{\"hour\":-4,\"minute\":75}"), ClockTime(0, 59))
        XCTAssertEqual(try decode(ClockTime.self, "{\"hour\":\"x\"}"), ClockTime(9, 0))
        XCTAssertEqual(ClockTime(minutesOfDay: -30), ClockTime(23, 30))
        XCTAssertEqual(ClockTime(minutesOfDay: 1500), ClockTime(1, 0))
    }

    func testRecurrenceClamps() throws {
        let weekly = try decode(Recurrence.self,
                                "{\"frequency\":\"weekly\",\"interval\":0,\"weekdays\":[9,0,3,1,3],\"monthDay\":0,\"month\":13}")
        XCTAssertEqual(weekly.frequency, .weekly)
        XCTAssertEqual(weekly.interval, 1)
        XCTAssertEqual(weekly.weekdays, [1, 3])
        XCTAssertNil(weekly.monthDay)
        XCTAssertNil(weekly.month)

        let monthly = try decode(Recurrence.self, "{\"frequency\":\"monthly\",\"interval\":500,\"monthDay\":-1,\"month\":12}")
        XCTAssertEqual(monthly.interval, 120)
        XCTAssertEqual(monthly.monthDay, -1)
        XCTAssertEqual(monthly.month, 12)

        let invalid = try decode(Recurrence.self, "{\"frequency\":\"weekly\",\"weekdays\":[8],\"monthDay\":32}")
        XCTAssertNil(invalid.weekdays)
        XCTAssertNil(invalid.monthDay)
    }

    func testNagProfileClamps() throws {
        let json = """
        {
          "followUpOffsetsMinutes": [0, -5, 10, 10, 2000, 30],
          "repeatMinutesWorkHours": 0,
          "repeatMinutesOffHours": -3,
          "dailyCap": 0,
          "maxPendingFollowUps": 50
        }
        """
        let profile = try decode(NagProfile.self, json)
        XCTAssertEqual(profile.followUpOffsetsMinutes, [10, 30])
        XCTAssertEqual(profile.repeatMinutesWorkHours, 5)
        XCTAssertEqual(profile.repeatMinutesOffHours, 5)
        XCTAssertEqual(profile.dailyCap, 1)
        XCTAssertEqual(profile.maxPendingFollowUps, 20)

        let capped = try decode(NagProfile.self, "{\"dailyCap\":1000,\"maxPendingFollowUps\":-1}")
        XCTAssertEqual(capped.dailyCap, 60)
        XCTAssertEqual(capped.maxPendingFollowUps, 0)
    }

    func testItemPlaceAndMetaClamps() throws {
        let item = try decode(Item.self, "{\"snoozeCount\":-3,\"leadTimesMinutes\":[-1,0,30,10,10,600000]}")
        XCTAssertEqual(item.snoozeCount, 0)
        XCTAssertEqual(item.leadTimesMinutes, [10, 30])

        let place = try decode(Place.self, "{\"latitude\":100,\"longitude\":-500,\"radiusMeters\":5}")
        XCTAssertEqual(place.latitude, 90, accuracy: 0.000_1)
        XCTAssertEqual(place.longitude, -180, accuracy: 0.000_1)
        XCTAssertEqual(place.radiusMeters, 100, accuracy: 0.000_1)
        let farPlace = try decode(Place.self, "{\"radiusMeters\":5000}")
        XCTAssertEqual(farPlace.radiusMeters, 1000, accuracy: 0.000_1)

        let meta = try decode(AppMeta.self, "{\"writerBuild\":-5,\"dismissedBanners\":\"x\",\"lastPlannedCount\":\"y\"}")
        XCTAssertEqual(meta.writerBuild, 0)
        XCTAssertEqual(meta.dismissedBanners, [:])
        XCTAssertEqual(meta.lastPlannedCount, 0)
    }
}
