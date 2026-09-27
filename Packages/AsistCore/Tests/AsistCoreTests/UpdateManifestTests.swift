import Foundation
import XCTest
@testable import AsistCore

/// 07 §6.2 / §13: `surum.json` decoding (lenient) and the update-check policy.
final class UpdateManifestTests: XCTestCase {
    func d(_ s: String) -> Date {
        return TestSupport.date(s)
    }

    func manifest(_ json: String) -> UpdateManifest? {
        return UpdateManifest.decode(from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testValidManifest() throws {
        let json = "{\"build\": 61, \"sha\": \"6d5403d9a1b2c3\", \"date\": \"2026-09-27T11:32:00Z\","
            + " \"notes\": \"Ses kısma ×2: Bugün ekranında gösterge\"}"
        let m = try XCTUnwrap(manifest(json))
        XCTAssertEqual(m.build, 61)
        XCTAssertEqual(m.sha, "6d5403d9a1b2c3")
        XCTAssertEqual(m.shortSHA, "6d5403d")
        XCTAssertEqual(m.date, d("2026-09-27T14:32"))      // Istanbul = UTC+3
        XCTAssertEqual(m.notes, "Ses kısma ×2: Bugün ekranında gösterge")
    }

    func testBuildAsNumericString() throws {
        let m = try XCTUnwrap(manifest("{\"build\": \"57\"}"))
        XCTAssertEqual(m.build, 57)
        XCTAssertEqual(try XCTUnwrap(manifest("{\"build\": \" 58 \"}")).build, 58)
    }

    func testMissingOptionalFields() throws {
        let m = try XCTUnwrap(manifest("{\"build\": 12}"))
        XCTAssertEqual(m, UpdateManifest(build: 12))
        XCTAssertEqual(m.sha, "")
        XCTAssertEqual(m.shortSHA, "")
        XCTAssertNil(m.date)
        XCTAssertEqual(m.notes, "")
    }

    func testBadDateBecomesNil() throws {
        let m = try XCTUnwrap(manifest("{\"build\": 12, \"date\": \"dün akşam\", \"notes\": 5, \"sha\": [1]}"))
        XCTAssertEqual(m.build, 12)
        XCTAssertNil(m.date)
        XCTAssertEqual(m.notes, "")
        XCTAssertEqual(m.sha, "")
    }

    func testNonPositiveOrGarbageBuildIsRejected() {
        XCTAssertNil(manifest("{\"build\": 0}"))
        XCTAssertNil(manifest("{\"build\": -4}"))
        XCTAssertNil(manifest("{\"build\": \"yeni\"}"))
        XCTAssertNil(manifest("{\"build\": null}"))
        XCTAssertNil(manifest("{\"sha\": \"abc\"}"))
    }

    func testNotJSONObjectIsRejected() {
        XCTAssertNil(manifest("<html>Not Found</html>"))
        XCTAssertNil(manifest("[{\"build\": 5}]"))
        XCTAssertNil(manifest("42"))
        XCTAssertNil(manifest(""))
    }

    func testNotesAreTrimmedFlattenedAndCut() throws {
        let long = String(repeating: "a", count: 400)
        let m = try XCTUnwrap(manifest("{\"build\": 3, \"notes\": \"" + long + "\"}"))
        XCTAssertEqual(m.notes.count, 300)
        let flat = try XCTUnwrap(manifest("{\"build\": 3, \"notes\": \"  Düzenle\\nwidget'lar\\r\\n  \"}"))
        XCTAssertEqual(flat.notes, "Düzenle widget'lar")
    }

    func testEncodeDecodeRoundTrip() throws {
        let original = UpdateManifest(build: 61, sha: "abcdef0123", date: d("2026-09-27T14:32"), notes: "Takvim")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        XCTAssertEqual(UpdateManifest.decode(from: data), original)
    }

    func testReleaseURLsPointAtSonSurum() {
        XCTAssertTrue(UpdateManifest.manifestURLString.hasSuffix("/releases/download/son-surum/surum.json"))
        XCTAssertTrue(UpdateManifest.ipaURLString.hasSuffix("/releases/download/son-surum/Asist.ipa"))
        XCTAssertTrue(UpdateManifest.unsignedIPAURLString.hasSuffix("/son-surum/Asist-imzasiz.ipa"))
        XCTAssertTrue(UpdateManifest.releasePageURLString.hasSuffix("/releases/tag/son-surum"))
        XCTAssertNotNil(URL(string: UpdateManifest.manifestURLString))
        XCTAssertNil(URL(string: UpdateManifest.manifestURLString)?.query)
    }

    // MARK: - Policy

    func testCheckDisabledIsNeverDue() {
        XCTAssertFalse(UpdatePolicy.isCheckDue(enabled: false, lastCheck: nil, lastAttempt: nil,
                                               now: d("2026-09-27T10:00")))
    }

    func testNeverCheckedIsDue() {
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: nil, lastAttempt: nil,
                                              now: d("2026-09-27T10:00")))
    }

    func testTwelveHourInterval() {
        let now = d("2026-09-27T22:00")
        XCTAssertFalse(UpdatePolicy.isCheckDue(enabled: true, lastCheck: d("2026-09-27T11:00"), lastAttempt: nil,
                                               now: now))                                   // 11 h
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: d("2026-09-27T10:00"), lastAttempt: nil,
                                              now: now))                                    // exactly 12 h
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: d("2026-09-26T08:00"), lastAttempt: nil,
                                              now: now))
    }

    func testClockMovedBack() {
        let now = d("2026-09-27T10:00")
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: d("2026-09-27T12:00"), lastAttempt: nil,
                                              now: now))
        // Within the 5-minute tolerance: treated as "just checked".
        XCTAssertFalse(UpdatePolicy.isCheckDue(enabled: true, lastCheck: d("2026-09-27T10:03"), lastAttempt: nil,
                                               now: now))
    }

    func testRecentFailureWaitsThirtyMinutes() {
        let now = d("2026-09-27T10:00")
        XCTAssertFalse(UpdatePolicy.isCheckDue(enabled: true, lastCheck: nil, lastAttempt: d("2026-09-27T09:45"),
                                               now: now))                                   // 15 min
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: nil, lastAttempt: d("2026-09-27T09:30"),
                                              now: now))                                    // 30 min
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: nil, lastAttempt: d("2026-09-27T11:00"),
                                              now: now))                                    // clock moved back
        // A due 12 h check still waits for the failure back-off.
        XCTAssertFalse(UpdatePolicy.isCheckDue(enabled: true, lastCheck: d("2026-09-26T08:00"),
                                               lastAttempt: d("2026-09-27T09:50"), now: now))
    }

    func testUpdateAvailability() {
        XCTAssertTrue(UpdatePolicy.isUpdateAvailable(latestBuild: 61, installedBuild: 57))
        XCTAssertFalse(UpdatePolicy.isUpdateAvailable(latestBuild: 57, installedBuild: 57))
        XCTAssertFalse(UpdatePolicy.isUpdateAvailable(latestBuild: 55, installedBuild: 57))
        XCTAssertFalse(UpdatePolicy.isUpdateAvailable(latestBuild: 0, installedBuild: 0))
        XCTAssertTrue(UpdatePolicy.isUpdateAvailable(latestBuild: 3, installedBuild: 0))
    }

    func testBannerID() {
        XCTAssertEqual(UpdatePolicy.bannerID(build: 61), "update_61")
    }
}
