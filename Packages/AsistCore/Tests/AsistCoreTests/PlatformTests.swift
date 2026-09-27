import Foundation // WP0-FIX: Data/URL/ISO8601DateFormatter/TimeZone must not rely on XCTest re-exporting Foundation on Linux
import XCTest
@testable import AsistCore

final class PlatformTests: XCTestCase {

    private let iso = ISO8601DateFormatter()

    func testParsesProfileWrappedInBinaryEnvelope() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Name</key><string>iOS Team Provisioning Profile: com.gokhanbudak.asist</string>
            <key>TeamName</key><string>Gökhan Budak</string>
            <key>TeamIdentifier</key><array><string>ABCDE12345</string></array>
            <key>CreationDate</key><date>2026-09-27T10:00:00Z</date>
            <key>ExpirationDate</key><date>2026-10-04T10:00:00Z</date>
            <key>ProvisionedDevices</key><array><string>00008120-000000000000001E</string></array>
            <key>Entitlements</key>
            <dict>
                <key>application-identifier</key><string>ABCDE12345.com.gokhanbudak.asist</string>
                <key>com.apple.security.application-groups</key>
                <array><string>group.com.gokhanbudak.asist.ABCDE12345</string></array>
                <key>get-task-allow</key><true/>
            </dict>
        </dict>
        </plist>
        """
        var blob = Data([0x30, 0x82, 0x3F, 0x12, 0x06, 0x09, 0x2A, 0x86, 0x48, 0xFF, 0xFE])  // sahte CMS başı
        blob.append(Data(xml.utf8))
        blob.append(Data([0xA0, 0x82, 0x0D, 0x00, 0xFF, 0x00]))                             // sahte imza kuyruğu

        let info = try XCTUnwrap(ProvisioningProfileReader.parse(profileData: blob))
        XCTAssertEqual(info.expirationDate, iso.date(from: "2026-10-04T10:00:00Z"))
        XCTAssertEqual(info.creationDate, iso.date(from: "2026-09-27T10:00:00Z"))
        XCTAssertEqual(info.teamIdentifier, "ABCDE12345")
        XCTAssertEqual(info.teamName, "Gökhan Budak")
        XCTAssertEqual(info.appGroups, ["group.com.gokhanbudak.asist.ABCDE12345"])
        XCTAssertTrue(info.getTaskAllow)
        XCTAssertEqual(info.provisionedDeviceCount, 1)
        XCTAssertTrue(info.looksLikeFreeAppleID)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(ProvisioningProfileReader.parse(profileData: Data([0x00, 0x01, 0x02])))
        XCTAssertNil(ProvisioningProfileReader.parse(profileData: Data("<?xml version=\"1.0\"?><plist>".utf8)))
    }

    func testIstanbulTimeZoneAvailable() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let date = try XCTUnwrap(iso.date(from: "2026-09-27T09:00:00Z"))
        XCTAssertEqual(tz.secondsFromGMT(for: date), 3 * 3600)
    }

    func testWarningsAvoidNightAndPast() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let expiration = try XCTUnwrap(iso.date(from: "2026-10-04T07:00:00Z"))   // 10:00 İstanbul
        let now = try XCTUnwrap(iso.date(from: "2026-09-27T07:00:00Z"))
        let dates = SigningExpiryPlanner.warningDates(expiration: expiration, now: now, calendar: calendar)
        // 48 s: 02.10 10:00 | 24 s: 03.10 10:00 | 4 s: 04.10 06:00 -> gece -> 03.10 21:00 (18:00Z)
        let expected = ["2026-10-02T07:00:00Z", "2026-10-03T07:00:00Z", "2026-10-03T18:00:00Z"]
            .compactMap { iso.date(from: $0) }
        XCTAssertEqual(dates, expected)
    }

    func testResolverTriesExpectedThenRenamedGroups() {
        let candidates = AppGroupResolver.candidates(
            expected: "group.com.gokhanbudak.asist",
            infoPlistGroups: ["group.com.gokhanbudak.asist.ABCDE12345"],
            profileGroups: ["group.com.gokhanbudak.asist.ABCDE12345", "group.baska.uygulama"])
        XCTAssertEqual(candidates, ["group.com.gokhanbudak.asist", "group.com.gokhanbudak.asist.ABCDE12345"])

        let resolved = AppGroupResolver.resolve(
            expected: "group.com.gokhanbudak.asist",
            infoPlistGroups: [],
            profileGroups: ["group.com.gokhanbudak.asist.ABCDE12345"]) { identifier in
                identifier.hasSuffix("ABCDE12345") ? URL(fileURLWithPath: "/tmp/grup") : nil
            }
        XCTAssertEqual(resolved?.identifier, "group.com.gokhanbudak.asist.ABCDE12345")

        let none = AppGroupResolver.resolve(expected: "group.com.gokhanbudak.asist",
                                            infoPlistGroups: [], profileGroups: []) { _ in nil }
        XCTAssertNil(none)
    }
}
