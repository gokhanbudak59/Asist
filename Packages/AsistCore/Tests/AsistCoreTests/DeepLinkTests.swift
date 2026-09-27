import Foundation // Linux: URL/UUID/URLComponents must not rely on XCTest re-exporting Foundation
import XCTest
@testable import AsistCore

/// WP8 (04 §3.5.7): every `DeepLink` case survives `url` → `init?(url:)`, the documented URL strings are stable
/// (user shortcuts and notification routing depend on them), and malformed input is rejected, never crashes.
final class DeepLinkTests: XCTestCase {

    // Fixed ids (tests never generate random data).
    private let itemID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private let projectID = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!

    private let allKinds: [ItemKind] = [.reminder, .task, .note, .waiting]

    // MARK: - Helpers

    private func parse(_ string: String, file: StaticString = #filePath, line: UInt = #line) -> DeepLink? {
        guard let url = URL(string: string) else {
            XCTFail("URL(string:) returned nil for " + string, file: file, line: line)
            return nil
        }
        return DeepLink(url: url)
    }

    private func assertRoundTrip(_ link: DeepLink, file: StaticString = #filePath, line: UInt = #line) {
        let url = link.url
        XCTAssertEqual(url.scheme, DeepLink.scheme, file: file, line: line)
        let parsed = DeepLink(url: url)
        XCTAssertEqual(parsed, link, "round trip failed for " + url.absoluteString, file: file, line: line)
        // A second round trip through the absolute string (what a Shortcut or a notification stores).
        let reparsedURL = URL(string: url.absoluteString)
        XCTAssertNotNil(reparsedURL, file: file, line: line)
        if let reparsedURL = reparsedURL {
            XCTAssertEqual(DeepLink(url: reparsedURL), link, file: file, line: line)
        }
    }

    /// Every case, including every listen combination (keeps the list exhaustive when a case is added:
    /// the switch in `testEveryCaseIsCovered` fails to compile first).
    private func everyLink() -> [DeepLink] {
        var links: [DeepLink] = []
        links.append(.listen(kind: nil, projectID: nil))
        links.append(.listen(kind: nil, projectID: projectID))
        for kind in allKinds {
            links.append(.listen(kind: kind, projectID: nil))
            links.append(.listen(kind: kind, projectID: projectID))
        }
        links.append(.compose)
        links.append(.today)
        links.append(.item(itemID))
        links.append(.completeItem(itemID))
        links.append(.endOfDay)
        links.append(.readAgenda)
        links.append(.settingsTriggers)
        return links
    }

    // MARK: - Round trips

    func testEveryCaseRoundTrips() {
        for link in everyLink() {
            assertRoundTrip(link)
        }
    }

    func testEveryCaseIsCovered() {
        // Compile-time exhaustiveness guard: adding a DeepLink case breaks this switch until the test is updated.
        var seen: Set<String> = []
        for link in everyLink() {
            switch link {
            case .listen: seen.insert("listen")
            case .compose: seen.insert("compose")
            case .today: seen.insert("today")
            case .item: seen.insert("item")
            case .completeItem: seen.insert("completeItem")
            case .endOfDay: seen.insert("endOfDay")
            case .readAgenda: seen.insert("readAgenda")
            case .settingsTriggers: seen.insert("settingsTriggers")
            }
        }
        XCTAssertEqual(seen.count, 8)
    }

    func testItemKindCasesAreAllListed() {
        XCTAssertEqual(Set(ItemKind.allCases.map { $0.rawValue }), Set(allKinds.map { $0.rawValue }))
    }

    func testRoundTripWithManyIDs() {
        // Different hex digits in every position (deterministic, no random UUIDs).
        let ids = [
            "00000000-0000-0000-0000-000000000000",
            "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
            "01234567-89AB-CDEF-0123-456789ABCDEF",
            "A1B2C3D4-E5F6-4789-8ABC-DEF012345678"
        ]
        for raw in ids {
            guard let id = UUID(uuidString: raw) else {
                XCTFail("bad fixture " + raw)
                continue
            }
            assertRoundTrip(.item(id))
            assertRoundTrip(.completeItem(id))
            assertRoundTrip(.listen(kind: .note, projectID: id))
        }
    }

    // MARK: - Documented URL strings (04 §3.5.7 comments)

    func testDocumentedURLStrings() {
        XCTAssertEqual(DeepLink.scheme, "asist")
        XCTAssertEqual(DeepLink.compose.url.absoluteString, "asist://yaz")
        XCTAssertEqual(DeepLink.today.url.absoluteString, "asist://bugun")
        XCTAssertEqual(DeepLink.endOfDay.url.absoluteString, "asist://gunsonu")
        XCTAssertEqual(DeepLink.readAgenda.url.absoluteString, "asist://oku")
        XCTAssertEqual(DeepLink.settingsTriggers.url.absoluteString, "asist://ayarlar/tetikleyiciler")
        XCTAssertEqual(DeepLink.listen(kind: nil, projectID: nil).url.absoluteString, "asist://dinle")
    }

    func testDocumentedItemURLStrings() {
        let idText = itemID.uuidString
        XCTAssertEqual(DeepLink.item(itemID).url.absoluteString, "asist://kayit/" + idText)
        XCTAssertEqual(DeepLink.completeItem(itemID).url.absoluteString, "asist://kayit/" + idText + "?eylem=yaptim")
    }

    func testDocumentedListenURLStrings() {
        let projectText = projectID.uuidString
        XCTAssertEqual(DeepLink.listen(kind: .reminder, projectID: nil).url.absoluteString,
                       "asist://dinle?tur=hatirlatma")
        XCTAssertEqual(DeepLink.listen(kind: .task, projectID: nil).url.absoluteString, "asist://dinle?tur=gorev")
        XCTAssertEqual(DeepLink.listen(kind: .note, projectID: nil).url.absoluteString, "asist://dinle?tur=not")
        XCTAssertEqual(DeepLink.listen(kind: .waiting, projectID: nil).url.absoluteString, "asist://dinle?tur=takip")
        XCTAssertEqual(DeepLink.listen(kind: nil, projectID: projectID).url.absoluteString,
                       "asist://dinle?proje=" + projectText)
        XCTAssertEqual(DeepLink.listen(kind: .task, projectID: projectID).url.absoluteString,
                       "asist://dinle?tur=gorev&proje=" + projectText)
    }

    // MARK: - Parsing hand-written URLs (Shortcuts "URL Aç", Back Tap recipes)

    func testParsesHandWrittenURLs() {
        XCTAssertEqual(parse("asist://bugun"), .today)
        XCTAssertEqual(parse("asist://yaz"), .compose)
        XCTAssertEqual(parse("asist://gunsonu"), .endOfDay)
        XCTAssertEqual(parse("asist://oku"), .readAgenda)
        XCTAssertEqual(parse("asist://ayarlar/tetikleyiciler"), .settingsTriggers)
        XCTAssertEqual(parse("asist://dinle"), .listen(kind: nil, projectID: nil))
        XCTAssertEqual(parse("asist://dinle?tur=gorev"), .listen(kind: .task, projectID: nil))
        XCTAssertEqual(parse("asist://dinle?tur=takip"), .listen(kind: .waiting, projectID: nil))
    }

    func testTrailingSlashAndExtraPathAreTolerated() {
        XCTAssertEqual(parse("asist://bugun/"), .today)
        XCTAssertEqual(parse("asist://dinle/"), .listen(kind: nil, projectID: nil))
        // Any "ayarlar" path opens the trigger settings (the only settings deep link in v1.0).
        XCTAssertEqual(parse("asist://ayarlar"), .settingsTriggers)
        XCTAssertEqual(parse("asist://kayit/" + itemID.uuidString + "/"), .item(itemID))
    }

    func testSchemeAndHostAreCaseInsensitive() {
        XCTAssertEqual(parse("ASIST://BUGUN"), .today)
        XCTAssertEqual(parse("Asist://Dinle?tur=gorev"), .listen(kind: .task, projectID: nil))
        XCTAssertEqual(parse("asist://KAYIT/" + itemID.uuidString), .item(itemID))
    }

    func testKindCodeIsCaseInsensitive() {
        XCTAssertEqual(parse("asist://dinle?tur=GOREV"), .listen(kind: .task, projectID: nil))
        XCTAssertEqual(parse("asist://dinle?tur=Hatirlatma"), .listen(kind: .reminder, projectID: nil))
    }

    func testLowercaseUUIDIsAccepted() {
        let lower = itemID.uuidString.lowercased()
        XCTAssertEqual(parse("asist://kayit/" + lower), .item(itemID))
        XCTAssertEqual(parse("asist://kayit/" + lower + "?eylem=yaptim"), .completeItem(itemID))
        let lowerProject = projectID.uuidString.lowercased()
        XCTAssertEqual(parse("asist://dinle?proje=" + lowerProject), .listen(kind: nil, projectID: projectID))
    }

    func testQueryOrderDoesNotMatter() {
        let projectText = projectID.uuidString
        XCTAssertEqual(parse("asist://dinle?proje=" + projectText + "&tur=not"),
                       .listen(kind: .note, projectID: projectID))
    }

    // MARK: - Lenient degradation (unknown values fall back, never fail the whole link)

    func testUnknownKindCodeFallsBackToPlainListen() {
        XCTAssertEqual(parse("asist://dinle?tur=bilinmeyen"), .listen(kind: nil, projectID: nil))
        XCTAssertEqual(parse("asist://dinle?tur="), .listen(kind: nil, projectID: nil))
    }

    func testMalformedProjectIsIgnored() {
        XCTAssertEqual(parse("asist://dinle?proje=bozuk"), .listen(kind: nil, projectID: nil))
        XCTAssertEqual(parse("asist://dinle?tur=gorev&proje=123"), .listen(kind: .task, projectID: nil))
    }

    func testUnknownActionOpensTheItem() {
        XCTAssertEqual(parse("asist://kayit/" + itemID.uuidString + "?eylem=sil"), .item(itemID))
        XCTAssertEqual(parse("asist://kayit/" + itemID.uuidString + "?eylem="), .item(itemID))
    }

    func testUnknownQueryItemsAreIgnored() {
        XCTAssertEqual(parse("asist://bugun?kaynak=widget"), .today)
        XCTAssertEqual(parse("asist://dinle?tur=gorev&x=1"), .listen(kind: .task, projectID: nil))
    }

    // MARK: - Rejection

    func testRejectsForeignSchemes() {
        XCTAssertNil(parse("https://bugun"))
        XCTAssertNil(parse("shortcuts://run-shortcut?name=Asist"))
        XCTAssertNil(parse("asistan://bugun"))
    }

    func testRejectsUnknownHosts() {
        XCTAssertNil(parse("asist://bilinmeyen"))
        XCTAssertNil(parse("asist://ayar"))
        XCTAssertNil(parse("asist://kayitlar/" + itemID.uuidString))
    }

    func testRejectsMissingHost() {
        XCTAssertNil(parse("asist:bugun"))
        XCTAssertNil(parse("asist:///bugun"))
    }

    func testRejectsItemWithoutValidID() {
        XCTAssertNil(parse("asist://kayit"))
        XCTAssertNil(parse("asist://kayit/"))
        XCTAssertNil(parse("asist://kayit/abc"))
        XCTAssertNil(parse("asist://kayit/abc?eylem=yaptim"))
        XCTAssertNil(parse("asist://kayit?eylem=yaptim"))
        // Truncated UUID.
        let truncated = String(itemID.uuidString.dropLast())
        XCTAssertNil(parse("asist://kayit/" + truncated))
    }

    // MARK: - Kind codes

    func testKindCodesRoundTrip() {
        for kind in allKinds {
            let code = DeepLink.kindCode(kind)
            XCTAssertEqual(DeepLink.kind(fromCode: code), kind, code)
            // Codes are ASCII lowercase (safe in URLs and Shortcuts without percent-encoding).
            XCTAssertEqual(code, code.lowercased())
            XCTAssertTrue(code.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isAlphabetic }, code)
        }
    }

    func testKindCodesAreExact() {
        XCTAssertEqual(DeepLink.kindCode(.reminder), "hatirlatma")
        XCTAssertEqual(DeepLink.kindCode(.task), "gorev")
        XCTAssertEqual(DeepLink.kindCode(.note), "not")
        XCTAssertEqual(DeepLink.kindCode(.waiting), "takip")
    }

    func testKindCodesAreDistinct() {
        let codes = allKinds.map { DeepLink.kindCode($0) }
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testUnknownKindCodes() {
        XCTAssertNil(DeepLink.kind(fromCode: ""))
        XCTAssertNil(DeepLink.kind(fromCode: "hatırlatma"))   // Turkish letters are not codes
        XCTAssertNil(DeepLink.kind(fromCode: "görev"))
        XCTAssertNil(DeepLink.kind(fromCode: "reminder"))
        XCTAssertNil(DeepLink.kind(fromCode: " gorev"))
    }

    // MARK: - Distinctness

    func testDistinctCasesProduceDistinctURLs() {
        let strings = everyLink().map { $0.url.absoluteString }
        XCTAssertEqual(Set(strings).count, strings.count)
    }
}
