import Foundation
import XCTest
@testable import AsistCore

/// 07 §3 / §11.1–11.3: revision-4 fields decode from older files with their defaults and clamps.
final class Revision4ModelTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(json.utf8))
    }

    func testOldSettingsDecodeRevision4Defaults() throws {
        let settings = try decode(AppSettings.self, "{\"userName\":\"Gökhan\"}")
        XCTAssertTrue(settings.updateCheckEnabled)
        XCTAssertTrue(settings.calendarOnToday)
        XCTAssertEqual(settings.calendarLeadMinutes, 15)
    }

    func testCalendarLeadIsClampedToChoices() throws {
        XCTAssertEqual(try decode(AppSettings.self, "{\"calendarLeadMinutes\":7}").calendarLeadMinutes, 15)
        XCTAssertEqual(try decode(AppSettings.self, "{\"calendarLeadMinutes\":30}").calendarLeadMinutes, 30)
        let garbage = try decode(AppSettings.self, "{\"calendarLeadMinutes\":\"x\",\"updateCheckEnabled\":\"no\"}")
        XCTAssertEqual(garbage.calendarLeadMinutes, 15)
        XCTAssertTrue(garbage.updateCheckEnabled)
    }

    func testOldMetaDecodesUpdateDefaults() throws {
        let meta = try decode(AppMeta.self, "{\"writerBuild\":12}")
        XCTAssertNil(meta.lastUpdateCheckAt)
        XCTAssertEqual(meta.latestBuildSeen, 0)
        XCTAssertNil(meta.latestBuildDate)
        XCTAssertNil(meta.latestBuildNotes)
        XCTAssertEqual(try decode(AppMeta.self, "{\"latestBuildSeen\":-4}").latestBuildSeen, 0)
    }

    func testMetaUpdateFieldsRoundTrip() throws {
        var meta = AppMeta()
        meta.lastUpdateCheckAt = Date(timeIntervalSince1970: 1_790_000_000)
        meta.latestBuildSeen = 61
        meta.latestBuildDate = Date(timeIntervalSince1970: 1_790_000_100)
        meta.latestBuildNotes = "Düzenle, widget'lar"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(AppMeta.self, from: data), meta)
    }

    func testCaptureSourceCalendar() throws {
        let data = try JSONEncoder().encode([CaptureSource.calendar])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"calendar\"]")
        XCTAssertEqual(try JSONDecoder().decode([CaptureSource].self, from: data), [CaptureSource.calendar])
        XCTAssertEqual(CaptureSource.calendar.historyLabel, "takvimden")
        let unknown = try JSONDecoder().decode([CaptureSource].self, from: Data("[\"gelecek\"]".utf8))
        XCTAssertEqual(unknown, [CaptureSource.other])
    }
}
