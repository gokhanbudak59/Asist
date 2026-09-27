import XCTest
@testable import AsistCore

/// 02 §3.1 (locale-free Turkish lowercase), §3.2 (fold table) and 04 §3.3.3 (searchKey, truncated).
final class TurkishTextTests: XCTestCase {

    func testLowerUsesDottedAndDotlessI() {
        XCTAssertEqual(TurkishText.lower("IŞIK"), "ışık")
        XCTAssertEqual(TurkishText.lower("İzmir"), "izmir")
        XCTAssertEqual(TurkishText.lower("ISPARTA"), "ısparta")
        XCTAssertEqual(TurkishText.lower("ÇAĞRI ÖĞÜT ŞÜKRÜ"), "çağrı öğüt şükrü")
        XCTAssertEqual(TurkishText.lower("PLC-500 Hattı"), "plc-500 hattı")
        XCTAssertEqual(TurkishText.lower(""), "")
    }

    func testLowerAppliesCanonicalComposition() {
        // Dictation may emit "I" + U+0307 (combining dot above); NFC composes it to "İ", which lowers to "i".
        XCTAssertEqual(TurkishText.lower("I\u{0307}zmir"), "izmir")
    }

    func testUpperAndUpperFirst() {
        XCTAssertEqual(TurkishText.upper("istanbul"), "İSTANBUL")
        XCTAssertEqual(TurkishText.upper("ılık"), "ILIK")
        XCTAssertEqual(TurkishText.upperFirst("izmir"), "İzmir")
        XCTAssertEqual(TurkishText.upperFirst("ışık"), "Işık")
        XCTAssertEqual(TurkishText.upperFirst("teklif konusu"), "Teklif konusu")
        XCTAssertEqual(TurkishText.upperFirst(""), "")
    }

    func testFoldTable() {
        XCTAssertEqual(TurkishText.fold("Çağrı Öğüt Şükrü"), "cagri ogut sukru")
        XCTAssertEqual(TurkishText.fold("IŞIK"), "isik")
        XCTAssertEqual(TurkishText.fold("İzmir"), "izmir")
        XCTAssertEqual(TurkishText.fold("öğle salı"), "ogle sali")
        XCTAssertEqual(TurkishText.fold("Kâğıt hâlâ Îmam Ûmit"), "kagit hala imam umit")
    }

    func testFoldHandlesCombiningDotAbove() {
        // "i" + U+0307 has no precomposed form; the fold table maps the cluster to "i" (02 §3.2 last column).
        XCTAssertEqual(TurkishText.fold("i\u{0307}zmir"), "izmir")
    }

    func testFoldIsIdempotent() {
        let samples = ["Çağrı Öğüt", "IŞIK", "İzmir'de toplantı", "Kâğıt"]
        for sample in samples {
            let once = TurkishText.fold(sample)
            XCTAssertEqual(TurkishText.fold(once), once, sample)
        }
    }

    func testSearchKey() {
        XCTAssertEqual(TurkishText.searchKey("Ahmet'e  teklif, gönder!"), "ahmete teklif gonder")
        XCTAssertEqual(TurkishText.searchKey("  İSTANBUL\u{2019}da  "), "istanbulda")
        XCTAssertEqual(TurkishText.searchKey("PLC-500 hattı"), "plc 500 hatti")
        XCTAssertEqual(TurkishText.searchKey("...!!"), "")
    }

    func testTruncated() {
        XCTAssertEqual(TurkishText.truncated("Kısa başlık", max: 60), "Kısa başlık")
        XCTAssertEqual(TurkishText.truncated("Teklif konusu hakkında Ahmet'e dönüş yap", max: 20), "Teklif konusu…")
        XCTAssertEqual(TurkishText.truncated("Abcdefghijklmnop", max: 6), "Abcde…")
    }
}
